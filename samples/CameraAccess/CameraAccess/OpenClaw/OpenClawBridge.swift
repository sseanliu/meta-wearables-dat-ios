import CoreLocation
import Foundation

@MainActor
class OpenClawBridge: ObservableObject {
  @Published var lastToolCallStatus: ToolCallStatus = .idle

  private let session: URLSession
  private var sessionKey: String

  init() {
    let config = URLSessionConfiguration.default
    // OpenClaw tasks can take a while (podcasts/videos). Keep iOS-side timeouts generous,
    // but do NOT wait indefinitely for connectivity, otherwise the UI looks "stuck forever".
    let requestTimeoutSec: Double = 5 * 60
    config.timeoutIntervalForRequest = requestTimeoutSec
    config.timeoutIntervalForResource = requestTimeoutSec
    config.waitsForConnectivity = false
    config.allowsConstrainedNetworkAccess = true
    config.allowsExpensiveNetworkAccess = true
    self.session = URLSession(configuration: config)
    self.sessionKey = OpenClawBridge.newSessionKey()
  }

  func resetSession() {
    sessionKey = OpenClawBridge.newSessionKey()
    NSLog("[OpenClaw] New session: %@", sessionKey)
  }

  private static func newSessionKey() -> String {
    let ts = ISO8601DateFormatter().string(from: Date())
    let agent = GeminiConfig.openClawAgentId.trimmingCharacters(in: .whitespacesAndNewlines)
    let agentPart = agent.isEmpty ? "openclaw" : agent
    return "visionclaw:\(AppSettings.deviceId()):\(agentPart):\(ts)"
  }

  // MARK: - Agent Chat (session continuity via x-openclaw-session-key header)

  func delegateTask(
    task: String,
    toolName: String = "execute"
  ) async -> ToolResult {
    lastToolCallStatus = .executing(toolName)

    guard GeminiConfig.isOpenClawConfigured else {
      lastToolCallStatus = .failed(toolName, "OpenClaw not configured")
      return .failure("OpenClaw not configured. Open Settings and set Host + Token.")
    }

    guard let url = GeminiConfig.openClawURL(path: "/v1/chat/completions") else {
      lastToolCallStatus = .failed(toolName, "Invalid URL")
      return .failure("Invalid gateway URL")
    }

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("Bearer \(GeminiConfig.openClawGatewayToken)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")

    let baseAgentId = GeminiConfig.openClawAgentId.trimmingCharacters(in: .whitespacesAndNewlines)
    let agentIdForRequest = baseAgentId
    let sessionKeyForRequest = sessionKey
    var effectiveTask = task.trimmingCharacters(in: .whitespacesAndNewlines)

    request.setValue(sessionKeyForRequest, forHTTPHeaderField: "x-openclaw-session-key")
    if !agentIdForRequest.isEmpty {
      request.setValue(agentIdForRequest, forHTTPHeaderField: "x-openclaw-agent-id")
    }

    if GeminiConfig.shareLocationWithJarvis {
      if let loc = await LocationService.shared.currentLocation(timeoutSeconds: 2.5) {
        let ts = ISO8601DateFormatter().string(from: loc.timestamp)
        let acc = max(0, loc.horizontalAccuracy)
        effectiveTask += """

        [device_location]
        lat: \(loc.coordinate.latitude)
        lon: \(loc.coordinate.longitude)
        accuracy_m: \(acc)
        timestamp: \(ts)
        [/device_location]
        """
      }
    }

    // Always include device-local time context so the VM (which may be in a different timezone)
    // interprets scheduling and "2pm Thursday" correctly.
    let tz = TimeZone.autoupdatingCurrent
    let offsetSec = tz.secondsFromGMT()
    let sign = offsetSec >= 0 ? "+" : "-"
    let absSec = abs(offsetSec)
    let hh = absSec / 3600
    let mm = (absSec % 3600) / 60
    let offset = String(format: "%@%02d:%02d", sign, hh, mm)

    let iso = ISO8601DateFormatter()
    iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    iso.timeZone = tz
    let localNow = iso.string(from: Date())

    effectiveTask += """

    [device_time]
    timezone: \(tz.identifier)
    utc_offset: \(offset)
    local_now: \(localNow)
    interpret_dates_and_times_in_this_request_as: \(tz.identifier)
    [/device_time]
    """

    let model = agentIdForRequest.isEmpty ? "openclaw" : "openclaw:\(agentIdForRequest)"
    let body: [String: Any] = [
      "model": model,
      "user": GeminiConfig.openClawUser,
      "messages": [
        ["role": "user", "content": effectiveTask]
      ],
      "stream": false
    ]

    do {
      request.httpBody = try JSONSerialization.data(withJSONObject: body)
      let (data, response) = try await session.data(for: request)
      let httpResponse = response as? HTTPURLResponse

      guard let statusCode = httpResponse?.statusCode, (200...299).contains(statusCode) else {
        let code = httpResponse?.statusCode ?? 0
        let bodyStr = String(data: data, encoding: .utf8) ?? "no body"
        NSLog("[OpenClaw] Chat failed: HTTP %d - %@", code, String(bodyStr.prefix(200)))
        lastToolCallStatus = .failed(toolName, "HTTP \(code)")
        return .failure("Agent returned HTTP \(code)")
      }

      if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
         let choices = json["choices"] as? [[String: Any]],
         let first = choices.first,
         let message = first["message"] as? [String: Any],
         let content = message["content"] as? String {
        NSLog("[OpenClaw] Agent result: %@", String(content.prefix(200)))
        lastToolCallStatus = .completed(toolName)
        return .success(content)
      }

      let raw = String(data: data, encoding: .utf8) ?? "OK"
      NSLog("[OpenClaw] Agent raw: %@", String(raw.prefix(200)))
      lastToolCallStatus = .completed(toolName)
      return .success(raw)
    } catch is CancellationError {
      lastToolCallStatus = .cancelled(toolName)
      return .failure("Cancelled")
    } catch {
      NSLog("[OpenClaw] Agent error: %@", error.localizedDescription)
      lastToolCallStatus = .failed(toolName, error.localizedDescription)
      return .failure("Agent error: \(error.localizedDescription)")
    }
  }
}
