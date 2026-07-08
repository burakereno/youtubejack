import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        UpdateChecker.shared.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        UpdateChecker.shared.stop()
    }
}

@main
struct YouTubeJackApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup("YouTubeJack", id: "main") {
            ContentView()
                .environmentObject(model)
        }
        .commands {
            CommandMenu("İndirme") {
                Button("Linki Analiz Et") {
                    Task { await model.analyzeCurrentURL() }
                }
                .keyboardShortcut(.return, modifiers: [.command])

                Button("Seçileni Kuyruğa Ekle") {
                    model.addSelectedToQueue()
                }
                .keyboardShortcut("d", modifiers: [.command])

                Button(model.queueControlTitle) {
                    model.toggleQueuePlayback()
                }
                .keyboardShortcut(.space, modifiers: [.command])

                Divider()

                Button("Tamamlananları Temizle") {
                    model.clearFinished()
                }
            }
        }

        Settings {
            SettingsView()
                .environmentObject(model)
        }
    }
}
