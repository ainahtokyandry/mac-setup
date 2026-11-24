// The contract between the host and a section: the protocol a section conforms
// to, the runs it contributes to the menu bar title, the colours and formatting
// it draws with, and the handful of NSMenuItem shapes it builds.
//
// Nothing here knows what any particular section measures. The sections live in
// their own repositories — see build.sh — and this file is the only thing they
// depend on, which is also why they can be compiled into a standalone app of
// their own without duplicating any of it.

import AppKit
import Foundation

// MARK: - Preferences

/// Every user-visible switch lives in UserDefaults under the bundle id, so
/// `defaults write local.macbar …` works from a script. Keys for the sections
/// themselves come from the sections; the host only owns `compact`.
enum Defaults {
    static let compact = "compactTitle"

    /// Sections default to visible, so a freshly installed app shows everything
    /// it can measure rather than an empty title.
    static func register(sections: [BarSection]) {
        var defaults: [String: Any] = [compact: true]
        for section in sections { defaults[section.showKey] = true }
        UserDefaults.standard.register(defaults: defaults)
    }

    static func bool(_ key: String) -> Bool { UserDefaults.standard.bool(forKey: key) }
    static func toggle(_ key: String) { UserDefaults.standard.set(!bool(key), forKey: key) }
    static func string(_ key: String) -> String? { UserDefaults.standard.string(forKey: key) }
}

// MARK: - Colours

/// The system accent colours are tuned for solid backgrounds. Both places this
/// app draws — the menu bar and a vibrant dropdown — are translucent, and
/// systemOrange in particular washes out to nothing over a light background. So
/// warning and critical are spelled out per appearance: deep enough to read on
/// light, bright enough to read on dark.
enum Palette {
    static let warning = NSColor(name: "macbarWarning") { appearance in
        isDark(appearance)
            ? NSColor(srgbRed: 1.00, green: 0.74, blue: 0.38, alpha: 1)
            : NSColor(srgbRed: 0.60, green: 0.32, blue: 0.00, alpha: 1)
    }

    static let critical = NSColor(name: "macbarCritical") { appearance in
        isDark(appearance)
            ? NSColor(srgbRed: 1.00, green: 0.50, blue: 0.48, alpha: 1)
            : NSColor(srgbRed: 0.69, green: 0.05, blue: 0.09, alpha: 1)
    }

    private static func isDark(_ appearance: NSAppearance) -> Bool {
        let match = appearance.bestMatch(from: [.aqua, .darkAqua, .vibrantLight, .vibrantDark])
        return match == .darkAqua || match == .vibrantDark
    }
}

// MARK: - Menu bar title

/// One run of text in the shared menu bar title.
///
/// The menu bar is translucent, so whatever wallpaper is behind it shows
/// through. Semi-transparent colours (secondaryLabelColor and friends) wash out
/// badly against a light or colourful background, so everything is drawn at full
/// opacity and the hierarchy comes from size and weight instead: small regular
/// labels, larger semibold numbers.
struct Segment {
    enum Role { case label, value }

    var text: String
    var role: Role
    var color: NSColor

    static func label(_ text: String, color: NSColor = .labelColor) -> Segment {
        Segment(text: text, role: .label, color: color)
    }

    static func value(_ text: String, color: NSColor = .labelColor) -> Segment {
        Segment(text: text, role: .value, color: color)
    }

    var font: NSFont {
        switch role {
        case .label: return NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        case .value: return NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        }
    }

    var attributed: NSAttributedString {
        NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color])
    }
}

// MARK: - Formatting

enum Fmt {
    static func iso(_ s: String?) -> Date? {
        guard let s = s else { return nil }
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = withFraction.date(from: s) { return d }

        // The API sends microseconds ("…:59.286288+00:00"); ISO8601DateFormatter
        // is only reliable with milliseconds, so drop the fractional part and
        // retry.
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        let stripped = s.replacingOccurrences(of: "\\.\\d+", with: "", options: .regularExpression)
        return plain.date(from: stripped)
    }

    /// "in 2d 3h", "in 14m", "any moment now", "3h 20m ago".
    static func relative(_ d: Date) -> String {
        let secs = Int(d.timeIntervalSinceNow)
        if secs <= 0 && secs > -60 { return "any moment now" }
        let a = abs(secs)
        let days = a / 86400, hours = (a % 86400) / 3600, mins = (a % 3600) / 60
        let span: String
        if days > 0 { span = "\(days)d \(hours)h" }
        else if hours > 0 { span = "\(hours)h \(mins)m" }
        else { span = "\(mins)m" }
        return secs > 0 ? "in \(span)" : "\(span) ago"
    }

    private static func formatter(_ pattern: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_GB")
        f.dateFormat = pattern
        return f
    }

    /// The time alone for today, the weekday and date for anything else.
    static func clock(_ d: Date) -> String {
        formatter(Calendar.current.isDateInToday(d) ? "HH:mm" : "EEE d MMM, HH:mm").string(from: d)
    }

    /// "Mon 08:00" — the menu bar form, where width is scarce.
    static func short(_ d: Date) -> String { formatter("EEE HH:mm").string(from: d) }

    /// "Mon 3 Aug, 08:00" — the dropdown form.
    static func long(_ d: Date) -> String { formatter("EEE d MMM, HH:mm").string(from: d) }

    static func gauge(_ percent: Int, width: Int = 14) -> String {
        let filled = max(0, min(width, Int((Double(percent) / 100 * Double(width)).rounded())))
        return String(repeating: "█", count: filled) + String(repeating: "░", count: width - filled)
    }

    static func pad(_ s: String, to n: Int) -> String {
        s.count >= n ? s : s + String(repeating: " ", count: n - s.count)
    }
}

// MARK: - Menu items

enum MenuKit {
    /// The name of a section, above its rows.
    static func header(_ text: String) -> NSMenuItem {
        let mi = NSMenuItem(title: text, action: nil, keyEquivalent: "")
        mi.attributedTitle = NSAttributedString(
            string: text,
            attributes: [
                .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
                .foregroundColor: NSColor.secondaryLabelColor,
            ])
        mi.isEnabled = false
        return mi
    }

    /// A reading, not a command.
    static func note(_ text: String, color: NSColor = .secondaryLabelColor) -> NSMenuItem {
        let mi = NSMenuItem(title: text, action: nil, keyEquivalent: "")
        mi.attributedTitle = NSAttributedString(
            string: text,
            attributes: [.font: NSFont.menuFont(ofSize: 12), .foregroundColor: color])
        mi.isEnabled = false
        return mi
    }

    /// Something wrong, said in colour. Left enabled — macOS draws a disabled
    /// item at reduced alpha, which is exactly what a warning cannot afford —
    /// and the menu turns off automatic enabling so nothing else re-dims it.
    static func alert(_ text: String, color: NSColor = Palette.warning) -> NSMenuItem {
        let mi = NSMenuItem(title: text, action: nil, keyEquivalent: "")
        mi.attributedTitle = NSAttributedString(
            string: text,
            attributes: [
                .font: NSFont.menuFont(ofSize: 12),
                .foregroundColor: color,
            ])
        mi.isEnabled = true
        return mi
    }

    static func action(_ title: String, _ selector: Selector, key: String = "",
                       target: AnyObject, object: Any? = nil) -> NSMenuItem {
        let mi = NSMenuItem(title: title, action: selector, keyEquivalent: key)
        mi.target = target
        mi.representedObject = object
        return mi
    }
}

// MARK: - Sections

/// One tool folded into the shared status item. A section owns its own polling
/// and its own block of the dropdown; it never touches the status item, and
/// asks for a redraw through the callback it is handed.
///
/// Implementations live in their own repositories. A section that conforms to
/// this and nothing else can be compiled either into MacBar alongside its
/// siblings, or into an app of its own.
protocol BarSection: AnyObject {
    /// Dropdown header, and the label of its switch under Sections.
    var name: String { get }
    /// UserDefaults key behind that switch. Off means off: nothing in the bar,
    /// nothing in the dropdown, and the section is not running. Owned by the
    /// section, so the host has no list of sections to keep in step.
    var showKey: String { get }
    /// False hides the section everywhere — nothing in the bar, nothing in the
    /// menu, no polling. For a section whose subject is not on this Mac.
    var isAvailable: Bool { get }

    /// Start polling: at launch for a section that is switched on, and again
    /// whenever it is switched back on after deactivate().
    func activate(onUpdate: @escaping () -> Void)

    /// The section was switched off, or is off at launch. Stop every clock and
    /// withdraw anything handed to the system. It may come without an
    /// activate() before it — at launch, to clear up after an earlier run — and
    /// activate() may follow it.
    func deactivate()

    /// The menu is opening, or the user asked for a refresh. `force` skips the
    /// polite floor between network polls.
    func refresh(force: Bool)

    func titleSegments(compact: Bool) -> [Segment]
    func menuRows() -> [NSMenuItem]

    /// The section's readings as plain lines, for `--print`. Asynchronous
    /// because a section may have to reach the network before it can answer;
    /// call the completion exactly once. `ok` false means the reading could not
    /// be taken, which becomes a non-zero exit status for the shell.
    func snapshot(_ completion: @escaping (_ lines: [String], _ ok: Bool) -> Void)
}

extension BarSection {
    var isAvailable: Bool { true }
    /// For a section written before deactivate() existed: it is hidden all the
    /// same, but its clock keeps running until MacBar quits.
    func deactivate() {}
    /// On this Mac, and switched on.
    var isEnabled: Bool { isAvailable && Defaults.bool(showKey) }
}
