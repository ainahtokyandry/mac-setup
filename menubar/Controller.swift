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
    /// The sections activated and not since deactivated. Tracked here, not read
    /// back from the preference, so that each switch starts or stops a section
    /// exactly once.
    private var running = Set<ObjectIdentifier>()

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
        for section in sections { sync(section, launching: true) }
    }

    /// The sections switched on, in their usual order.
    private var enabled: [BarSection] { sections.filter { $0.isEnabled } }

    /// Starts or stops a section to match its switch. One that is off at launch
    /// is told to stop all the same, so it can withdraw whatever an earlier run
    /// left scheduled.
    private func sync(_ section: BarSection, launching: Bool = false) {
        let id = ObjectIdentifier(section)
        if section.isEnabled {
            guard !running.contains(id) else { return }
            running.insert(id)
            section.activate { [weak self] in self?.setNeedsRedraw() }
        } else if running.remove(id) != nil || launching {
            section.deactivate()
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
        let groups = enabled
            .map { $0.titleSegments(compact: compact) }
            .filter { !$0.isEmpty }

        let title = NSMutableAttributedString()
        title.append(Segment.label(" ").attributed)
        for (i, group) in groups.enumerated() {
            if i > 0 { title.append(Segment.label(" · ").attributed) }
            for segment in group { title.append(segment.attributed) }
        }
        // Every section switched off, or none with anything to say: the icon
        // alone would look like a hang, so put something beside it.
        if groups.isEmpty { title.append(Segment.label("⋯").attributed) }

        button.attributedTitle = title
    }

    // MARK: Menu

    private func rebuildMenu() {
        menu.removeAllItems()

        for section in enabled {
            menu.addItem(MenuKit.header(section.name))
            for row in section.menuRows() { menu.addItem(row) }
            menu.addItem(.separator())
        }

        // "Refresh All" reads oddly with one section, which is how a section
        // repository's own app is built — and switching off its only section
        // would leave that app with nothing, so it gets no Sections menu.
        let refresh = sections.count > 1 ? "Refresh All" : "Refresh Now"
        menu.addItem(MenuKit.action(refresh, #selector(refreshAll), key: "r", target: self))
        if sections.count > 1 { menu.addItem(sectionsSubmenu()) }

        let compact = MenuKit.action("Compact Display", #selector(toggleCompact), target: self)
        compact.state = Defaults.bool(Defaults.compact) ? .on : .off
        menu.addItem(compact)

        menu.addItem(.separator())
        menu.addItem(MenuKit.action("Quit \(Self.appName)", #selector(quit), key: "q", target: self))
    }

    /// A switch per section. Off takes it out of the menu bar and the dropdown,
    /// and stops it.
    private func sectionsSubmenu() -> NSMenuItem {
        let submenu = NSMenu()
        for section in sections {
            let item = MenuKit.action(section.name, #selector(toggleSection),
                                      target: self, object: section.showKey)
            item.state = section.isEnabled ? .on : .off
            submenu.addItem(item)
        }

        let parent = NSMenuItem(title: "Sections", action: nil, keyEquivalent: "")
        parent.submenu = submenu
        return parent
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        rebuildMenu()
    }

    func menuWillOpen(_ menu: NSMenu) {
        menuIsOpen = true
        for section in enabled { section.refresh(force: false) }
    }

    func menuDidClose(_ menu: NSMenu) {
        menuIsOpen = false
    }

    // MARK: Actions

    @objc private func refreshAll() {
        for section in enabled { section.refresh(force: true) }
    }

    // The menu closes on the click and is rebuilt on its way open again, so
    // neither switch needs to update its own checkmark.

    @objc private func toggleSection(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String,
              let section = sections.first(where: { $0.showKey == key }) else { return }
        Defaults.toggle(key)
        sync(section)
        renderTitle()
    }

    @objc private func toggleCompact() {
        Defaults.toggle(Defaults.compact)
        renderTitle()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
