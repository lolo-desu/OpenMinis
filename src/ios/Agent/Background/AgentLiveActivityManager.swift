import Foundation
import UIKit

@MainActor
final class AgentLiveActivityManager {
    static let shared = AgentLiveActivityManager()
    private init() {}

    var taskStartTime: Date? { nil }
    static var isLiveActivitySupported: Bool { false }
    static let userAudioToggleSource = "liveActivityToggle"

    struct AudioState {
        var isPlaying: Bool
        var isLoaded: Bool
        var title: String
    }

    static func currentAudioState() -> AudioState {
        let v = VoiceOutputState.shared
        return AudioState(isPlaying: !v.speechPaused, isLoaded: v.isReadingAloud, title: "")
    }

    static func isAudioActive() -> Bool {
        VoiceOutputState.shared.isReadingAloud
    }

    func cleanupStaleActivities(source: String = "?") {}
    func startActivity(sessions: [LiveSessionSnapshot]) {}
    func updateActivity(sessions: [LiveSessionSnapshot]) {}
    func endActivity() {}
    func markSessionCompleted(sessionId: String, lastMessage: String) {}
    func finishActivity(lastMessages: [String: String] = [:]) async {}
    func handleSessionDeleted(_ sessionId: String) {}
    func dismissFinishedActivityOnForeground() {}
    func audioStateChanged(source: String) {}

    static func currentSoulName() -> String {
        let name = SoulStore.cachedMetadata.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "Minis" : name
    }

    static func latestToolIcon() -> String {
        guard let toolName = SessionActivityTracker.shared.latestToolName() else { return "" }
        return sfSymbol(forTool: toolName)
    }

    static func sfSymbol(forTool toolName: String) -> String {
        switch toolName {
        case "browser", "browser_use":          return "globe"
        case "shell", "shell_execute":          return "terminal"
        case "file_read":                       return "doc.text"
        case "file_write":                      return "doc.text.fill"
        case "file_edit":                       return "pencil.line"
        case "read_image":                      return "photo"
        case "memory":                          return "brain.head.profile"
        case "text":                            return "bubble.left"
        case "thinking":                        return "lightbulb.max"
        case "code_interpret":                  return "chevron.left.forwardslash.chevron.right"
        default:                                return "ellipsis.circle"
        }
    }

    static func displayName(forTool toolName: String) -> String {
        switch toolName {
        case "browser", "browser_use":          return "Browser"
        case "shell", "shell_execute":          return "Shell"
        case "file_read":                       return "Read File"
        case "file_write":                      return "Write File"
        case "file_edit":                       return "Edit File"
        case "read_image":                      return "Read Image"
        case "memory":                          return "Memory"
        case "text":                            return "Responding"
        case "thinking":                        return "Thinking"
        case "code_interpret":                  return "Code"
        default:                                return "Working"
        }
    }
}
