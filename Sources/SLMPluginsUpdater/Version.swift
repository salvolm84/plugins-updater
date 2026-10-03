import Foundation

/// Loose semantic version: takes the first `1.2.3` run found in a tag such as `v1.2.3` or `Release 1.2`.
struct Version: Comparable, Hashable, CustomStringConvertible {
    let components: [Int]

    init?(_ string: String) {
        guard let range = string.range(of: #"\d+(\.\d+)*"#, options: .regularExpression) else { return nil }
        components = string[range].split(separator: ".").compactMap { Int($0) }
        if components.isEmpty { return nil }
    }

    var description: String { components.map(String.init).joined(separator: ".") }

    static func < (lhs: Version, rhs: Version) -> Bool {
        let count = max(lhs.components.count, rhs.components.count)
        for i in 0..<count {
            let l = i < lhs.components.count ? lhs.components[i] : 0
            let r = i < rhs.components.count ? rhs.components[i] : 0
            if l != r { return l < r }
        }
        return false
    }

    static func == (lhs: Version, rhs: Version) -> Bool { !(lhs < rhs) && !(rhs < lhs) }

    func hash(into hasher: inout Hasher) {
        var trimmed = components
        while trimmed.last == 0 { trimmed.removeLast() }
        hasher.combine(trimmed)
    }
}
