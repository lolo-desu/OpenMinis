# iOS 15 backport — maintainer guide

This branch (`ios15-support`) lowers Minis' minimum deployment target from
**iOS 16.0 to iOS 15.0** without forking the app's behaviour.

Upstream targets iOS 16 and freely uses SwiftUI/iOS 16 APIs. Rather than rewrite
call sites (hundreds of them), this port adds a **compatibility shim** and strips
the subsystems that cannot work on 15 at all. The result is a small, auditable
diff that stays mergeable with `main`.

> **If you are an agent picking this up: read `known-traps.md` first.** It is the
> distilled result of several failed build/fix cycles. Two of those cycles were
> wasted on wrong theories that a five-minute check in that document would have
> avoided.

## Documents

| file | what it answers |
|---|---|
| [`sync-playbook.md`](sync-playbook.md) | How to merge upstream `main` into this branch. **Start here when upstream moves.** |
| [`known-traps.md`](known-traps.md) | The non-obvious failure modes, each with a symptom → cause → fix. |
| [`compatibility-layer.md`](compatibility-layer.md) | What `iOS15Compatibility.swift` provides, and how to add to it. |
| [`build-and-verify.md`](build-and-verify.md) | CI workflow, the verification script, and how to read a crash report. |

## Ground rules

1. **Never retro-fit the app source to iOS 15 by hand.** If an upstream call site
   uses an iOS 16 API, add a shim in `iOS15Compatibility.swift` (same name, same
   signature) so the call site stays byte-identical to upstream. This keeps merges
   clean and keeps the diff small.
2. **Exception to rule 1:** when the API's *type* itself is iOS 16+ in a way a
   shim cannot hide (`LocalizedStringResource`, `Transferable`, `ActivityKit`
   types), change the call site and record it in `known-traps.md`.
3. **The deployment target lives in CI, not in the project file.** See
   `build-and-verify.md`. Do not "fix" `IPHONEOS_DEPLOYMENT_TARGET` in
   `project.pbxproj`.
4. **Verify the binary, not just the build.** A green build says nothing about
   whether an iOS 16 symbol survived. Run `scripts/verify_ios15_ipa.py`.

## Current scope

Forked from upstream `b4c0661` (v1.14). The diff against that point is
**63 files** — a shim, a handful of call-site edits, two stripped subsystems, and
the CI workflow. Everything else is untouched, which is what makes syncing cheap.

What is **deliberately not available** on iOS 15, and why:

| feature | reason |
|---|---|
| App Intents / Shortcuts actions | `AppIntents` is iOS 16+; the intent files are stubbed |
| Live Activities / Dynamic Island | `ActivityKit` is iOS 16.1+; manager is a no-op stub |
| WeatherKit | iOS 16+; bridge returns an explanatory error |
| Home-screen/widget extension | target stays 16.2; excluded from the 15.x bundle |
| Share extension | temporarily excluded from packaging (see `known-traps.md` #1) |
| FileProvider (Files app integration) | target stays 16.0; excluded from the 15.x bundle |
| Session drag-to-reorder | needs `Transferable`; `.draggable` call sites are commented out |

Everything else — chat, agents, terminal/iSH, providers, voice, memory, skills —
is expected to work. **"Expected" is doing real work in that sentence**: this port
has been validated at the binary level and against crash reports, not on a device
farm. Treat device reports as the source of truth.
