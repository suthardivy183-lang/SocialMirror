import Foundation

/// Detects "hedge" words and phrases that signal uncertainty or filler.
/// Matching is case-insensitive and respects whole-word boundaries — so
/// `"like"` matches in `"I like, ran"` but NOT in `"likeable"`.
nonisolated struct HedgeWordDetector: Sendable {
    static let hedgeWords: Set<String> = [
        "maybe", "perhaps", "sort of", "kind of", "i think",
        "i guess", "probably", "might", "possibly", "i suppose",
        "i mean", "basically", "literally", "actually", "you know",
        "like", "right", "honestly", "clearly",
    ]

    /// Pre-compiled alternation regex, ordered longest-first so multi-word
    /// phrases ("sort of") match before their constituent words ("of").
    private static let regex: NSRegularExpression = {
        let pattern = "\\b(" + hedgeWords
            .sorted(by: { $0.count > $1.count })
            .map { NSRegularExpression.escapedPattern(for: $0) }
            .joined(separator: "|") + ")\\b"
        // .caseInsensitive + UnicodeWordBoundaries ⇒ correct \b on letters.
        return try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .useUnicodeWordBoundaries])
    }()

    func count(in text: String) -> Int {
        let range = NSRange(text.startIndex ..< text.endIndex, in: text)
        return Self.regex.numberOfMatches(in: text, options: [], range: range)
    }

    func find(in text: String) -> [(word: String, range: Range<String.Index>)] {
        let range = NSRange(text.startIndex ..< text.endIndex, in: text)
        var results: [(String, Range<String.Index>)] = []
        Self.regex.enumerateMatches(in: text, options: [], range: range) { match, _, _ in
            guard let m = match,
                  let r = Range(m.range, in: text) else { return }
            results.append((String(text[r]), r))
        }
        return results
    }
}
