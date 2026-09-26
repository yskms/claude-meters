import Foundation
import Security

// PoC only: confirms whether a distinct (optionally code-signed / sandboxed)
// process can read Claude Code's own Keychain item and call the Usage API.
// Prints only status flags — never the token or the response body.

func log(_ s: String) { print(s); fflush(stdout) }

let query: [String: Any] = [
    kSecClass as String: kSecClassGenericPassword,
    kSecAttrService as String: "Claude Code-credentials",
    kSecReturnData as String: true,
    kSecMatchLimit as String: kSecMatchLimitOne,
]

var item: CFTypeRef?
let status = SecItemCopyMatching(query as CFDictionary, &item)
let statusMessage = SecCopyErrorMessageString(status, nil) as String? ?? "unknown"
log("KEYCHAIN_OSSTATUS: \(status) (\(statusMessage))")

guard status == errSecSuccess, let data = item as? Data else {
    log("KEYCHAIN_ACCESS: failed")
    exit(1)
}
log("KEYCHAIN_ACCESS: success")

guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
    log("JSON_PARSE: failed")
    exit(1)
}
log("JSON_PARSE: success")

var token: String?
if let t = json["accessToken"] as? String {
    token = t
} else if let oauth = json["claudeAiOauth"] as? [String: Any], let t = oauth["accessToken"] as? String {
    token = t
}

guard let accessToken = token else {
    log("TOKEN_EXTRACT: failed")
    exit(1)
}
log("TOKEN_EXTRACT: success (len=\(accessToken.count))")

var request = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")

let semaphore = DispatchSemaphore(value: 0)
URLSession.shared.dataTask(with: request) { data, response, error in
    defer { semaphore.signal() }
    if let error = error {
        log("HTTP_ERROR: \(error.localizedDescription)")
        return
    }
    guard let http = response as? HTTPURLResponse else {
        log("HTTP_STATUS: unknown")
        return
    }
    log("HTTP_STATUS: \(http.statusCode)")
    guard let data = data,
          let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        log("BODY_PARSE: failed")
        return
    }
    let fiveHour = obj["five_hour"] as? [String: Any]
    let sevenDay = obj["seven_day"] as? [String: Any]
    log("FIVE_HOUR_PRESENT: \(fiveHour != nil)")
    log("FIVE_HOUR_HAS_UTILIZATION: \(fiveHour?["utilization"] != nil)")
    log("FIVE_HOUR_HAS_RESETS_AT: \(fiveHour?["resets_at"] != nil)")
    log("SEVEN_DAY_PRESENT: \(sevenDay != nil)")
    log("SEVEN_DAY_HAS_UTILIZATION: \(sevenDay?["utilization"] != nil)")
    log("SEVEN_DAY_HAS_RESETS_AT: \(sevenDay?["resets_at"] != nil)")
}.resume()
semaphore.wait()
