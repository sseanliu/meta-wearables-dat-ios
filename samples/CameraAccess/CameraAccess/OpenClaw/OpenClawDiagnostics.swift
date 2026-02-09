import Foundation

enum OpenClawDiagnostics {
  struct ProbeResult {
    var ok: Bool
    var detail: String
  }

  static func health(
    host: String,
    port: Int
  ) async -> ProbeResult {
    guard let url = openClawURL(host: host, port: port, path: "/health") else {
      return ProbeResult(ok: false, detail: "Invalid OpenClaw base URL")
    }

    var req = URLRequest(url: url)
    req.httpMethod = "GET"

    do {
      let (data, resp) = try await URLSession.shared.data(for: req)
      let http = resp as? HTTPURLResponse
      let status = http?.statusCode ?? 0
      let body = String(data: data, encoding: .utf8) ?? ""
      if (200...299).contains(status) {
        return ProbeResult(ok: true, detail: "OK (\(status)) \(body.prefix(120))")
      }
      return ProbeResult(ok: false, detail: "HTTP \(status) \(body.prefix(200))")
    } catch {
      return ProbeResult(ok: false, detail: error.localizedDescription)
    }
  }

  static func chatPing(
    host: String,
    port: Int,
    gatewayToken: String,
    agentId: String,
    user: String
  ) async -> ProbeResult {
    guard let url = openClawURL(host: host, port: port, path: "/v1/chat/completions") else {
      return ProbeResult(ok: false, detail: "Invalid OpenClaw base URL")
    }

    var req = URLRequest(url: url)
    req.httpMethod = "POST"
    req.setValue("Bearer \(gatewayToken)", forHTTPHeaderField: "Authorization")
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    if !agentId.isEmpty {
      req.setValue(agentId, forHTTPHeaderField: "x-openclaw-agent-id")
    }

    let model = agentId.isEmpty ? "openclaw" : "openclaw:\(agentId)"
    let body: [String: Any] = [
      "model": model,
      "user": user,
      "messages": [
        ["role": "user", "content": "ping"]
      ],
      "stream": false,
    ]

    do {
      req.httpBody = try JSONSerialization.data(withJSONObject: body)
      let (data, resp) = try await URLSession.shared.data(for: req)
      let http = resp as? HTTPURLResponse
      let status = http?.statusCode ?? 0
      let raw = String(data: data, encoding: .utf8) ?? ""
      if !(200...299).contains(status) {
        return ProbeResult(ok: false, detail: "HTTP \(status) \(raw.prefix(200))")
      }

      if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
         let choices = json["choices"] as? [[String: Any]],
         let first = choices.first,
         let message = first["message"] as? [String: Any],
         let content = message["content"] as? String {
        return ProbeResult(ok: true, detail: "OK (\(status)) \(content.prefix(200))")
      }

      return ProbeResult(ok: true, detail: "OK (\(status)) \(raw.prefix(200))")
    } catch {
      return ProbeResult(ok: false, detail: error.localizedDescription)
    }
  }

  private static func openClawURL(host: String, port: Int, path: String) -> URL? {
    let raw = host.trimmingCharacters(in: .whitespacesAndNewlines)
    if raw.isEmpty { return nil }

    // Handle bare host input like "jarvis.tailnet.ts.net".
    let withScheme: String
    if raw.hasPrefix("http://") || raw.hasPrefix("https://") {
      withScheme = raw
    } else {
      withScheme = "https://\(raw)"
    }

    guard var comps = URLComponents(string: withScheme) else { return nil }
    if comps.port == nil {
      comps.port = port
    }
    comps.path = path.hasPrefix("/") ? path : "/" + path
    comps.query = nil
    comps.fragment = nil
    return comps.url
  }
}

