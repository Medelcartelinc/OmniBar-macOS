// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Medelcartelinc

import AppKit
import Foundation
import IOKit.kext

/// Service to monitor and toggle Intel CPU Turbo Boost state.
/// Integrates with Turbo Boost Switcher (Pro or standard) and checks loaded kext status.
final class TurboBoostService: ObservableObject {
    static let shared = TurboBoostService()

    @Published private(set) var isSupported: Bool = false
    @Published private(set) var isTurboBoostEnabled: Bool = true
    @Published private(set) var isAppInstalled: Bool = false
    @Published private(set) var isAppRunning: Bool = false

    private static let bundleIDPro = "com.rugarciap.Turbo-Boost-Switcher-Pro"
    private static let bundleIDFree = "com.rugarciap.Turbo-Boost-Switcher"
    private static let kextID = "com.rugarciap.DisableTurboBoost"

    private var refreshTimer: Timer?

    private init() {
        checkSupport()
        refresh()
    }

    private func checkSupport() {
        #if arch(x86_64)
        isSupported = true
        #else
        isSupported = TemperatureSensorSelector.currentPlatform() == .generic
        #endif
    }

    func startMonitoring() {
        refresh()
        if refreshTimer == nil {
            refreshTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
                self?.refresh()
            }
        }
    }

    func stopMonitoring() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    func refresh() {
        guard isSupported else { return }

        // 1. Check if DisableTurboBoost kext is loaded
        if let info = KextManagerCopyLoadedKextInfo(nil, nil)?.takeRetainedValue() as? [String: Any] {
            let isKextLoaded = info[Self.kextID] != nil
            self.isTurboBoostEnabled = !isKextLoaded
        }

        // 2. Check if Turbo Boost Switcher app is installed
        let proURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.bundleIDPro)
            ?? URL(fileURLWithPath: "/Applications/Turbo Boost Switcher Pro.app")
        let freeURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.bundleIDFree)
            ?? URL(fileURLWithPath: "/Applications/Turbo Boost Switcher.app")
        let proExists = FileManager.default.fileExists(atPath: proURL.path)
        let freeExists = FileManager.default.fileExists(atPath: freeURL.path)
        self.isAppInstalled = proExists || freeExists

        // 3. Check if app is currently running
        let running = NSWorkspace.shared.runningApplications
        self.isAppRunning = running.contains { app in
            app.bundleIdentifier == Self.bundleIDPro ||
            app.bundleIdentifier == Self.bundleIDFree ||
            (app.localizedName ?? "").contains("Turbo Boost Switcher")
        }
    }

    func toggleTurboBoost() {
        guard isSupported else { return }

        // If Pro app is installed, send native AppleScript command
        let proURL = URL(fileURLWithPath: "/Applications/Turbo Boost Switcher Pro.app")
        if FileManager.default.fileExists(atPath: proURL.path) || isAppRunning {
            let command = isTurboBoostEnabled ? "disabletb" : "enabletb"
            let appleScript = """
            tell application "Turbo Boost Switcher Pro"
                \(command)
            end tell
            """
            DispatchQueue.global(qos: .userInitiated).async {
                var error: NSDictionary?
                if let scriptObj = NSAppleScript(source: appleScript) {
                    scriptObj.executeAndReturnError(&error)
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    self.refresh()
                }
            }
            return
        }

        // If standard app is installed, open it
        openSwitcherApp()
    }

    func openSwitcherApp() {
        let proURL = URL(fileURLWithPath: "/Applications/Turbo Boost Switcher Pro.app")
        let freeURL = URL(fileURLWithPath: "/Applications/Turbo Boost Switcher.app")
        if FileManager.default.fileExists(atPath: proURL.path) {
            NSWorkspace.shared.open(proURL)
        } else if FileManager.default.fileExists(atPath: freeURL.path) {
            NSWorkspace.shared.open(freeURL)
        } else {
            if let webURL = URL(string: "https://www.rugarciap.com/turbo-boost-switcher-for-os-x/") {
                NSWorkspace.shared.open(webURL)
            }
        }
    }
}
