import Foundation

/// Subsequence-based fuzzy matcher. Returns nil when not a match.
/// Score is in [0, 1] — higher is better. Bonuses for prefix, word boundary, and case match.
enum FuzzyMatcher {
    static func score(query: String, candidate: String) -> Double? {
        let q = query.lowercased()
        let c = candidate.lowercased()
        if q.isEmpty { return 0.0 }
        if c.isEmpty { return nil }

        var qi = q.startIndex
        var ci = c.startIndex
        var matches = 0
        var bonus = 0.0
        var prevBoundary = true
        var prevMatched = false

        while qi < q.endIndex && ci < c.endIndex {
            let qc = q[qi]
            let cc = c[ci]
            let isBoundary = prevBoundary || cc.isWordBoundaryFromPrevious
            if qc == cc {
                matches += 1
                if isBoundary { bonus += 0.15 }
                if prevMatched { bonus += 0.10 }
                if ci == c.startIndex { bonus += 0.20 }
                qi = q.index(after: qi)
                prevMatched = true
            } else {
                prevMatched = false
            }
            prevBoundary = !cc.isLetter && !cc.isNumber || cc.isUppercase
            ci = c.index(after: ci)
        }

        guard qi == q.endIndex else { return nil }

        let coverage = Double(matches) / Double(c.count)
        let lengthPenalty = max(0, Double(c.count - q.count)) / 200.0
        let score = min(1.0, 0.5 * coverage + bonus - lengthPenalty)
        return max(0.05, score) // floor for non-zero match
    }
}

private extension Character {
    var isWordBoundaryFromPrevious: Bool {
        return self == " " || self == "_" || self == "-" || self == "/" || self == "."
            || self.isUppercase
    }
}
