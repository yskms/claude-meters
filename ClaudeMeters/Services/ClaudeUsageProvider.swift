import Foundation
import os

/// Reads Claude Code's own locally-stored OAuth credential (never manages
/// credentials of its own) and calls Anthropic's usage endpoint.
///
/// This endpoint (`/api/oauth/usage`) is undocumented — see
/// docs/REQUIREMENTS.md "開発前提・技術検証" for the PoC that verified it
/// and the risks of depending on it. Session/Weekly reset timestamps are
/// used exactly as returned; this type never computes a reset time itself.
final class ClaudeUsageProvider: UsageProvider {
    private let keychainService = "Claude Code-credentials"
    /// Long enough to type a password if `security` itself prompts (e.g. to
    /// unlock a locked keychain), yet bounded so the update loop can't stall.
    private let securityCLITimeout: TimeInterval = 60
    private let usageURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    /// Failures are logged at .error so they persist and can be reviewed
    /// later with `log show --predicate 'subsystem == "com.yskms.ClaudeMeters"'`.
    /// The access token is never logged.
    private static let logger = Logger(subsystem: "com.yskms.ClaudeMeters", category: "usage")

    func fetchUsage() async throws -> UsageSnapshot {
        let token = try readAccessToken()

        var request = URLRequest(url: usageURL)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch let urlError as URLError where urlError.code == .cancelled {
            throw CancellationError()
        } catch {
            Self.logger.error("Usage request failed: \(String(describing: error), privacy: .public)")
            throw UsageProviderError.network(error)
        }
        guard let http = response as? HTTPURLResponse else {
            Self.logger.error("Usage response was not HTTP")
            throw UsageProviderError.invalidResponse
        }
        do {
            let snapshot = try Self.parseResponse(statusCode: http.statusCode, data: data, fetchedAt: Date())
            // Logged (without values) so the success/429 cadence can be read
            // from the log alongside the failures.
            Self.logger.notice("Usage fetch succeeded: status=\(http.statusCode, privacy: .public)")
            return snapshot
        } catch UsageProviderError.unexpectedStatus(let status) {
            Self.logHTTPFailure(status: status, http: http, data: data)
            throw UsageProviderError.unexpectedStatus(status)
        } catch {
            Self.logShapeFailure(error, data: data)
            throw error
        }
    }

    /// Pure so status/body handling is unit-testable without networking.
    static func parseResponse(statusCode: Int, data: Data, fetchedAt: Date) throws -> UsageSnapshot {
        guard (200..<300).contains(statusCode) else {
            throw UsageProviderError.unexpectedStatus(statusCode)
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw UsageProviderError.invalidResponse
        }
        // This endpoint is undocumented (see docs/REQUIREMENTS.md). If its
        // shape changes and a required field goes missing, that must surface
        // as a fetch failure, not as a silent "0%"/"–" display.
        guard let session = Self.parseMeter(json["five_hour"] as? [String: Any]),
              let weekly = Self.parseMeter(json["seven_day"] as? [String: Any]) else {
            throw UsageProviderError.invalidResponse
        }

        return UsageSnapshot(session: session, weekly: weekly, fetchedAt: fetchedAt)
    }

    /// Logs only enumerable diagnostics, never free-form server text (body,
    /// error message, arbitrary headers): this endpoint is undocumented, so a
    /// proxy/auth/server failure could put anything in them, and these logs
    /// are public and persisted.
    private static func logHTTPFailure(status: Int, http: HTTPURLResponse, data: Data) {
        let retryAfter = Self.sanitizedRetryAfter(http.value(forHTTPHeaderField: "Retry-After"))
        let summary = Self.errorSummary(of: data)
        logger.error("Usage fetch failed: status=\(status, privacy: .public) retry-after=\(retryAfter, privacy: .public) \(summary, privacy: .public)")
    }

    /// Delay-seconds form only; anything else (HTTP-date, garbage) is not echoed.
    static func sanitizedRetryAfter(_ value: String?) -> String {
        guard let value else { return "-" }
        return value.range(of: #"^[0-9]{1,9}$"#, options: .regularExpression) != nil ? value : "<non-numeric>"
    }

    /// e.g. `type=rate_limit_error bytes=94`. The type is echoed only when it
    /// looks like an Anthropic error-type identifier; `message` is never logged.
    static func errorSummary(of data: Data) -> String {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = json["error"] as? [String: Any] else {
            return "body=<\(data.count) bytes, not an API error object>"
        }
        let type: String
        if let raw = error["type"] as? String {
            type = raw.range(of: #"^[a-z_]{1,64}$"#, options: .regularExpression) != nil ? raw : "<unrecognized>"
        } else {
            type = "-"
        }
        return "type=\(type) bytes=\(data.count)"
    }

    /// 2xx with an unexpected shape: the body is (part of) a real usage
    /// payload, so only its key structure is logged, never the values.
    private static func logShapeFailure(_ error: Error, data: Data) {
        let keys = Self.keyStructure(of: data)
        logger.error("Usage fetch failed: \(String(describing: error), privacy: .public) keys=\(keys, privacy: .public)")
    }

    /// e.g. `five_hour{resets_at,utilization} seven_day{...}`, or
    /// `<not a JSON object>`. Values are dropped.
    static func keyStructure(of data: Data) -> String {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return "<not a JSON object>"
        }
        return json.keys.sorted().map { key in
            guard let nested = json[key] as? [String: Any] else { return key }
            return "\(key){\(nested.keys.sorted().joined(separator: ","))}"
        }.joined(separator: " ")
    }

    private func readAccessToken() throws -> String {
        // No SecItemCopyMatching fallback on failure: it can block
        // indefinitely on the Keychain prompt, and a fetch that never returns
        // stalls UsageViewModel's loop (it awaits the previous Task). A
        // fallback would also rarely help — a locked keychain or an ACL
        // without `security` makes the CLI prompt (not fail), and a missing
        // item is missing for both.
        let result = Self.runProcess(
            executableURL: URL(fileURLWithPath: "/usr/bin/security"),
            arguments: ["find-generic-password", "-s", keychainService, "-w"],
            timeout: securityCLITimeout
        )
        guard case .success(let data) = result else {
            Self.logger.error("Keychain read via security failed: \(String(describing: result), privacy: .public)")
            throw UsageProviderError.credentialUnavailable
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            Self.logger.error("Keychain item is not the expected JSON")
            throw UsageProviderError.credentialUnavailable
        }

        if let token = json["accessToken"] as? String {
            return token
        }
        if let oauth = json["claudeAiOauth"] as? [String: Any],
           let token = oauth["accessToken"] as? String {
            return token
        }
        Self.logger.error("Keychain item has no accessToken")
        throw UsageProviderError.credentialUnavailable
    }

    enum ProcessResult: Equatable {
        case success(Data)
        case failed
        case timedOut
    }

    /// Runs a short-lived command and returns its stdout. The keychain is
    /// read through `/usr/bin/security` instead of calling
    /// SecItemCopyMatching directly: Claude Code appears to rewrite the item
    /// with `security add-generic-password -U` on every token refresh, which
    /// resets its ACL to trust only `/usr/bin/security`, so an "Always Allow"
    /// granted to this app is lost a few times a day and the Keychain password
    /// prompt reappears. Going through the same binary avoids the prompt. Do
    /// not replace this with SecItemCopyMatching.
    ///
    /// Blocks the calling thread, but never longer than `timeout` (plus a
    /// short grace period for termination), since Task cancellation cannot
    /// interrupt it.
    static func runProcess(executableURL: URL, arguments: [String], timeout: TimeInterval) -> ProcessResult {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice

        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }
        do {
            try process.run()
        } catch {
            return .failed
        }

        // Drain stdout concurrently so a large output can't fill the pipe
        // buffer and keep the child from exiting.
        var output = Data()
        let drained = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            output = stdout.fileHandleForReading.readDataToEndOfFile()
            drained.signal()
        }

        guard exited.wait(timeout: .now() + timeout) == .success else {
            process.terminate()
            if exited.wait(timeout: .now() + 1) == .timedOut {
                kill(process.processIdentifier, SIGKILL)
                _ = exited.wait(timeout: .now() + 1)
            }
            return .timedOut
        }
        // The child has exited, so its end of the pipe is closed and the read
        // finishes; the timeout only guards against a grandchild holding it.
        guard drained.wait(timeout: .now() + 1) == .success else { return .timedOut }
        guard process.terminationStatus == 0, !output.isEmpty else { return .failed }
        return .success(output)
    }

    static func parseMeter(_ dict: [String: Any]?) -> MeterUsage? {
        guard let dict,
              let utilization = dict["utilization"] as? Double,
              let resetsAtString = dict["resets_at"] as? String,
              let resetsAt = Self.parseDate(resetsAtString) else {
            return nil
        }
        guard utilization.isFinite, (0.0...100.0).contains(utilization) else { return nil }
        let percent = Int(utilization.rounded())
        return MeterUsage(percentUsed: percent, resetsAt: resetsAt)
    }

    static func parseDate(_ string: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: string) { return date }

        let withoutFraction = ISO8601DateFormatter()
        withoutFraction.formatOptions = [.withInternetDateTime]
        return withoutFraction.date(from: string)
    }
}
