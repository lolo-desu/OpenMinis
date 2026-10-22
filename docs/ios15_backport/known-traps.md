# Known traps

Every item here cost at least one failed build cycle. Read the symptom column
before you start debugging: several of these look like something else.

---

## 1. `containerURL(forSecurityApplicationGroupIdentifier:)` returns `nil`

**Symptom.** The app shows its launch screen, then dies ~1 second later. Crash
report:

```
Exception Type:  EXC_BREAKPOINT (SIGTRAP)
frame 0  AIChatViewModel.minisAppGroupRoot.getter
frame 1  SoulStore.fileURL → minisMemoryPersistentDir
frame 2  SoulStore.load()
frame 3  MinisApp.init()
```

**Cause.** The code was
`containerURL(forSecurityApplicationGroupIdentifier: ...)!`. This call returns
`nil` when the process's code signature does not enumerate the app group — which
is exactly what happens for an **unsigned / TrollStore / sideloaded** install, and
can also happen if entitlements are dropped by a resigning tool.

This is **not** an iOS 15 problem. It would crash on any iOS version with the same
signature situation. It only looked like an iOS 15 backport bug because that was
the context it was first observed in.

**Fix.** Go through `AIChatViewModel.appGroupContainer`, which resolves the group
and falls back to `Library/Application Support/MinisAppGroup` when it is missing.
Never reintroduce `!` here — `scripts/verify_ios15_ipa.py` fails the build's
verification step if you do.

**Lesson.** A forced unwrap of a *system query that can legitimately fail* is a
launch-time trap. The app group is optional in every signature mode except a
properly provisioned one.

---

## 2. `-weak_framework` makes iOS 16 types load eagerly

**Symptom.** Crash at launch with no useful stack, on a binary whose deployment
target looks correct. `dyld` may or may not complain.

**Cause.** The original project linked iOS 16 frameworks with
`OTHER_LDFLAGS = -Wl,-weak_framework,AppIntents ...`. Weak linking defers *symbol*
resolution, but Swift still emits eager metadata/ conformance accessors for any
type it can see at compile time. When those run on iOS 15 the framework is absent
and the process traps during startup, before `main`.

**Fix.** All `-weak_framework` entries are removed from `project.pbxproj`. The iOS
16+ subsystems are instead **compiled out** (stubs) or guarded by
`#if WIDGET_EXTENSION`. Do not re-add weak linking as a shortcut.

---

## 3. `.draggable` / `.dropDestination` drag `CoreTransferable` in

**Symptom.** After removing all weak frameworks, the binary still loads
`CoreTransferable` (iOS 16+).

**Cause.** `Transferable` is a protocol with runtime conformance records. A
`.draggable(x)` call site inside `#available(iOS 16.0, *)` still emits the generic
symbol, and the linker records the dylib.

**Fix.** `draggable`/`dropDestination` are **unconditional no-ops** in the shim,
and the two `.draggable(session.id)` call sites in `ContentView.swift` are
commented out. An `#available` guard is **not** sufficient for this class of API;
removing the call site is.

**Cost.** Session drag-to-reorder is gone on iOS 15. Acceptable; it is a
convenience, not a feature.

---

## 4. `LocalizedStringResource` produces >1000 errors at once

**Symptom.** Compile fails with ~1065 errors, mostly mentioning
`LocalizedStringResource`.

**Cause.** Upstream moved localization to `LocalizedStringResource`, which is
iOS 16+. A shim cannot substitute it cleanly: `Text(...)` / `LocalizedStringKey`
initializers differ by overload, and the type appears in stored properties.

**Fix.** Call sites were changed to `LocalizedStringKey` (notably
`SessionLockStore.labelKey`). This is the main sanctioned exception to "shim, don't
edit".

**When upstream adds more `LocalizedStringResource` usage**, expect the same
class of error and apply the same conversion.

---

## 5. `#if WIDGET_EXTENSION` must guard shared sources

**Symptom.** Widget target fails with *cannot find `AgentActivityAttributes` in
scope* (or similar), while the main app builds fine.

**Cause.** `AgentActivityAttributes.swift` and `AudioTogglePlaybackIntent.swift`
are compiled into **both** the app and the widget target. The main target needs the
iOS-15-safe subset; the widget target needs the real `ActivityKit` types.

**Fix.** Shared files use
`#if WIDGET_EXTENSION` … `#else` … `#endif`, and the widget build configuration
sets `OTHER_SWIFT_FLAGS = "-DWIDGET_EXTENSION"`. The main target's `#else` branch
must expose only what the app uses (`LiveSessionSnapshot` etc.).

**If you add a file to both targets**, decide up front which branch it belongs to.

---

## 6. Calling a `Void`-returning function inside a `ViewBuilder`

**Symptom.** `'buildExpression' is unavailable: this expression does not conform to
'View'`.

**Cause.** A statement was dropped between views inside a `ViewBuilder` closure.

**Fix.** Prefix with `let _ =`. **But** scattering `let _ =` through a large
`body` can also push the type-checker over its budget, yielding a misleading
`ambiguous use of 'init'` (see `ContentView.body`). Prefer the smallest enclosing
scope, or move the work into `.onAppear`.

---

## 7. Toolbar conditionals must live *inside* `ToolbarItem`

**Symptom.** `ToolbarContentBuilder` type errors.

**Cause.** `if #available(...)` placed between `ToolbarItem`s rather than inside
one.

**Fix.** Move the conditional inside the `ToolbarItem`'s `ViewBuilder`. Eight files
needed this.

---

## 8. iSH / filesystem: a directory can become un-creatable

**Symptom.** `mkdir: can't create directory 'docs/ios15-backport': No such file or
directory` while `docs/` clearly exists and sibling names work.

**Cause.** Not a code problem — the iSH Linux layer occasionally leaves a directory
inode in a state where new entries cannot be created. It is *sticky per path*:
other names in the same parent work fine.

**Workaround.** `git checkout -- <dir>` to restore tracked contents, then use a
different directory name (this port uses `docs/ios15_backport`, underscore). A fresh
name always worked in practice.

---

## 9. Reading a crash report: confirm it is from the build you think

**Symptom.** You "fix" something, get a fresh `.ips` with a recent filename, and
conclude the fix failed.

**Cause.** The filename timestamp is when iOS *captured* the report, which can be
minutes after the crash, and file-share copy operations re-stamp mtimes. Reports can
also correspond to a launch that happened before your build existed.

**How to know for certain.** Take the `imageOffset` from the crashing thread's
`matchesCrashFrame` entry and inspect that offset in **both** binaries:

```python
import struct
d = open("Payload/Minis.app/Minis", "rb").read()
w = struct.unpack_from("<I", d, 0x4fb740)[0]   # imageOffset from the report
print("BRK (trap)" if (w & 0xFFE0001F) == 0xD4200000 else "not a trap")
```

`BRK` encodes as `0xD4200000 | (imm16 << 5)`:

| instruction | word |
|---|---|
| `brk #1` — Swift `__builtin_trap`, what this port hit | `0xD4200020` |
| `brk #32` | `0xD4200400` |

If the offset holds a `BRK` in the old binary and a `bl` in the new one, **the
report is from the old build** regardless of its filename. This exact check
resolved a long false trail.

Do not scan `__TEXT` for traps: it is ~48 MB and contains **20,000+** `BRK`
instructions. Always start from `matchesCrashFrame`'s `imageOffset`.

**Also check `uptime`.** A crash report's `procLaunch` wall-clock can be stale
after a device reboot with an uncalibrated clock; `uptime` (ms) plus `captureTime`
gives the true boot time and therefore the true launch window.

---

## 10. App Group caveats on unsigned installs (beyond the crash)

Even with the `!` fixed, an unsigned install has **no** app group. Consequences to
remember when debugging:

- Files under `MinisAppGroup` land in the sandbox fallback and are **not** visible
  in the iOS Files app.
- Anything relying on the *extension* side of the group (FileProvider, share
  extension) will not see the app's data. Those extensions are excluded from the
  15.x bundle partly for this reason.
- `NSFileCoordinator` across the group will not work. Do not add cross-process
  sharing on this branch without a fallback.
