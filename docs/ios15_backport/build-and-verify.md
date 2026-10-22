# Building and verifying

## The workflow

`.github/workflows/build-ios15.yml` produces an unsigned `.ipa` on `macos-15`.

Triggers: push to `main` / `master` / `ios15-support`, or manual
`workflow_dispatch`. Artifacts: `Minis-iOS15-IPA` (the IPA) and `xcodebuild-log`
(uploaded even on failure — read it first when a build breaks).

Steps, in order: checkout with submodules → Go 1.25 → pin Xcode → `brew install lld`
→ restore caches for native deps → build **iSH, FFmpeg, LAME, rclone** → prepare
configs → `xcodebuild` → upload log → package IPA.

A full cold build is 30–60 min; with the native-dependency caches warm, 12–25 min.
The native dependency build is the slow, fragile part: `deps/build_ish.sh`,
`build_ffmpeg.sh` and `build_lame.sh` already target `IOS_DEPLOYMENT_TARGET="14.0"`;
only `deps/build_rclone_ios.sh` was hardcoded to 16.0 and was lowered to 15.0.

## Where the deployment target comes from

`project.pbxproj`, per target. The `xcodebuild` invocation does **not** override it:

```
                IPHONEOS_DEPLOYMENT_TARGET = 15.0;   # ← this is what ships
```

Current state:

| target | target | why |
|---|---|---|
| project + `Minis` + `MinisShare` | **15.0** | the point of the fork |
| `MinisFileProvider` | 16.0 | `NSFileProviderReplicatedExtension` is iOS 16+; excluded from the IPA |
| `AgentWidget` | 16.2 | `ActivityKit` widgets; excluded from the IPA |
| `MinisTests`, `MinisUITests` | 26.2 | test-only, not shipped — leave alone |

**Consequence for syncing:** upstream changes to `IPHONEOS_DEPLOYMENT_TARGET` and
`MARKETING_VERSION` in `project.pbxproj` will conflict on every merge. Resolve in
this fork's favour (15.0 / the fork's version string). This is the single most
conflict-prone file, which is why `sync-playbook.md` treats it specially.

## Packaging: what gets excluded

The package step strips iOS 16+ plug-ins from the bundle before zipping:

- `AgentWidgetExtension.appex`
- `MinisFileProvider.appex`
- `MinisShare.appex` — **temporarily** removed while diagnosing launch crashes,
  because it declares the same app group an unsigned install cannot be granted.
  Restore it once boot is confirmed stable on real devices.

An `.appex` whose `MinimumOSVersion` is 16.0 will make the whole app refuse to
install on a 15.x device, so this exclusion is load-bearing, not cosmetic.

## Verification: `scripts/verify_ios15_ipa.py`

Run after **every** build. A green `xcodebuild` proves nothing about iOS 15
compatibility — the binary can still reference iOS 16 symbols.

```bash
python3 scripts/verify_ios15_ipa.py Minis-iOS15-unsigned.ipa --sources src/ios
```

It checks:

| check | catches |
|---|---|
| app `MinimumOSVersion` ≤ 15.0 | a re-upgraded deployment target |
| every shipped plug-in installable on 15.x | a 16.0 extension slipping through packaging |
| no iOS 16+ framework in **load commands** | weak links / stray imports |
| no `@rpath`/`.framework` reference to iOS 16+ frameworks | a framework pulled in via a generic symbol |
| app group container never force-unwrapped | trap #1 in `known-traps.md` |
| native deps present | a cache miss shipping a broken iSH/FFmpeg |

Exit code is non-zero on failure, so it can gate CI directly.

> **Careful with string matching.** A bare `"ActivityKit"` or `"WeatherKit"` in the
> binary is usually this port's own user-facing copy ("Live Activities are not
> supported…"), not a dependency. Only load commands and `@rpath` references mean
> anything — the script checks those, not raw substrings.

## Reading a crash report

1. Find `Exception Type` and the crashing thread's frames.
2. Take `imageOffset` from the frame with `matchesCrashFrame: 1`.
3. Compare that offset across builds to confirm the report matches the build you
   think it does — see `known-traps.md` #9. **Do this before theorising.**
4. For Swift, `imageOffset` + a symbol table lookup gives the function; if the
   symbol is gone, the function was inlined into a caller (look one frame up).
5. `EXC_BREAKPOINT` (SIGTRAP) is a Swift runtime trap, not a memory bug: look for
   `!`, array out-of-bounds, or `fatalError`. `EXC_BAD_ACCESS` is something else
   entirely.

The app also keeps its own launch breadcrumb (`Documents/launch-trace.log`, one
line per startup stage, readable in-app at Settings → About → Diagnostics). When a
crash happens before any crash reporter can run, this log names the last stage that
was reached.
