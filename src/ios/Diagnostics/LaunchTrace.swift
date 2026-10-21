//
//  LaunchTrace.swift
//  Minis
//
//  [T-ios15-launch-trace] Crash beacon for the iOS 15 backport.
//
//  The app dies ~1 s after the launch-screen handoff, with no crash report the
//  user can reach and no local Swift toolchain to attach a debugger from. This
//  file writes a durable, append-only breadcrumb trail to
//  Documents/launch-trace.log, one line immediately BEFORE each startup stage
//  runs, so whatever the last surviving line is names the stage that killed
//  the process.
//
//  Split of duties — deliberately, after the first attempt got this wrong:
//
//   * THIS file owns breadcrumbs only. Each line is one open/write/fsync/close
//     through a raw fd, so a SIGKILL'd or watchdog-killed process still leaves
//     every completed line on disk (no FILE* buffer to lose).
//
//   * SIGNAL HANDLING stays in CrashSignalHandler.m, which already existed and
//     already does it correctly: async-signal-safe string formatting, dladdr
//     offsets, O_EXCL so an NSException report is never overwritten by a
//     follow-up SIGABRT, and SIG_DFL + re-raise so ReportCrash still gets its
//     Mach exception. Re-implementing sigaction in Swift would have been both
//     redundant and a portability risk on the iOS 26 SDK.
//
//  Every line is written with Foundation only — no SwiftUI, no app singletons
//  — so the diagnostic cannot itself fail before the code it is measuring.
//

import Darwin
import Foundation

/// Breadcrumb trail persisted to Documents/launch-trace.log.
public enum LaunchTrace {

    public static let fileName = "launch-trace.log"

    /// Absolute path of the log, or nil if Documents is unavailable.
    public static var logURL: URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent(fileName)
    }

    private static let lock = NSLock()
    private static var startStamp = CFAbsoluteTimeGetCurrent()

    /// Milliseconds since `beginSession()` (or first use, if it never ran).
    private static func elapsed() -> Int {
        Int((CFAbsoluteTimeGetCurrent() - startStamp) * 1000)
    }

    /// Append one breadcrumb. Call it immediately BEFORE the stage runs, so
    /// the last surviving line is the stage that never finished.
    ///
    /// - Parameter stage: short stage label, e.g. "init:SoulStore.refreshCache".
    public static func mark(_ stage: String) {
        write("t=+\(elapsed())ms  \(stage)")
    }

    /// Append an arbitrary diagnostic line (not a stage marker).
    public static func note(_ text: String) {
        write("           · \(text)")
    }

    // MARK: - File IO

    private static func write(_ line: String) {
        lock.lock()
        defer { lock.unlock() }
        guard let url = logURL else { return }
        let payload = Array((line + "\n").utf8)

        // O_APPEND|O_CREAT|O_WRONLY: no buffering anywhere in the path, so the
        // bytes are visible to the kernel the moment write() returns.
        let fd = open(url.path, O_WRONLY | O_CREAT | O_APPEND, 0o644)
        guard fd >= 0 else { return }
        payload.withUnsafeBufferPointer { buf in
            guard let base = buf.baseAddress else { return }
            var off = 0
            while off < buf.count {
                let n = Darwin.write(fd, base.advanced(by: off), buf.count - off)
                if n <= 0 { break }
                off += n
            }
        }
        // fsync is what survives a SIGKILL — without it the tail we care about
        // can still be sitting in the page cache.
        _ = fsync(fd)
        close(fd)
    }

    /// Truncate the log so a crash beacon never grows without bound.
    public static func reset() {
        lock.lock()
        defer { lock.unlock() }
        guard let url = logURL else { return }
        try? FileManager.default.removeItem(at: url)
    }

    /// Start a fresh trail for this process and record the environment that
    /// earlier backport rounds never confirmed on-device: OS build (e.g.
    /// "19H349"), hardware model (e.g. "iPhone13,2"), and the bundle's own
    /// version + MinimumOSVersion.
    public static func beginSession() {
        startStamp = CFAbsoluteTimeGetCurrent()
        reset()
        let info = Bundle.main.infoDictionary ?? [:]
        let osv = ProcessInfo.processInfo.operatingSystemVersion
        write("=== Minis launch trace ===")
        write("os=\(osv.majorVersion).\(osv.minorVersion).\(osv.patchVersion)"
              + "  build=\(sysctlString("kern.osversion"))"
              + "  model=\(sysctlString("hw.machine"))")
        write("app=\(info["CFBundleIdentifier"] as? String ?? "?") "
              + "v\(info["CFBundleShortVersionString"] as? String ?? "?") "
              + "(\(info["CFBundleVersion"] as? String ?? "?")) "
              + "minOS=\(info["MinimumOSVersion"] as? String ?? "?")")
        write("exec=\(Bundle.main.executableURL?.path ?? "?")")
        write("pid=\(getpid())")
        // CrashSignalHandler.m has already been installed at this point
        // (MinisApp.init calls it right after beginSession); its own report
        // goes to Application Support/last_crash_stack.txt.
        note("signal handlers: CrashSignalHandler.m (Application Support/last_crash_stack.txt)")
    }

    private static func sysctlString(_ name: String) -> String {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return "?" }
        var buf = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buf, &size, nil, 0) == 0 else { return "?" }
        return String(cString: buf)
    }
}
