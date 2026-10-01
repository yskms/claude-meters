import Foundation

/// A dotted numeric version such as `0.1.8`, as found in the app's
/// `CFBundleShortVersionString` and in the `vX.Y.Z` GitHub release tags.
/// Anything with a non-numeric component (e.g. `0.2.0-beta`) is rejected
/// rather than guessed at, so an unexpected tag format shows up as a failed
/// update check instead of a wrong "up to date"/"update available" answer.
struct AppVersion: Comparable, CustomStringConvertible {
    let components: [Int]

    init?(_ string: String) {
        var text = Substring(string.trimmingCharacters(in: .whitespacesAndNewlines))
        if text.hasPrefix("v") || text.hasPrefix("V") {
            text = text.dropFirst()
        }
        var numbers: [Int] = []
        for part in text.split(separator: ".", omittingEmptySubsequences: false) {
            // `Int("+1")`/`Int("-1")` would parse, so check the digits ourselves.
            guard !part.isEmpty, part.allSatisfy({ $0.isASCII && $0.isNumber }),
                  let number = Int(part) else {
                return nil
            }
            numbers.append(number)
        }
        components = numbers
    }

    var description: String {
        components.map(String.init).joined(separator: ".")
    }

    /// Missing trailing components count as 0, so `0.1` equals `0.1.0`.
    private func component(at index: Int) -> Int {
        index < components.count ? components[index] : 0
    }

    static func == (lhs: AppVersion, rhs: AppVersion) -> Bool {
        !(lhs < rhs) && !(rhs < lhs)
    }

    static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        for index in 0..<max(lhs.components.count, rhs.components.count) {
            let left = lhs.component(at: index)
            let right = rhs.component(at: index)
            if left != right { return left < right }
        }
        return false
    }
}
