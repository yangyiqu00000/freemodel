#!/usr/bin/env swift
import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let appPath = root.appendingPathComponent("FreeModelMenuBar").appendingPathComponent("FreeModelMenuBar").appendingPathComponent("FreeModelMenuBarApp.swift")
let menuPath = root.appendingPathComponent("FreeModelMenuBar").appendingPathComponent("FreeModelMenuBar").appendingPathComponent("MenuContent.swift")

let appSource = try String(contentsOf: appPath, encoding: .utf8)
let menuSource = try String(contentsOf: menuPath, encoding: .utf8)

guard appSource.contains("SettingsWindowController.shared.configure") == false else {
    fputs("App should not configure the settings window from @StateObject init.\n", stderr)
    exit(1)
}

guard menuSource.contains("SettingsWindowController.shared.openSettings("),
      menuSource.contains("balanceManager: balanceManager"),
      menuSource.contains("accountManager: accountManager"),
      menuSource.contains("routerManager: routerManager") else {
    fputs("Settings button does not pass active managers to the window controller.\n", stderr)
    exit(1)
}

let controllerPath = root.appendingPathComponent("FreeModelMenuBar").appendingPathComponent("FreeModelMenuBar").appendingPathComponent("SettingsWindowController.swift")
let controllerSource = try String(contentsOf: controllerPath, encoding: .utf8)

guard controllerSource.contains("@MainActor") else {
    fputs("SettingsWindowController must be main-actor isolated.\n", stderr)
    exit(1)
}

guard controllerSource.contains("func openSettings(balanceManager: BalanceManager, accountManager: AccountManager, routerManager: RouterManager)") else {
    fputs("SettingsWindowController must accept active managers.\n", stderr)
    exit(1)
}

guard !controllerSource.contains("BalanceManager()") else {
    fputs("SettingsWindowController should not create a fallback BalanceManager.\n", stderr)
    exit(1)
}

guard !controllerSource.contains("AccountManager()") else {
    fputs("SettingsWindowController should not create a fallback AccountManager.\n", stderr)
    exit(1)
}

guard controllerSource.contains("contentViewController") else {
    fputs("Settings window should retain its hosting controller via contentViewController.\n", stderr)
    exit(1)
}

print("settings-window-check-pass")
