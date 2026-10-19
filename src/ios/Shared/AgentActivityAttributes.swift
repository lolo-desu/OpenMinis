import Foundation

struct LiveSessionSnapshot: Codable, Hashable {
    var sessionId: String
    var title: String
    /// SF Symbol name for the current tool (e.g. "globe", "terminal", "doc.text").
    var toolIcon: String
    /// Human-readable tool status (e.g. "navigate...", "running...", "get_text...").
    var toolStatus: String
    var loopIteration: Int
    var isCompleted: Bool = false
    var lastMessage: String = ""
}

#if WIDGET_EXTENSION
// The widget extension (stripped from the iOS 15 IPA) compiles the full
// ActivityKit-backed version of the shared activity attributes.
import ActivityKit

@available(iOS 16.2, *)
struct AgentActivityAttributes: ActivityAttributes {
    var startDate: Date

    public struct ContentState: Codable, Hashable {
        var activeSessionCount: Int
        var sessions: [LiveSessionSnapshot]
        var carouselIndex: Int
        var soulName: String
        var latestToolIcon: String = ""
        var minimalShowsTool: Bool = false
        var allCompleted: Bool = false
        var isAudioPlaying: Bool = false
        var isAudioLoaded: Bool = false
        var audioTitle: String = ""
        var finishedAt: Date? = nil
        var privacyMode: Bool = false
    }
}
#endif
