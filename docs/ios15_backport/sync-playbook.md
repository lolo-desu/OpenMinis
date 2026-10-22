# Syncing with upstream `main`

The goal is to be able to pull upstream releases into this branch **routinely**, not
as a one-off heroic merge. That works only if the port stays a thin layer — see the
ground rules in `README.md`.

## Why it can be routine

This branch forked cleanly from upstream `b4c0661` (v1.14) with **no history
rewrite**, so `git merge upstream/main` is a genuine three-way merge with a real
merge base. The diff is ~63 files: one shim file, a handful of edited call sites,
two stubbed subsystems, a packaging block, and the workflow.

Two things make maintenance cheap, and both should be preserved:

1. **Shims mirror upstream names**, so upstream call sites need no edits.
2. **No changes to `Localizable.xcstrings`**, so localization churn never conflicts.

## One-time setup

```bash
cd OpenMinis
git remote add upstream https://github.com/OpenMinis/OpenMinis.git
git fetch upstream

# Are we shallow? (GitHub forks often are; a shallow clone cannot find a merge base)
git rev-parse --is-shallow-repository
git fetch --unshallow upstream      # only if the above prints true
```

A shallow clone is a real trap: `git merge-base` returns nothing and
`git diff upstream/main...HEAD` silently yields an empty diff, which reads as "no
changes" rather than as an error.

## The routine loop

```bash
git checkout ios15-support
git fetch upstream

# What is upstream bringing?
git log --oneline HEAD..upstream/main
git diff --stat HEAD...upstream/main | tail -20
```

Then merge:

```bash
git merge upstream/main
```

**Conflicts you should expect, and how to resolve them:**

| path | conflict cause | resolution |
|---|---|---|
| `src/ios/Minis.xcodeproj/project.pbxproj` | `IPHONEOS_DEPLOYMENT_TARGET`, `MARKETING_VERSION`, `OTHER_SWIFT_FLAGS`, file registrations, `-weak_framework` | keep 15.0 / widget 16.2 / FileProvider 16.0; **re-delete any `-weak_framework` line upstream re-adds**; keep `-DWIDGET_EXTENSION` on widget configs; keep shim file registrations |
| `src/ios/Shared/iOS15Compatibility.swift` | rarely — upstream does not know this file | keep ours; but re-check whether upstream now *needs* a new shim (see below) |
| `src/ios/Agent/Intents/*.swift` | upstream keeps adding intents | keep the stubs; carry over any non-Intent types other files import (see `SendPromptIntent.swift`) |
| `src/ios/Agent/Background/AgentLiveActivityManager.swift` | upstream evolves the real implementation | keep the stub, **but diff carefully**: new non-ActivityKit methods may be called from elsewhere and must be stubbed too |
| `src/ios/Shared/AgentActivityAttributes.swift`, `AudioTogglePlaybackIntent.swift` | upstream edits inside ActivityKit/AppIntents | keep the `#if WIDGET_EXTENSION` split, update the widget branch to upstream's version |
| localized strings | upstream adds `LocalizedStringResource` | convert to `LocalizedStringKey` — `known-traps.md` #4 |
| converted call sites (`.languageCode`, `NSRegularExpression`, etc.) | upstream may revert or re-add | keep ours if it is a compat conversion; otherwise take upstream |

After resolving, **never trust the merge result blindly** — upstream may have added
new iOS 16 API that compiles fine (Xcode 18 SDK) and only fails at runtime:

```bash
# 1. Does it still build?
#    (push to the branch; CI runs build-ios15.yml)

# 2. Did any new iOS 16 API slip in?
rg -n 'NavigationStack|NavigationSplitView|LabeledContent|presentationDetents|PhotosPicker|ShareLink|scrollPosition|onChange\(of:.*initial|ContentUnavailableView|Grid\(' src/ios --type swift -g '!Shared/iOS15Compatibility.swift'
# Every hit outside the shim must be something the shim already provides.

rg -n 'LocalizedStringResource|AppIntents|ActivityKit|WeatherKit|CoreTransferable|FoundationModels' src/ios --type swift
# Every hit must be inside #if WIDGET_EXTENSION, a stub, or an error message.

# 3. Verify the built binary
python3 scripts/verify_ios15_ipa.py Minis-iOS15-unsigned.ipa --sources src/ios

# 4. Merge back into the fork and bump the version so devices can tell builds apart
git push origin ios15-support
```

## Detecting new iOS 16 API that needs a shim

The compile step catches *type* errors, but not everything. The risky class is API
that exists in the SDK and **only fails at runtime on 15** — those compile cleanly
under Xcode 18 and crash on the device. Three detection layers:

1. **`verify_ios15_ipa.py`** — catches framework-level leakage (load commands,
   `@rpath`). This is the mechanical gate.
2. **Grep sweep** — the `rg` commands above. Catches SwiftUI API called through the
   shim's name but bypassing it, and new subsystems.
3. **Real device** — the only authority. When something crashes on device with
   `EXC_BREAKPOINT`, read `known-traps.md` #9 **before** forming a theory, and use the
   offset-comparison trick to confirm which build the report came from.

When you add a shim for something new, add a row to `compatibility-layer.md` and, if
it bit you, an entry to `known-traps.md`. The next agent's time is the thing this
documentation exists to protect.

## Automating it

`workflow_dispatch` builds can be triggered per merge. For unattended tracking, add
a scheduled workflow in the **fork** that merges upstream when it moves:

```yaml
name: Sync upstream
on:
  schedule: [{ cron: '0 3 * * *' }]
  workflow_dispatch:
jobs:
  sync:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with: { fetch-depth: 0 }
      - run: |
          git config user.name  "ios15-sync"
          git config user.email "sync@example.invalid"
          git remote add upstream https://github.com/OpenMinis/OpenMinis.git
          git fetch upstream
          git merge --no-edit upstream/main || {
            echo "::warning::merge conflict — resolve manually"; exit 1; }
          git push
```

Keep the merge commit-triggered `build-ios15.yml` as the gate: if the sync breaks
the build, you find out immediately instead of at the next release.

Caveat: an unattended merge cannot resolve conflicts, and `project.pbxproj`
*will* conflict on any upstream version bump. Expect the scheduled job to succeed on
most days and stop for manual attention on release days — that is still much cheaper
than syncing by hand.

## When the port gets too expensive

If upstream stops targeting iOS 16 and starts *depending* on 17/18/26 APIs (SwiftUI
`FoundationModels`, new observation macros, etc.), the shim approach degrades. The
signal: shims start needing to replace *behaviour*, not just spellings, or the
diff grows past a few hundred files. At that point a pinned "last good upstream
commit" plus targeted backports is more honest than pretending to track `main`.
