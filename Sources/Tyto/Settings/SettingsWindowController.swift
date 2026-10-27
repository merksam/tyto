import AppKit
import SwiftUI

/// Hosts the SwiftUI settings panes in a normal titled window, one toolbar tab each.
@MainActor final class SettingsWindowController {
    enum Pane: Int { case general, destinations }

    private var window: NSWindow?
    private var tabs: NSTabViewController?
    let destinations = DestinationsModel()

    var isVisible: Bool { window?.isVisible ?? false }
    var frame: CGRect? { window?.frame }

    func close() { window?.orderOut(nil) }

    func show(_ pane: Pane? = nil) {
        if window == nil {
            let tabs = NSTabViewController()
            tabs.tabStyle = .toolbar
            tabs.addTabViewItem(Self.tab(SettingsView(), label: "General", symbol: "gearshape"))
            tabs.addTabViewItem(Self.tab(DestinationsView(model: destinations), label: "Destinations", symbol: "paperplane"))
            let w = NSWindow(contentViewController: tabs)
            w.styleMask = [.titled, .closable, .miniaturizable]
            w.isReleasedWhenClosed = false
            w.center()
            window = w
            self.tabs = tabs
        }
        if let pane { tabs?.selectedTabViewItemIndex = pane.rawValue }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    /// Each pane reports its own size, so the window fits whichever tab is showing.
    private static func tab(_ view: some View, label: String, symbol: String) -> NSTabViewItem {
        let hosting = NSHostingController(rootView: view)
        hosting.sizingOptions = [.preferredContentSize]
        hosting.title = label
        let item = NSTabViewItem(viewController: hosting)
        item.label = label
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        return item
    }
}
