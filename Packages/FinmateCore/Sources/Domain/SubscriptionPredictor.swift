import Foundation

// MARK: - Subscription prediction & category inference (docs/13 §10, ported from Substimate)

/// What the Add-Subscription sheet prefills when it recognizes a service name.
public struct SubscriptionPrediction: Equatable, Sendable {
    public let vendorURL: String?
    public let icon: String?
    public let suggestedAmountMinor: Int64?
    public let category: String

    public init(vendorURL: String?, icon: String?, suggestedAmountMinor: Int64?, category: String) {
        self.vendorURL = vendorURL
        self.icon = icon
        self.suggestedAmountMinor = suggestedAmountMinor
        self.category = category
    }
}

/// Pure, unit-testable predictor. Exact name match first, then case-insensitive
/// substring match; names shorter than 2 chars never predict. Category inference
/// scans a keyword→category table (ported from Substimate `subscriptionPredictions.ts`).
public enum SubscriptionPredictor {
    struct Seed: Sendable { let url: String; let icon: String; let amountMinor: Int64? }

    static let seed: [String: Seed] = [
        "netflix":   Seed(url: "netflix.com",   icon: "play.tv",            amountMinor: 1299),
        "spotify":   Seed(url: "spotify.com",   icon: "music.note",         amountMinor: 1099),
        "chatgpt":   Seed(url: "openai.com",    icon: "bubble.left.and.bubble.right", amountMinor: 2000),
        "openai":    Seed(url: "openai.com",    icon: "bubble.left.and.bubble.right", amountMinor: 2000),
        "claude":    Seed(url: "claude.com",    icon: "sparkles",           amountMinor: 2000),
        "cursor":    Seed(url: "cursor.sh",     icon: "chevron.left.forwardslash.chevron.right", amountMinor: 2000),
        "github":    Seed(url: "github.com",    icon: "chevron.left.forwardslash.chevron.right", amountMinor: 1000),
        "midjourney":Seed(url: "midjourney.com",icon: "photo.artframe",     amountMinor: 1000),
        "notion":    Seed(url: "notion.so",     icon: "doc.text",           amountMinor: 1000),
        "figma":     Seed(url: "figma.com",     icon: "pencil.and.ruler",   amountMinor: 1500),
        "adobe":     Seed(url: "adobe.com",     icon: "paintbrush",         amountMinor: 5999),
    ]

    /// Ordered keyword → category. First substring hit wins; default "Other".
    static let keywordCategory: [(kw: String, category: String)] = [
        ("chatgpt", "AI Chat"), ("openai", "AI Chat"), ("claude", "AI Chat"), ("gemini", "AI Chat"),
        ("cursor", "Coding"), ("copilot", "Coding"), ("github", "Coding"),
        ("midjourney", "Diffusion"), ("runway", "Diffusion"), ("leonardo", "Diffusion"), ("stable diffusion", "Diffusion"),
        ("netflix", "Streaming"), ("disney", "Streaming"), ("hbo", "Streaming"), ("prime video", "Streaming"),
        ("spotify", "Music"), ("apple music", "Music"), ("tidal", "Music"),
        ("notion", "Productivity"), ("linear", "Productivity"), ("trello", "Productivity"),
        ("adobe", "Creative"), ("figma", "Creative"),
    ]

    public static func inferCategory(name: String) -> String {
        let n = name.lowercased()
        for entry in keywordCategory where n.contains(entry.kw) { return entry.category }
        return "Other"
    }

    public static func predict(name: String) -> SubscriptionPrediction? {
        let n = name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard n.count >= 2 else { return nil }

        if let exact = seed[n] {
            return SubscriptionPrediction(vendorURL: exact.url, icon: exact.icon,
                                          suggestedAmountMinor: exact.amountMinor,
                                          category: inferCategory(name: n))
        }
        for (key, s) in seed where n.contains(key) {
            return SubscriptionPrediction(vendorURL: s.url, icon: s.icon,
                                          suggestedAmountMinor: s.amountMinor,
                                          category: inferCategory(name: n))
        }
        // No dictionary hit, but still infer a category from keywords.
        let category = inferCategory(name: n)
        return SubscriptionPrediction(vendorURL: nil, icon: nil, suggestedAmountMinor: nil, category: category)
    }
}
