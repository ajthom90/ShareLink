import Foundation

public enum Diagnostics {
    /// Config summary with usernames and hosts redacted. Share names and paths are omitted.
    /// Passwords are never accepted by this function.
    public static func report(
        servers: [ServerConfig],
        statuses: [String: ServerStatus],
        issues: [String],
        appVersion: String,
        logTail: [String]
    ) -> String {
        var lines: [String] = ["ShareLink \(appVersion)", "", "Servers"]
        if servers.isEmpty {
            lines.append("- none")
        } else {
            for server in servers {
                lines.append(line(for: server, status: statuses[server.id] ?? .needsSignIn))
            }
        }
        lines.append("")
        lines.append("Issues")
        if issues.isEmpty {
            lines.append("- none")
        } else {
            for issue in issues {
                lines.append("- \(issue)")
            }
        }
        lines.append("")
        lines.append("Log")
        if logTail.isEmpty {
            lines.append("- none")
        } else {
            lines.append(contentsOf: logTail)
        }
        return lines.joined(separator: "\n")
    }

    private static func line(for server: ServerConfig, status: ServerStatus) -> String {
        let source: String
        switch server.source {
        case .managed(let slot): source = "managed slot \(slot)"
        case .user: source = "user"
        }
        let statusText: String
        switch status {
        case .signedIn: statusText = "signed in"
        case .needsSignIn: statusText = "needs sign-in"
        case .error: statusText = "error"
        }
        let encryption = server.requireEncryption ? "required" : "optional"
        return "- \(server.displayName) (\(source)): \(statusText), encryption \(encryption), user \(redactUsername(server.username)), host \(redactHost(server.host))"
    }

    private static func redactUsername(_ username: String) -> String {
        guard let first = username.first else { return "***" }
        return "\(first)***"
    }

    private static func redactHost(_ host: String) -> String {
        let trimmed = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first else { return "***" }
        let labels = trimmed.split(separator: ".").map(String.init)
        if labels.count == 4, labels.allSatisfy(isIPv4Octet) {
            return "x.x.x.\(labels[3])"
        }
        guard labels.count >= 2, let suffix = labels.last, !suffix.isEmpty else {
            return "\(first)***"
        }
        return "\(first)***.\(suffix)"
    }

    private static func isIPv4Octet(_ text: String) -> Bool {
        guard let value = Int(text), (0...255).contains(value) else { return false }
        return String(value) == text
    }
}
