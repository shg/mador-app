//
//  AppDelegate.swift
//  Mador
//
//  Created by Ryan Hanson on 6/11/19.
//  Copyright © 2019 Ryan Hanson. All rights reserved.
//

import Cocoa
import Sparkle
import ServiceManagement
import os.log

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {

    static let launcherAppId = "org.kakera.MadorLauncher"

    private let accessibilityAuthorization = AccessibilityAuthorization()
    private let statusItem = MadorStatusItem.instance
    static let windowHistory = WindowHistory()
    var updaterController: SPUStandardUpdaterController!
    var hasPendingUpdate = false {
        didSet {
            Notification.Name.updateAvailability.post()
        }
    }

    private var shortcutManager: ShortcutManager!
    private var windowManager: WindowManager!
    private var applicationToggle: ApplicationToggle!
    private var windowCalculationFactory: WindowCalculationFactory!
    private var prefsWindowController: NSWindowController?
    
    private var prevActiveAppObservation: NSKeyValueObservation?
    private var prevActiveApp: NSRunningApplication?
    private var additionalSizeMenuItems: [NSMenuItem] = []
    private var dynamicMenuItemCount: Int = 0

    @IBOutlet weak var mainStatusMenu: NSMenu!
    @IBOutlet weak var unauthorizedMenu: NSMenu!
    @IBOutlet weak var ignoreMenuItem: NSMenuItem!
    @IBOutlet weak var viewLoggingMenuItem: NSMenuItem!
    @IBOutlet weak var updatesMenuItem: NSMenuItem!
    @IBOutlet weak var quitMenuItem: NSMenuItem!
    
    static var instance: AppDelegate {
        NSApp.delegate as! AppDelegate
    }
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        Defaults.migrateLegacyDefaultsIfNeeded()
        Defaults.loadFromSupportDir()
        migrateShowEighthsInMenu()

        checkVersion()
        mainStatusMenu.delegate = self
        checkLaunchOnLogin()
        
        let alreadyTrusted = accessibilityAuthorization.checkAccessibility {
            self.showWelcomeWindow()
            self.checkForConflictingApps()
            self.statusItem.statusMenu = self.mainStatusMenu
            self.accessibilityTrusted()
        }
        
        if alreadyTrusted {
            accessibilityTrusted()
        }
        
        statusItem.statusMenu = alreadyTrusted
            ? mainStatusMenu
            : unauthorizedMenu
        statusItem.refreshVisibility()
        
        mainStatusMenu.autoenablesItems = false
        insertManageLayoutsMenuItem()
        addWindowActionMenuItems()

        NotificationCenter.default.addObserver(self, selector: #selector(rebuildMenu), name: .showAdditionalSizesInMenuChanged, object: nil)

        updaterController = SPUStandardUpdaterController(updaterDelegate: nil, userDriverDelegate: self)
        
        checkAutoCheckForUpdates()
        
        Notification.Name.configImported.onPost(using: { _ in
            self.checkAutoCheckForUpdates()
            self.statusItem.refreshVisibility()
            self.applicationToggle.reloadFromDefaults()
            self.shortcutManager.reloadFromDefaults()
        })
        
        prevActiveAppObservation = NSWorkspace.shared.observe(\.frontmostApplication, options: .old) { workspace, change in
            self.prevActiveApp = change.oldValue ?? nil
        }
    }
    
    func checkVersion() {
        let currentVersion = Bundle.main.infoDictionary?["CFBundleVersion"] as? String
        if let lastVersion = Defaults.lastVersion.value,
           let intLastVersion = Int(lastVersion) {
            if intLastVersion < 46 {
                MASShortcutMigration.migrate()
            }
            if intLastVersion < 72 {
                if #available(macOS 13, *) {
                    SMLoginItemSetEnabled(AppDelegate.launcherAppId as CFString, false)
                }
            }
        } else {
            Defaults.installVersion.value = currentVersion
            Defaults.allowAnyShortcut.enabled = true
        }
        
        Defaults.lastVersion.value = currentVersion
    }
    
    func applicationWillBecomeActive(_ notification: Notification) {
        Notification.Name.appWillBecomeActive.post()
    }
    
    func checkAutoCheckForUpdates() {
        updaterController.updater.automaticallyChecksForUpdates = Defaults.SUEnableAutomaticChecks.enabled
    }
    
    func accessibilityTrusted() {
        self.windowCalculationFactory = WindowCalculationFactory()
        self.windowManager = WindowManager()
        self.shortcutManager = ShortcutManager(windowManager: windowManager)
        self.applicationToggle = ApplicationToggle(shortcutManager: shortcutManager)
        self.statusItem.primaryAction = { [weak self] in
            self?.shortcutManager?.openChooserFromStatusItem()
        }
    }

    func checkForConflictingApps() {
        let conflictingAppsIds: [String: String] = [
            "com.divisiblebyzero.Spectacle": "Spectacle",
            "com.crowdcafe.windowmagnet": "Magnet",
            "com.hegenberg.BetterSnapTool": "BetterSnapTool",
            "com.manytricks.Moom": "Moom"
        ]
        
        let runningApps = NSWorkspace.shared.runningApplications
        for app in runningApps {
            guard let bundleId = app.bundleIdentifier else { continue }
            if let conflictingAppName = conflictingAppsIds[bundleId] {
                AlertUtil.oneButtonAlert(question: "Potential window manager conflict: \(conflictingAppName)", text: "Since \(conflictingAppName) might have some overlapping behavior with Mador, it's recommended that you either disable or quit \(conflictingAppName).")
                break
            }
        }
        
    }
    
    private func showWelcomeWindow() {
        Defaults.alternateDefaultShortcuts.enabled = true
        Defaults.subsequentExecutionMode.value = .acrossMonitor
    }
    
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if Defaults.relaunchOpensMenu.enabled {
            statusItem.openMenu()
        }
        return false
    }
    
    @IBAction func openPreferences(_ sender: Any) {
        if prefsWindowController == nil {
            prefsWindowController = BasicPreferencesWindowController()
        }
        NSApp.activate(ignoringOtherApps: true)
        prefsWindowController?.showWindow(self)
        prefsWindowController?.window?.makeKeyAndOrderFront(self)
    }

    @IBAction func openLayoutManager(_ sender: Any) {
        shortcutManager?.openLayoutManagerFromMenu()
    }
    
    @IBAction func showAbout(_ sender: Any) {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(sender)
    }
    
    @IBAction func viewLogging(_ sender: Any) {
        Logger.showLogging(sender: sender)
    }
    
    @IBAction func ignoreFrontMostApp(_ sender: NSMenuItem) {
        if sender.state == .on {
            applicationToggle.enableApp()
        } else {
            applicationToggle.disableApp()
        }
    }
    
    @IBAction func checkForUpdates(_ sender: Any) {
        updaterController.checkForUpdates(sender)
    }
    
    @IBAction func authorizeAccessibility(_ sender: Any) {
        accessibilityAuthorization.showAuthorizationWindow()
    }

    private func checkLaunchOnLogin() {
        if #available(macOS 13.0, *) {
            if Defaults.launchOnLogin.enabled, !LaunchOnLogin.isEnabled {
                LaunchOnLogin.isEnabled = true
            }
        } else {
            let running = NSWorkspace.shared.runningApplications
            let isRunning = !running.filter({$0.bundleIdentifier == AppDelegate.launcherAppId}).isEmpty
            if isRunning {
                let killNotification = Notification.Name("killLauncher")
                DistributedNotificationCenter.default().post(name: killNotification, object: Bundle.main.bundleIdentifier!)
            }
            if !Defaults.SUHasLaunchedBefore {
                Defaults.launchOnLogin.enabled = true
            }
            
            // Even if we are already set up to launch on login, setting it again since macOS can be buggy with this type of launch on login.
            if Defaults.launchOnLogin.enabled {
                let smLoginSuccess = SMLoginItemSetEnabled(AppDelegate.launcherAppId as CFString, true)
                if !smLoginSuccess {
                    if #available(OSX 10.12, *) {
                        os_log("Unable to enable launch at login. Attempting one more time.", type: .info)
                    }
                    SMLoginItemSetEnabled(AppDelegate.launcherAppId as CFString, true)
                }
            }
        }
    }

    private func insertManageLayoutsMenuItem() {
        let settingsItemIndex = mainStatusMenu.indexOfItem(withTitle: "Settings…")
        guard mainStatusMenu.item(withTag: 9001) == nil,
              settingsItemIndex != -1 else {
            return
        }

        let menuItem = NSMenuItem(title: "Manage Layouts…", action: #selector(openLayoutManager(_:)), keyEquivalent: "")
        menuItem.tag = 9001
        menuItem.target = self
        mainStatusMenu.insertItem(menuItem, at: settingsItemIndex + 1)
    }
    
}

extension AppDelegate: NSMenuDelegate {
    
    func menuWillOpen(_ menu: NSMenu) {
        if menu != mainStatusMenu {
            updateWindowActionMenuItems(menu: menu)
            return
        }
        
        if let frontAppName = ApplicationToggle.frontAppName {
            let ignoreString = NSLocalizedString("D99-0O-MB6.title", tableName: "Main", value: "Ignore frontmost.app", comment: "")
            ignoreMenuItem.title = ignoreString.replacingOccurrences(of: "frontmost.app", with: frontAppName)
            ignoreMenuItem.state = ApplicationToggle.shortcutsDisabled ? .on : .off
            ignoreMenuItem.isHidden = false
        } else {
            ignoreMenuItem.isHidden = true
        }
        
        updateWindowActionMenuItems(menu: menu)
        viewLoggingMenuItem.keyEquivalentModifierMask = .option
        quitMenuItem.keyEquivalent = "q"
        quitMenuItem.keyEquivalentModifierMask = .command
    }
    
    private func updateWindowActionMenuItems(menu: NSMenu) {
        return
    }
    
    func menuDidClose(_ menu: NSMenu) {
        for menuItem in menu.items {
            
            menuItem.keyEquivalent = ""
            menuItem.keyEquivalentModifierMask = NSEvent.ModifierFlags()
            
            menuItem.isEnabled = true
        }
    }
    
    @objc func executeMenuWindowAction(sender: NSMenuItem) {
        guard let windowAction = sender.representedObject as? WindowAction else { return }
        windowAction.postMenu()
    }
    
    func addWindowActionMenuItems() {
        dynamicMenuItemCount = 0
    }

    @objc func rebuildMenu() {
        // Remove all dynamically added items
        for _ in 0..<dynamicMenuItemCount {
            mainStatusMenu.removeItem(at: 0)
        }
        dynamicMenuItemCount = 0
        additionalSizeMenuItems.removeAll()
        addWindowActionMenuItems()
    }

    private func migrateShowEighthsInMenu() {
        let oldKey = "showEighthsInMenu"
        let oldValue = UserDefaults.standard.integer(forKey: oldKey)
        if oldValue != 0 && Defaults.showAdditionalSizesInMenu.notSet {
            Defaults.showAdditionalSizesInMenu.enabled = (oldValue == 1)
        }
    }

    struct CategoryMenu {
        let menu: NSMenu
        let category: WindowActionCategory
    }

}

// todo mode
extension AppDelegate {
    func initializeTodo(_ bringToFront: Bool = true) {
        self.showHideTodoMenuItems()
        TodoManager.registerUnregisterToggleShortcut()
        TodoManager.registerUnregisterReflowShortcut()
        TodoManager.moveAllIfNeeded(bringToFront)
    }

    enum TodoItem {
        case mode, app, reflow, separator, window

        var tag: Int {
            switch self {
            case .mode: return 101
            case .app: return 102
            case .reflow: return 103
            case .separator: return 104
            case .window: return 105
            }
        }
        
        static let tags = [101, 102, 103, 104, 105]
    }

    private func addTodoModeMenuItems(startingIndex: Int) {
        var menuIndex = startingIndex

        let todoModeItemTitle = NSLocalizedString("Enable Todo Mode", tableName: "Main", value: "", comment: "")
        let todoModeMenuItem = NSMenuItem(title: todoModeItemTitle, action: #selector(toggleTodoMode), keyEquivalent: "")
        todoModeMenuItem.tag = TodoItem.mode.tag
        todoModeMenuItem.target = self
        mainStatusMenu.insertItem(todoModeMenuItem, at: menuIndex)
        menuIndex += 1

        let todoAppItemTitle = NSLocalizedString("Use frontmost.app as Todo App", tableName: "Main", value: "", comment: "")
        let todoAppMenuItem = NSMenuItem(title: todoAppItemTitle, action: #selector(setTodoApp), keyEquivalent: "")
        todoAppMenuItem.tag = TodoItem.app.tag
        mainStatusMenu.insertItem(todoAppMenuItem, at: menuIndex)
        menuIndex += 1

        let todoWindowItemTitle = NSLocalizedString("Use as Todo Window", tableName: "Main", value: "", comment: "")
        let todoWindowMenuItem = NSMenuItem(title: todoWindowItemTitle, action: #selector(setTodoWindow), keyEquivalent: "")
        todoWindowMenuItem.tag = TodoItem.window.tag
        mainStatusMenu.insertItem(todoWindowMenuItem, at: menuIndex)
        menuIndex += 1
        
        let todoReflowItemTitle = NSLocalizedString("Reflow Todo", tableName: "Main", value: "", comment: "")
        let todoReflowItem = NSMenuItem(title: todoReflowItemTitle, action: #selector(todoReflow), keyEquivalent: "")
        todoReflowItem.tag = TodoItem.reflow.tag
        mainStatusMenu.insertItem(todoReflowItem, at: menuIndex)
        menuIndex += 1
        
        let separator = NSMenuItem.separator()
        separator.tag = TodoItem.separator.tag
        mainStatusMenu.insertItem(separator, at: menuIndex)
        
        showHideTodoMenuItems()
    }
    
    private func showHideTodoMenuItems() {
        for item in mainStatusMenu.items {
            if TodoItem.tags.contains(item.tag) {
                item.isHidden = !Defaults.todo.userEnabled
            }
        }
    }

    @objc func toggleTodoMode(_ sender: NSMenuItem) {
        let enabled = sender.state == .off
        TodoManager.setTodoMode(enabled)
    }

    @objc func setTodoApp(_ sender: NSMenuItem) {
        applicationToggle.setTodoApp()
        TodoManager.moveAllIfNeeded()
    }

    @objc func todoReflow(_ sender: NSMenuItem) {
        TodoManager.moveAll()
    }
    
    @objc func setTodoWindow(_ sender: NSMenuItem) {
        TodoManager.resetTodoWindow()
        TodoManager.moveAllIfNeeded()
    }

    private func updateTodoModeMenuItems(menu: NSMenu) {
        guard Defaults.todo.userEnabled,
              let todoAppMenuItem = menu.item(withTag: TodoItem.app.tag),
              let todoModeMenuItem = menu.item(withTag: TodoItem.mode.tag),
              let todoReflowMenuItem = menu.item(withTag: TodoItem.reflow.tag),
              let todoWindowMenuItem = menu.item(withTag: TodoItem.window.tag)
        else {
            return
        }

        if let frontAppName = ApplicationToggle.frontAppName {
            let appString = NSLocalizedString("Use frontmost.app as Todo App", tableName: "Main", value: "", comment: "")
            todoAppMenuItem.title = appString.replacingOccurrences(
                of: "frontmost.app", with: frontAppName)
            todoAppMenuItem.isEnabled = !applicationToggle.todoAppIsActive()
            todoAppMenuItem.state = applicationToggle.todoAppIsActive() ? .on : .off
            todoAppMenuItem.isHidden = false
        } else {
            todoAppMenuItem.isHidden = true
        }

        todoModeMenuItem.state = Defaults.todoMode.enabled ? .on : .off
        
        if let fullKeyEquivalent = TodoManager.getToggleKeyDisplay(),
            let keyEquivalent = fullKeyEquivalent.0?.lowercased() {
            todoModeMenuItem.keyEquivalent = keyEquivalent
            todoModeMenuItem.keyEquivalentModifierMask = fullKeyEquivalent.1
        }

        if let fullKeyEquivalent = TodoManager.getReflowKeyDisplay(),
            let keyEquivalent = fullKeyEquivalent.0?.lowercased() {
            todoReflowMenuItem.keyEquivalent = keyEquivalent
            todoReflowMenuItem.keyEquivalentModifierMask = fullKeyEquivalent.1
        }
        
        todoReflowMenuItem.isEnabled = Defaults.todoMode.enabled
        
        todoWindowMenuItem.isHidden = !applicationToggle.todoAppIsActive() || TodoManager.isTodoWindowFront()
    }
}

extension AppDelegate: NSWindowDelegate {
    
    func windowWillClose(_ notification: Notification) {
        NSApp.abortModal()
    }
    
}

extension AppDelegate {
    func application(_ application: NSApplication, open urls: [URL]) {
        if NSWorkspace.shared.frontmostApplication == NSRunningApplication.current {
            prevActiveApp?.activate()
        }
        DispatchQueue.main.async {
            
            func getUrlName(_ name: String) -> String {
                return name.map { $0.isUppercase ? "-" + $0.lowercased() : String($0) }.joined()
            }
            
            func extractBundleIdParameter(fromComponents components: URLComponents) -> String? {
                (components.queryItems?.first { $0.name == "app-bundle-id" })?.value ?? ApplicationToggle.frontAppId
            }
            
            func isValidParameter(bundleId: String?) -> Bool {
                let isValid = bundleId?.isEmpty != true
                if !isValid {
                    Logger.log("Received an empty app-bundle-id parameter. Either pass a valid app bundle id or remove the parameter.")
                }
                return isValid
            }
            
            for url in urls {
                guard
                    let components = URLComponents(url: url, resolvingAgainstBaseURL: true),
                    components.path.isEmpty
                else {
                    continue
                }
                    
                let name = (components.queryItems?.first { $0.name == "name" })?.value
                switch (components.host, name) {
                case ("execute-action", _):
                    let action = (WindowAction.active.first { getUrlName($0.name) == name })
                    action?.postUrl()
                case ("execute-task", "ignore-app"):
                    let bundleId = extractBundleIdParameter(fromComponents: components)
                    guard isValidParameter(bundleId: bundleId) else { continue }
                    self.applicationToggle.disableApp(appBundleId: bundleId)
                case ("execute-task", "unignore-app"):
                    let bundleId = extractBundleIdParameter(fromComponents: components)
                    guard isValidParameter(bundleId: bundleId) else { continue }
                    self.applicationToggle.enableApp(appBundleId: bundleId)
                default:
                    continue
                }
            }
        }
    }
}

extension AppDelegate: SPUStandardUserDriverDelegate {
    
    var supportsGentleScheduledUpdateReminders: Bool {
        true
    }

    func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool) -> Bool {
        if immediateFocus {
            return true
        }
        
        self.hasPendingUpdate = true
        updatesMenuItem.title = "Update Available…".localized
        return false
    }
    
    func standardUserDriverWillFinishUpdateSession() {
        self.hasPendingUpdate = false
        updatesMenuItem.title = "Check for Updates…".localized(key: "HIK-3r-i7E.title")
    }
}
