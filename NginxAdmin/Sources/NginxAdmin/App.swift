import AppKit
import SwiftUI
import UserNotifications

@main
struct NginxAdminApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            PanelView()
                .environmentObject(model.prefs)
                .environmentObject(model.monitor)
        } label: {
            MenuBarLabel(state: model.monitor.menuBar, prefs: model.prefs)
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
final class AppModel: ObservableObject {
    let prefs: AppPreferences
    let monitor: ServerMonitor

    init() {
        prefs = AppPreferences()
        monitor = ServerMonitor(prefs: prefs)
        monitor.begin()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        if Bundle.main.bundleURL.pathExtension == "app" {
            UNUserNotificationCenter.current().delegate = self
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}

/// The menu bar icon's content. It only publishes when the icon or text actually changes,
/// so the menu bar isn't redrawn on every status check.
@MainActor
final class MenuBarState: ObservableObject {
    @Published private(set) var icon = MenuBarLabel.icon(for: .checking)
    @Published private(set) var text: String? = "…"
    private var iconPhase = ServerPhase.checking.title

    func update(phase: ServerPhase, text: String?) {
        if phase.title != iconPhase {
            iconPhase = phase.title
            icon = MenuBarLabel.icon(for: phase)
        }
        if text != self.text { self.text = text }
    }
}

/// Menu bar icon: colour shows the state at a glance.
struct MenuBarLabel: View {
    @ObservedObject var state: MenuBarState
    @ObservedObject var prefs: AppPreferences

    var body: some View {
        if prefs.showTextInMenuBar, let text = state.text {
            HStack(spacing: 4) {
                Image(nsImage: state.icon)
                Text(text)
            }
        } else {
            Image(nsImage: state.icon)
        }
    }

    static func icon(for phase: ServerPhase) -> NSImage {
        let up = phase.isUp || phase.isBusy
        let name = up ? "video.fill" : "video.slash.fill"
        var config = NSImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
        let plain = phase == .stopped || phase == .dockerOff
        if !plain {
            config = config.applying(NSImage.SymbolConfiguration(paletteColors: [phase.nsColor]))
        }
        let image = NSImage(systemSymbolName: name, accessibilityDescription: phase.title)?
            .withSymbolConfiguration(config) ?? NSImage()
        image.isTemplate = plain
        return image
    }
}
