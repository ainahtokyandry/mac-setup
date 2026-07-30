// Starting up, for both kinds of build: MacBar with every section that was
// found, and a section repository building an app of its own with one.
//
// Keeping this here rather than in each main.swift means a standalone section
// app is not a second implementation of anything — it is this app with a list of
// one.

import AppKit
import Foundation

enum Host {
    /// The whole of a main.swift: `Host.run(sections: [MySection()])`.
    static func run(sections: [BarSection]) -> Never {
        Defaults.register(sections: sections)

        if CommandLine.arguments.contains("--print") {
            exit(printReadings(sections))
        }

        let app = NSApplication.shared
        let controller = MenuBarController(sections: sections)
        app.delegate = controller
        app.setActivationPolicy(.accessory)   // menu bar only, no Dock icon
        app.run()
        exit(0)
    }

    /// `--print` writes the same readings to stdout and exits, which is handy
    /// from a shell and keeps the formatting path testable.
    ///
    /// Sections are asked in parallel and printed in order, so one section
    /// waiting on the network does not hold up the rest.
    private static func printReadings(_ sections: [BarSection]) -> Int32 {
        let group = DispatchGroup()
        let lock = NSLock()
        var answers: [Int: (lines: [String], ok: Bool)] = [:]

        for (i, section) in sections.enumerated() {
            guard section.isAvailable else {
                answers[i] = (["not available on this Mac"], false)
                continue
            }
            group.enter()
            let answered = OneShot()
            section.snapshot { lines, ok in
                // A section that called back twice would crash on leave().
                guard answered.claim() else { return }
                lock.lock()
                answers[i] = (lines, ok)
                lock.unlock()
                group.leave()
            }
        }

        // A section that never answers should not hang a shell.
        if group.wait(timeout: .now() + 30) == .timedOut {
            print("timed out waiting for a section to report", to: &standardError)
        }

        var status: Int32 = 0
        for (i, section) in sections.enumerated() {
            if i > 0 { print("") }
            print(section.name)
            let answer = answers[i] ?? (["no reading"], false)
            if !answer.ok { status = 1 }
            for line in answer.lines { print("  " + line) }
        }
        return status
    }
}

/// Lets the first completion through and no more, from any thread.
private final class OneShot {
    private let lock = NSLock()
    private var used = false

    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if used { return false }
        used = true
        return true
    }
}

/// print(to:) needs a TextOutputStream; stderr does not come with one.
struct StandardError: TextOutputStream {
    func write(_ string: String) {
        FileHandle.standardError.write(Data(string.utf8))
    }
}

var standardError = StandardError()
