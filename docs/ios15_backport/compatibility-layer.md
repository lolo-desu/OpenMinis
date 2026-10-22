# Compatibility layer

`src/ios/Shared/iOS15Compatibility.swift` is the single place where iOS 16 API is
reshaped into something iOS 15 accepts. It is compiled into the main app target.

**Design rule:** every shim keeps the *name and signature* of the iOS 16 API. That
way upstream call sites compile unmodified, so a `git merge` of upstream work does
not conflict. If a shim cannot achieve that (see the exceptions), the call site is
edited and the reason is recorded in `known-traps.md`.

## How a shim decides what to do

Two patterns are used, and picking the wrong one is a common source of bugs:

**A. `typealias` to a working equivalent** — when an iOS 16 *type* has an iOS 15
equivalent that is API-compatible enough:

```swift
typealias ShareLink = CompatShareLink      // manual share sheet
```

**B. Same name, availability-branched implementation** — when behaviour differs:

```swift
struct CompatNavigationStack<Content: View>: View {
    var body: some View {
        if #available(iOS 16.0, *) { NavigationStack { content } }
        else { NavigationView { content }.navigationViewStyle(.stack) }
    }
}
```

`#available` is *fine* here because the shim is a real SwiftUI view. It is **not**
fine for APIs that pull in iOS 16 framework symbols regardless of the branch —
see `known-traps.md` #3, where the call site had to go.

## What is provided

Grouped by area. Note that `NavigationStack` and `LabeledContent` are shims where
the iOS 15 fallback is *behaviourally close but not identical* — do not assume pixel
parity in UI work.

### Navigation and layout

| shim | iOS 15 fallback | parity notes |
|---|---|---|
| `NavigationStack` | `NavigationView` + `.stack` style | no `navigationDestination`-style type erasure; deep-link paths behave differently |
| `NavigationSplitView` | `NavigationView` + `.columns` style | column visibility is approximated |
| `LabeledContent` | `HStack` with label + value | alignment/width behaviour differs |
| `Grid` | `LazyVGrid` approximation | no row-spanning |
| `UnevenRoundedRectangle` | `RoundedRectangle` (uniform radius) | corners are not individually controlled |
| `onGeometryChange` | `GeometryReader` + `PreferenceKey` | fires on a different cadence |

### Presentation

| shim | iOS 15 fallback |
|---|---|
| `sheet` + `presentationDetents` | `UISheetPresentationController` via a hosting controller — **half sheets work** |
| `presentationBackground` | ignored |
| `presentationCornerRadius` | ignored |

### Media and sharing

| shim | iOS 15 fallback |
|---|---|
| `PhotosPicker` | `.compatPhotosPicker(...)` + `CompatPhotosPickerItem` (PHPickerViewController wrapper) |
| `ShareLink` | `UIActivityViewController` |
| `draggable` / `dropDestination` | **unconditional no-op** (see `known-traps.md` #3) |

### Async / task utilities

| shim | iOS 15 fallback |
|---|---|
| `Task.sleep(for:)` | `Task.sleep(nanoseconds:)` |
| Clock-based APIs | `Task.sleep` equivalents |

### Toolbar / scroll modifiers

`toolbarBackground`, `scrollIndicators`, `scrollContentBackground` and friends map
to their pre-16 UIKit equivalents or are ignored. Ignoring is deliberate: these are
cosmetic, and emulating them adds risk for no functional gain.

## Not shimmed — compiled out instead

These cannot be emulated, so the code that uses them is a stub:

| subsystem | file | shape |
|---|---|---|
| Live Activities / Dynamic Island | `AgentLiveActivityManager.swift` | no-op methods, `isLiveActivitySupported = false` |
| App Intents | `Agent/Intents/*.swift` | `import Foundation` stubs; `SendPromptIntent.swift` keeps the non-Intent types others depend on |
| WeatherKit | `WeatherOffloadBridge.swift` | returns "WeatherKit is not available on iOS 15." |

When stubbing a subsystem, **keep the symbols other files reference**. A stub that
deletes a type used elsewhere trades one compile error for twenty.

## Adding a shim

1. Check whether an equivalent exists on iOS 15 (first choice: `typealias`, then a
   wrapper view).
2. Match upstream's name and signature exactly.
3. Put it in `iOS15Compatibility.swift` under the right `MARK:` section.
4. If it must be `#available`-branched, confirm the iOS 16 branch does not leave a
   framework symbol in the binary — then run `scripts/verify_ios15_ipa.py`.
5. If you could not shim it, edit the call site **and** add an entry to
   `known-traps.md`.

## File registration

Files added to this branch must be registered in `project.pbxproj` (three places:
`PBXBuildFile`, `PBXFileReference`, and the group's `children`), plus the target's
`Sources` phase. A file present on disk but not in the project compiles *nowhere*,
and the resulting error ("cannot find X in scope") looks like a code bug. This bit
the first build of the port.
