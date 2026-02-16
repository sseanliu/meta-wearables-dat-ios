import Foundation

@MainActor
class ToolCallRouter {
  private let bridge: OpenClawBridge
  private let onToolFinished: ((ToolResult) -> Void)?
  private var inFlightTasks: [String: Task<Void, Never>] = [:]

  init(
    bridge: OpenClawBridge,
    onToolFinished: ((ToolResult) -> Void)? = nil
  ) {
    self.bridge = bridge
    self.onToolFinished = onToolFinished
  }

  /// Route a tool call from Gemini to OpenClaw. Calls sendResponse with the
  /// JSON dictionary to send back as a toolResponse message.
  func handleToolCall(
    _ call: GeminiFunctionCall,
    sendResponse: @escaping ([String: Any]) -> Void
  ) {
    let callId = call.id
    let callName = call.name

    NSLog("[ToolCall] Received: %@ (id: %@) args: %@",
          callName, callId, String(describing: call.args))

    // Some spoken phrases are local app controls (video on/off, stop) and should not
    // be delegated to OpenClaw. Gemini may still emit an `execute(task)` for them
    // based on the system prompt. We short-circuit so the session doesn't hang
    // waiting on a slow tool call and so audio keeps flowing.
    if callName == "execute" {
      let taskDesc = call.args["task"] as? String ?? String(describing: call.args)
      if let local = localAppControl(task: taskDesc) {
        NSLog("[ToolCall] Local app control: %@", local.logLabel)
        NotificationCenter.default.post(name: local.notificationName, object: nil)
        bridge.lastToolCallStatus = .completed(callName)
        let result = ToolResult.success(local.responseText)
        onToolFinished?(result)
        let response = buildToolResponse(callId: callId, name: callName, result: result)
        sendResponse(response)
        return
      }
    }

    let task = Task { @MainActor in
      defer { self.inFlightTasks.removeValue(forKey: callId) }

      let taskDesc = call.args["task"] as? String ?? String(describing: call.args)
      let result = await bridge.delegateTask(task: taskDesc, toolName: callName)

      guard !Task.isCancelled else {
        NSLog("[ToolCall] Task %@ was cancelled, skipping response", callId)
        return
      }

      NSLog("[ToolCall] Result for %@ (id: %@): %@",
            callName, callId, String(describing: result))

      self.onToolFinished?(result)

      let response = self.buildToolResponse(callId: callId, name: callName, result: result)
      sendResponse(response)
    }

    inFlightTasks[callId] = task
  }

  /// Cancel specific in-flight tool calls (from toolCallCancellation)
  func cancelToolCalls(ids: [String]) {
    for id in ids {
      if let task = inFlightTasks[id] {
        NSLog("[ToolCall] Cancelling in-flight call: %@", id)
        task.cancel()
        inFlightTasks.removeValue(forKey: id)
      }
    }
    bridge.lastToolCallStatus = .cancelled(ids.first ?? "unknown")
  }

  /// Cancel all in-flight tool calls (on session stop)
  func cancelAll() {
    for (id, task) in inFlightTasks {
      NSLog("[ToolCall] Cancelling in-flight call: %@", id)
      task.cancel()
    }
    inFlightTasks.removeAll()
  }

  // MARK: - Private

  private func buildToolResponse(
    callId: String,
    name: String,
    result: ToolResult
  ) -> [String: Any] {
    return [
      "toolResponse": [
        "functionResponses": [
          [
            "id": callId,
            "name": name,
            "response": result.responseValue
          ]
        ]
      ]
    ]
  }

  private struct LocalControl {
    let logLabel: String
    let notificationName: Notification.Name
    let responseText: String
  }

  private func localAppControl(task: String) -> LocalControl? {
    let tokens = normalizeTokens(task)

    // Drop fillers.
    var t = tokens
    while let first = t.first, ["hey", "ok", "okay", "please", "um", "uh"].contains(first) {
      t.removeFirst()
    }
    if t.isEmpty { return nil }

    // First try explicit user phrasing with an anchored "jarvis" token.
    if t.count >= 3, t[0] == "jarvis", let cmd = parseVideoCommandRest(Array(t.dropFirst())) {
      return cmd
    }
    if t.count >= 3, t.last == "jarvis", let cmd = parseVideoCommandRest(Array(t.dropLast())) {
      return cmd
    }

    // Gemini can rewrite voice commands before emitting execute(task), often dropping
    // the "jarvis" token (e.g. "turn video on"). Catch those to avoid accidental
    // delegation of local app controls to OpenClaw, which can stall audio.
    if let cmd = parseLooseVideoCommand(tokens: t) {
      return cmd
    }
    return nil
  }

  private func parseVideoCommandRest(_ rest: [String]) -> LocalControl? {
    if rest.count >= 2, ["video", "camera", "vision"].contains(rest[0]) {
      if isVideoOnWord(rest[1]) { return videoOnControl() }
      if isVideoOffWord(rest[1]) { return videoOffControl() }
    }
    if rest.count >= 3, rest[0] == "turn", ["video", "camera", "vision"].contains(rest[1]) {
      if isVideoOnWord(rest[2]) { return videoOnControl() }
      if isVideoOffWord(rest[2]) { return videoOffControl() }
    }
    return nil
  }

  private func parseLooseVideoCommand(tokens: [String]) -> LocalControl? {
    if tokens.isEmpty { return nil }
    let media = Set(["video", "camera", "vision"])

    // "video on/off", "camera enable/disable"
    if tokens.count >= 2, media.contains(tokens[0]) {
      if isVideoOnWord(tokens[1]) { return videoOnControl() }
      if isVideoOffWord(tokens[1]) { return videoOffControl() }
    }

    // "turn video on", "switch camera off", "set vision on"
    if tokens.count >= 3, ["turn", "switch", "set"].contains(tokens[0]), media.contains(tokens[1]) {
      if isVideoOnWord(tokens[2]) { return videoOnControl() }
      if isVideoOffWord(tokens[2]) { return videoOffControl() }
    }

    // "turn on video", "turn off camera"
    if tokens.count >= 3, ["turn", "switch", "set"].contains(tokens[0]), media.contains(tokens[2]) {
      if isVideoOnWord(tokens[1]) { return videoOnControl() }
      if isVideoOffWord(tokens[1]) { return videoOffControl() }
    }

    // "enable video", "disable camera", "resume vision", "stop video"
    if tokens.count >= 2, media.contains(tokens[1]) {
      if ["enable", "start", "resume"].contains(tokens[0]) { return videoOnControl() }
      if ["disable", "stop", "pause"].contains(tokens[0]) { return videoOffControl() }
    }

    return nil
  }

  private func isVideoOnWord(_ word: String) -> Bool {
    return ["on", "enable", "enabled", "start", "resume"].contains(word)
  }

  private func isVideoOffWord(_ word: String) -> Bool {
    return ["off", "disable", "disabled", "stop", "pause"].contains(word)
  }

  private func videoOnControl() -> LocalControl {
    return LocalControl(
      logLabel: "video_on",
      notificationName: .jarvisVideoOnRequested,
      responseText: "Video enabled."
    )
  }

  private func videoOffControl() -> LocalControl {
    return LocalControl(
      logLabel: "video_off",
      notificationName: .jarvisVideoOffRequested,
      responseText: "Video disabled."
    )
  }

  private func normalizeTokens(_ input: String) -> [String] {
    let lower = input.lowercased()
    var out = ""
    out.reserveCapacity(lower.count)
    for scalar in lower.unicodeScalars {
      if CharacterSet.alphanumerics.contains(scalar) {
        out.unicodeScalars.append(scalar)
      } else {
        out.append(" ")
      }
    }
    return out.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" }).map(String.init)
  }
}
