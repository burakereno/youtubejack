import YouTubeJackCore
import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var model: AppModel?
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        Task { await UpdateChecker.shared.start() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        UpdateChecker.shared.stop()
        model?.stopYTDLPUpdateChecks()
    }
}

@main
struct YouTubeJackApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()

    init() {
        AppLanguageSettings.shared.applySystemLanguageAtLaunch()
    }

    var body: some Scene {
        WindowGroup("YouTubeJack", id: "main") {
            ContentView()
                .environmentObject(model)
                .environment(\.locale, AppLanguageSettings.shared.language.locale)
                .onAppear { appDelegate.model = model }
                .task { await model.startYTDLPUpdateChecks() }
        }
        .defaultSize(width: 1160, height: 740)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button(L10n.string("Settings…")) {
                    model.presentSettingsPanel()
                }
                .keyboardShortcut(",", modifiers: [.command])
            }

            CommandMenu(L10n.string("Downloads")) {
                Button(L10n.string("Analyze Link")) {
                    Task { await model.analyzeCurrentURL() }
                }
                .keyboardShortcut(.return, modifiers: [.command])
                .disabled(model.canAnalyze == false)

                Button(L10n.string("Add Selection to Queue")) {
                    model.addSelectedToQueue()
                }
                .keyboardShortcut("d", modifiers: [.command])
                .disabled(model.canAddToQueue == false || model.isAnyDrawerPresented)

                Button(model.queueControlTitle) {
                    model.toggleQueuePlayback()
                }
                .keyboardShortcut(.space, modifiers: [.command])
                .disabled(model.canToggleQueue == false || model.isAnyDrawerPresented)

                Divider()

                Button(L10n.string("Clear Completed")) {
                    model.clearFinished()
                }
                .disabled(model.isAnyDrawerPresented)
            }
        }
    }
}
