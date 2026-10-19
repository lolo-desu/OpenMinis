import Foundation

/// [T-ios-live-activity-audio-toggle] Shared constants for the Live Activity
/// audio play/pause control's cross-process handoff. Compiled into BOTH the main
/// app and the AgentWidget extension so the widget can request a toggle and the
/// app can service it. See full design notes in the widget-extension build of
/// this file (WIDGET_EXTENSION conditional below).
enum AudioTogglePlaybackBridge {
    /// Darwin notification name the widget posts and the app observes.
    static let darwinNotificationName = "com.openminis.app.liveActivity.audioToggle"
}

#if WIDGET_EXTENSION
// The widget extension (stripped from the iOS 15 IPA) compiles the full
// LiveActivityIntent-backed button so the Dynamic Island audio control works
// there. The main iOS 15 target gets only the constants above.
import AppIntents

@available(iOS 17.0, *)
struct AudioTogglePlaybackIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Play or Pause Narration"
    static var description = IntentDescription("Toggles play/pause on Minis audio narration from the Live Activity.")
    static var openAppWhenRun = false

    func perform() async throws -> some IntentResult {
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        CFNotificationCenterPostNotification(
            center,
            CFNotificationName(AudioTogglePlaybackBridge.darwinNotificationName as CFString),
            nil, nil, true
        )
        return .result()
    }
}
#endif
