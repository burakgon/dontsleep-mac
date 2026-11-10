import AppKit

/// What the app shows the first time it is opened. It has no window of its own, so this is
/// where it says where it lives, and where the person picks the icon it wears there.
///
/// It is a standard alert with a row of icons in it, which macOS lays out and draws. The
/// icon in the menu bar changes as the choices are tried, so the preview is the real thing.
/// Afterwards the app starts afresh, which gives back the memory all of this took.
final class Welcome: NSObject {
    private let menuBarItem: MenuBarItem
    private let picker = NSSegmentedControl()
    private let name = NSTextField(labelWithString: "")
    private let openAtLogin = NSButton(checkboxWithTitle: "Open DontSleep when I log in", target: nil, action: nil)

    init(menuBarItem: MenuBarItem) {
        self.menuBarItem = menuBarItem
    }

    func run() {
        let alert = NSAlert()
        alert.messageText = "Welcome to DontSleep"
        alert.informativeText = """
            DontSleep lives in your menu bar. Click its icon to keep your Mac awake, or right-click it to switch right away.

            Choose an icon for it. You can change it later in Settings.
            """
        alert.accessoryView = makeChoices()
        alert.addButton(withTitle: "Done")
        NSApp.activate()
        alert.runModal()

        let wantsLogin = openAtLogin.state == .on
        if wantsLogin != LoginItem.isEnabled {
            try? LoginItem.setEnabled(wantsLogin)
        }
    }

    private func makeChoices() -> NSView {
        let styles = IconStyle.allCases
        picker.segmentCount = styles.count
        picker.trackingMode = .selectOne
        picker.controlSize = .large
        picker.target = self
        picker.action = #selector(pick)
        for (index, style) in styles.enumerated() {
            // Shown as they look while keeping the Mac awake; the menu bar shows the other half.
            picker.setImage(style.image(isActive: true), forSegment: index)
            picker.setImageScaling(.scaleProportionallyDown, forSegment: index)
            picker.setWidth(46, forSegment: index)
            picker.setToolTip(style.title, forSegment: index)
        }
        picker.selectedSegment = styles.firstIndex(of: menuBarItem.iconStyle) ?? 0
        picker.setAccessibilityLabel("Menu bar icon")
        name.stringValue = menuBarItem.iconStyle.title
        name.textColor = .secondaryLabelColor
        name.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        openAtLogin.state = LoginItem.isEnabled ? .on : .off

        let choices = NSStackView(views: [picker, name, openAtLogin])
        choices.orientation = .vertical
        choices.alignment = .centerX
        choices.spacing = 6
        choices.setCustomSpacing(16, after: name)
        choices.edgeInsets = NSEdgeInsets(top: 4, left: 0, bottom: 2, right: 0)
        choices.frame.size = choices.fittingSize
        return choices
    }

    @objc private func pick() {
        let style = IconStyle.allCases[picker.selectedSegment]
        menuBarItem.iconStyle = style
        name.stringValue = style.title
    }
}
