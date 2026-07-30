// The one status item: it joins what the sections report into a single title,
// and stacks their rows into a single dropdown.

import AppKit

final class MenuBarController: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let sections: [BarSection]
    private var statusItem: NSStatusItem!
    // One menu instance for the life of the app, rebuilt in place. Swapping in a
    // fresh NSMenu would be a problem when a refresh lands while the menu is on
    // screen.
    private let menu = NSMenu()
    private var menuIsOpen = false
    private var redrawQueued = false

    init(sections: [BarSection]) {
        self.sections = sections.filter { $0.isAvailable }
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = Self.icon()
            button.imagePosition = .imageLeading
        }
        menu.delegate = self
        // Enablement is set per item. Warning rows have to stay enabled to be
        // drawn at full strength, and AppKit would otherwise switch them off for
        // having no action.
        menu.autoenablesItems = false
        statusItem.menu = menu

        renderTitle()
        rebuildMenu()
        for section in sections {
            section.activate { [weak self] in self?.setNeedsRedraw() }
        }
    }

    /// Whatever bundle this host was built into — MacBar, or a single section
    /// built as an app of its own.
    private static var appName: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? ProcessInfo.processInfo.processName
    }

    /// The nicest gauge symbol available on the running macOS, or nothing. One
    /// icon stands for the whole app, so it does not shift about as sections are
    /// shown and hidden.
    private static func icon() -> NSImage? {
        for name in ["gauge.with.dots.needle.bottom.50percent", "gauge.medium", "gauge", "speedometer"] {
            if let image = NSImage(systemSymbolName: name, accessibilityDescription: appName) {
                return image
            }
        }
        return nil
    }

    // MARK: Redraw

    /// Sections poll on their own clocks and can land in the same turn of the
    /// run loop; coalescing means one redraw rather than three.
    private func setNeedsRedraw() {
        guard !redrawQueued else { return }
        redrawQueued = true
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.redrawQueued = false
            self.renderTitle()
            // Only while the menu is on screen — otherwise it is rebuilt on the
            // way open, which is cheaper and cannot disturb a highlighted row.
            if self.menuIsOpen { self.rebuildMenu() }
        }
    }

    private func renderTitle() {
        guard let button = statusItem.button else { return }

        let compact = Defaults.bool(Defaults.compact)
        let groups = sections
            .filter { $0.showsInMenuBar }
            .map { $0.titleSegments(compact: compact) }
            .filter { !$0.isEmpty }

        let title = NSMutableAttributedString()
        title.append(Segment.label(" ").attributed)
        for (i, group) in groups.enumerated() {
            if i > 0 { title.append(Segment.label(" · ").attributed) }
            for segment in group { title.append(segment.attributed) }
        }
        // Every section hidden: the icon alone would look like a hang, so say
        // the readings are in the menu.
        if groups.isEmpty { title.append(Segment.label("⋯").attributed) }

        button.attributedTitle = title
    }

    // MARK: Menu

    private func rebuildMenu() {
        menu.removeAllItems()

        for section in sections {
            menu.addItem(MenuKit.header(section.name))
            for row in section.menuRows() { menu.addItem(row) }
            menu.addItem(.separator())
        }

        // "Refresh All" reads oddly with one section, which is how a section
        // repository's own app is built.
        let refresh = sections.count > 1 ? "Refresh All" : "Refresh Now"
        menu.addItem(MenuKit.action(refresh, #selector(refreshAll), key: "r", target: self))
        menu.addItem(menuBarSubmenu())
        menu.addItem(.separator())
        menu.addItem(MenuKit.action("Quit \(Self.appName)", #selector(quit), key: "q", target: self))
    }

    /// What the single status item shows, and how tightly.
    private func menuBarSubmenu() -> NSMenuItem {
        let submenu = NSMenu()

        let compact = MenuKit.action("Compact Display", #selector(toggleDefault),
                                     target: self, object: Defaults.compact)
        compact.state = Defaults.bool(Defaults.compact) ? .on : .off
        submenu.addItem(compact)
        submenu.addItem(.separator())

        for section in sections {
            let item = MenuKit.action(section.name, #selector(toggleDefault),
                                      target: self, object: section.showKey)
            item.state = Defaults.bool(section.showKey) ? .on : .off
            submenu.addItem(item)
        }

        let parent = NSMenuItem(title: "Menu Bar", action: nil, keyEquivalent: "")
        parent.submenu = submenu
        return parent
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        rebuildMenu()
    }

    func menuWillOpen(_ menu: NSMenu) {
        menuIsOpen = true
        for section in sections { section.refresh(force: false) }
    }

    func menuDidClose(_ menu: NSMenu) {
        menuIsOpen = false
    }

    // MARK: Actions

    @objc private func refreshAll() {
        for section in sections { section.refresh(force: true) }
    }

    @objc private func toggleDefault(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String else { return }
        Defaults.toggle(key)
        sender.state = Defaults.bool(key) ? .on : .off
        renderTitle()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
