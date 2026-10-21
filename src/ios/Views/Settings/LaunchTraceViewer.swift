//
//  AboutView+LaunchTrace.swift
//  Minis
//
//  [T-ios15-launch-trace] In-app reader for Documents/launch-trace.log.
//
//  The whole point of the breadcrumb file is that it can be read WITHOUT a
//  computer. This screen renders it as selectable text with a copy button,
//  so after a crash the user relaunches, opens About, and can hand over the
//  exact last stage.
//

import SwiftUI

/// Row that opens the launch-trace viewer. Mounted in AboutView.
struct LaunchTraceRow: View {
    @State private var showingTrace = false

    /// One-line summary for the row subtitle: file size + mtime, or "none".
    private var summary: String {
        guard let url = LaunchTrace.logURL,
              let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? Int
        else { return "no trace file" }
        let fmt = DateFormatter()
        fmt.dateFormat = "MM-dd HH:mm:ss"
        let when = (attrs[.modificationDate] as? Date).map { fmt.string(from: $0) } ?? "?"
        let stackPending = !CrashSignalHandler.crashStackPath().isEmpty
            && FileManager.default.fileExists(atPath: CrashSignalHandler.crashStackPath())
        return "\(size) bytes · \(when)" + (stackPending ? " · ⚠️ crash stack saved" : "")
    }

    var body: some View {
        Button {
            showingTrace = true
        } label: {
            HStack {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Launch Trace")
                        Text(summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "ladybug.fill")
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundStyle(.tertiary)
            }
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showingTrace) {
            LaunchTraceViewer()
        }
    }
}

/// Full-screen log viewer with copy / share / reset.
struct LaunchTraceViewer: View {
    @Environment(\.dismiss) private var dismiss

    @State private var text = ""
    @State private var didCopy = false

    var body: some View {
        NavigationView {
            ScrollView {
                Text(text.isEmpty ? "(empty)" : text)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
            .navigationTitle("Launch Trace")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        UIPasteboard.general.string = text
                        didCopy = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { didCopy = false }
                    } label: {
                        Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                    }
                }
            }
        }
        .navigationViewStyle(.stack)
        .onAppear(perform: reload)
    }

    private func reload() {
        var out = ""
        if let url = LaunchTrace.logURL {
            out += (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        }
        // CrashSignalHandler's post-mortem stack (written by the Obj-C signal
        // handler; CrashReporter deletes it after folding it into a report,
        // so read it here before that can happen).
        let stackPath = CrashSignalHandler.crashStackPath()
        if !stackPath.isEmpty, let stack = try? String(contentsOfFile: stackPath, encoding: .utf8) {
            out += "\n=== last_crash_stack.txt ===\n" + stack
        }
        text = out
    }
}
