import Foundation
import Darwin

/// Classification never queries handlers or launches an application.
public enum PayloadClassification: Equatable, Sendable {
    case webURL(URL)
    case externalCandidate(URL)
    case plainText(String)
    /// Show as text with explicit Copy/Open as text; never dispatch this URI.
    case blockedText(String)
    case unsupported
}

public enum PayloadClassifier {
    public static let maximumUTF8Bytes = 64 * 1024

    public static func classify(_ original: String?) -> PayloadClassification {
        guard let original, original.utf8.count <= maximumUTF8Bytes else { return .unsupported }
        let candidate = original.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.isEmpty,
              let colon = candidate.firstIndex(of: ":") else { return .plainText(original) }
        let scheme = String(candidate[..<colon])
        guard scheme.range(of: "^[A-Za-z][A-Za-z0-9+.-]*$", options: .regularExpression) != nil else {
            return .plainText(original)
        }
        let lower = scheme.lowercased()
        if ["file", "javascript", "data"].contains(lower) { return .blockedText(original) }
        if lower == "wifi" { return .plainText(original) }
        guard !candidate.unicodeScalars.contains(where: {
            CharacterSet.whitespacesAndNewlines.contains($0) || CharacterSet.controlCharacters.contains($0)
        }) else { return .plainText(original) }
        // Disable Foundation's implicit repair of malformed escapes and characters.
        guard let url = URL(string: candidate, encodingInvalidCharacters: false),
              url.scheme?.lowercased() == lower else { return .plainText(original) }
        if lower == "http" || lower == "https" {
            guard candidate[candidate.index(after: colon)...].hasPrefix("//"),
                  let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                  let host = components.host, validHost(host),
                  components.port.map({ (1...65535).contains($0) }) ?? true else {
                return .plainText(original)
            }
            return .webURL(url)
        }
        return .externalCandidate(url)
    }

    private static func validHost(_ host: String) -> Bool {
        guard !host.isEmpty else { return false }
        if host.hasPrefix("["), host.hasSuffix("]") {
            var address = in6_addr()
            return String(host.dropFirst().dropLast()).withCString { inet_pton(AF_INET6, $0, &address) == 1 }
        }
        let value = host.hasSuffix(".") ? String(host.dropLast()) : host
        let labels = value.split(separator: ".", omittingEmptySubsequences: false)
        guard value.utf8.count <= 253, !labels.isEmpty else { return false }
        if labels.count == 4 && labels.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }) {
            return labels.allSatisfy { Int($0).map { (0...255).contains($0) } ?? false }
        }
        return labels.allSatisfy { label in
            !label.isEmpty && label.utf8.count <= 63 && label.first != "-" && label.last != "-" &&
                label.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" }
        }
    }
}
