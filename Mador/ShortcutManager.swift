//
//  ShortcutManager.swift
//  Mador
//
//  Created by Ryan Hanson on 6/12/19.
//  Copyright © 2019 Ryan Hanson. All rights reserved.
//

import Foundation
import Cocoa
import MASShortcut

class ShortcutManager {
    static let prefixShortcutDefaultsKey = Defaults.layoutChooserPrefixShortcutKey
    private static let prefixShortcut = Shortcut(NSEvent.ModifierFlags.option.rawValue, 12)
    
    let windowManager: WindowManager
    private var chooserWindowController: LayoutChooserWindowController?
    private var pendingExecutionTarget: PendingExecutionTarget?
    
    init(windowManager: WindowManager) {
        self.windowManager = windowManager
        
        MASShortcutBinder.shared()?.bindingOptions = [NSBindingOption.valueTransformerName: MASDictionaryTransformerName]
        
        registerDefaults()

        bindShortcuts()
        
        subscribeAll(selector: #selector(windowActionTriggered))
        
        Notification.Name.changeDefaults.onPost { _ in self.registerDefaults() }
    }
    
    public func reloadFromDefaults() {
        unsubscribe()
        unbindShortcuts()
        registerDefaults()
        bindShortcuts()
        subscribeAll(selector: #selector(windowActionTriggered))
    }
    
    public func bindShortcuts() {
        MASShortcutBinder.shared()?.bindShortcut(withDefaultsKey: Self.prefixShortcutDefaultsKey, toAction: openLayoutChooser)
    }
    
    public func unbindShortcuts() {
        MASShortcutBinder.shared()?.breakBinding(withDefaultsKey: Self.prefixShortcutDefaultsKey)
    }
    
    public func getKeyEquivalent(action: WindowAction) -> (String?, NSEvent.ModifierFlags)? {
        nil
    }
    
    deinit {
        unsubscribe()
    }
    
    private func registerDefaults() {
        let shortcut = MASShortcut(
            keyCode: Self.prefixShortcut.keyCode,
            modifierFlags: NSEvent.ModifierFlags(rawValue: Self.prefixShortcut.modifierFlags)
        )
        let defaultShortcuts = [Self.prefixShortcutDefaultsKey: shortcut]
        MASShortcutBinder.shared()?.registerDefaultShortcuts(defaultShortcuts)
    }

    @objc private func openLayoutChooser() {
        guard let windowElement = AccessibilityElement.getFrontWindowElement(),
              let windowId = windowElement.getWindowId(),
              let frontmostApplication = NSWorkspace.shared.frontmostApplication else {
            NSSound.beep()
            return
        }

        pendingExecutionTarget = PendingExecutionTarget(
            windowElement: windowElement,
            windowId: windowId,
            application: frontmostApplication
        )

        if chooserWindowController == nil {
            chooserWindowController = LayoutChooserWindowController(onAction: { action in
                self.execute(action: action)
            }, onClose: { [weak self] in
                self?.restorePendingExecutionTarget()
                self?.pendingExecutionTarget = nil
                self?.chooserWindowController = nil
            })
        }

        NSApp.activate(ignoringOtherApps: true)
        chooserWindowController?.showWindow(self)
        chooserWindowController?.refreshBindings()
        chooserWindowController?.window?.center()
        chooserWindowController?.window?.makeKeyAndOrderFront(self)
    }

    private func execute(action: WindowAction) {
        guard let pendingExecutionTarget else {
            NSSound.beep()
            return
        }

        NotificationCenter.default.post(
            name: action.notificationName,
            object: ExecutionParameters(
                action,
                windowElement: pendingExecutionTarget.windowElement,
                windowId: pendingExecutionTarget.windowId
            )
        )
    }

    private func restorePendingExecutionTarget() {
        guard let pendingExecutionTarget else { return }

        pendingExecutionTarget.application.activate(options: .activateIgnoringOtherApps)
        pendingExecutionTarget.windowElement.bringToFront(force: true)
    }
    
    @objc func windowActionTriggered(notification: NSNotification) {
        guard var parameters = notification.object as? ExecutionParameters else { return }
        
        if MultiWindowManager.execute(parameters: parameters) {
            return
        }
        
        // Check if repeat cycles displays
        if Defaults.subsequentExecutionMode.value == .cycleMonitor,
           parameters.action.classification != .size,
           parameters.action.classification != .display {
            guard let windowElement = parameters.windowElement ?? AccessibilityElement.getFrontWindowElement(),
                  let windowId = parameters.windowId ?? windowElement.getWindowId()
            else {
                NSSound.beep()
                return
            }
            
            if isRepeatAction(parameters: parameters, windowElement: windowElement, windowId: windowId) {
                if let screen = ScreenDetection().detectScreens(using: windowElement)?.adjacentScreens?.next{
                    parameters = ExecutionParameters(parameters.action, updateRestoreRect: parameters.updateRestoreRect, screen: screen, windowElement: windowElement, windowId: windowId)
                    // Bypass any other subsequent action by removing the last action
                    AppDelegate.windowHistory.lastRectangleActions.removeValue(forKey: windowId)
                }
            }
        }
        
        windowManager.execute(parameters)
    }
    
    private func isRepeatAction(parameters: ExecutionParameters, windowElement: AccessibilityElement, windowId: CGWindowID) -> Bool {
        
        if parameters.action == .maximize {
            if ScreenDetection().detectScreens(using: windowElement)?.currentScreen.visibleFrame.size == windowElement.frame.size {
                return true
            }
        }
        if parameters.action == AppDelegate.windowHistory.lastRectangleActions[windowId]?.action {
            return true
        }
        return false
    }
    
    private func subscribe(notification: WindowAction, selector: Selector) {
        NotificationCenter.default.addObserver(self, selector: selector, name: notification.notificationName, object: nil)
    }
    
    private func unsubscribe() {
        NotificationCenter.default.removeObserver(self)
    }
    
    private func subscribeAll(selector: Selector) {
        for windowAction in WindowAction.active {
            subscribe(notification: windowAction, selector: selector)
        }
    }
}

private struct PendingExecutionTarget {
    let windowElement: AccessibilityElement
    let windowId: CGWindowID
    let application: NSRunningApplication
}

private final class LayoutChooserWindowController: NSWindowController, NSWindowDelegate {
    private let chooserViewController: LayoutChooserViewController
    private let onClose: () -> Void

    init(onAction: @escaping (WindowAction) -> Void, onClose: @escaping () -> Void) {
        chooserViewController = LayoutChooserViewController(onAction: onAction)
        self.onClose = onClose

        let window = NSWindow(contentViewController: chooserViewController)
        window.title = "Choose Layout"
        window.setContentSize(NSSize(width: 320, height: 180))
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.level = .floating
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.center()
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.moveToActiveSpace]

        super.init(window: window)
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func refreshBindings() {
        chooserViewController.refreshBindings()
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        refreshBindings()
        window?.makeFirstResponder(chooserViewController.keyHandlingView)
    }

    func windowWillClose(_ notification: Notification) {
        onClose()
    }
}

private final class LayoutChooserViewController: NSViewController {
    fileprivate let keyHandlingView = LayoutChooserKeyHandlingView()

    private let leftKeyLabel = NSTextField(labelWithString: "")
    private let rightKeyLabel = NSTextField(labelWithString: "")
    private let onAction: (WindowAction) -> Void

    init(onAction: @escaping (WindowAction) -> Void) {
        self.onAction = onAction
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = keyHandlingView
        keyHandlingView.onAction = { [weak self] action in
            self?.onAction(action)
            self?.view.window?.close()
        }
        keyHandlingView.onCancel = { [weak self] in
            self?.view.window?.close()
        }
        buildInterface()
        refreshBindings()
    }

    func refreshBindings() {
        let leftKey = Defaults.layoutChooserLeftKey.value ?? "["
        let rightKey = Defaults.layoutChooserRightKey.value ?? "]"
        leftKeyLabel.stringValue = leftKey
        rightKeyLabel.stringValue = rightKey
        keyHandlingView.leftTrigger = leftKey
        keyHandlingView.rightTrigger = rightKey
    }

    private func buildInterface() {
        view.wantsLayer = true
        view.layer?.cornerRadius = 14
        view.layer?.cornerCurve = .continuous
        view.layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.82).cgColor

        let titleLabel = NSTextField(labelWithString: "Choose a Layout")
        titleLabel.font = NSFont.boldSystemFont(ofSize: 16)

        let descriptionLabel = NSTextField(wrappingLabelWithString: "Press the assigned key to place the captured window, or press Esc to cancel.")
        descriptionLabel.textColor = .secondaryLabelColor
        descriptionLabel.maximumNumberOfLines = 0

        let leftRow = makeRow(title: "Left Half", image: WindowAction.leftHalf.image, keyLabel: leftKeyLabel)
        let rightRow = makeRow(title: "Right Half", image: WindowAction.rightHalf.image, keyLabel: rightKeyLabel)

        let stack = NSStackView(views: [titleLabel, descriptionLabel, leftRow, rightRow])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 20),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -20),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor, constant: -20)
        ])
    }

    private func makeRow(title: String, image: NSImage, keyLabel: NSTextField) -> NSStackView {
        let imageView = NSImageView(frame: NSRect(x: 0, y: 0, width: 30, height: 20))
        imageView.image = image
        imageView.image?.size = NSSize(width: 30, height: 20)

        let titleLabel = NSTextField(labelWithString: title)

        let titleStack = NSStackView(views: [titleLabel, imageView])
        titleStack.orientation = .horizontal
        titleStack.alignment = .centerY
        titleStack.spacing = 10

        keyLabel.font = NSFont.monospacedSystemFont(ofSize: 14, weight: .medium)
        keyLabel.alignment = .center

        let keyContainer = NSBox()
        keyContainer.boxType = .custom
        keyContainer.cornerRadius = 6
        keyContainer.borderWidth = 1
        keyContainer.borderColor = .separatorColor
        keyContainer.contentViewMargins = NSSize(width: 12, height: 6)
        keyContainer.contentView = keyLabel
        keyContainer.translatesAutoresizingMaskIntoConstraints = false
        keyContainer.widthAnchor.constraint(equalToConstant: 56).isActive = true

        let row = NSStackView(views: [titleStack, keyContainer])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 16
        return row
    }
}

private final class LayoutChooserKeyHandlingView: NSView {
    var leftTrigger = "["
    var rightTrigger = "]"
    var onAction: ((WindowAction) -> Void)?
    var onCancel: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onCancel?()
            return
        }

        guard let input = event.characters, input.count == 1 else {
            NSSound.beep()
            return
        }

        if input == leftTrigger {
            onAction?(.leftHalf)
            return
        }
        if input == rightTrigger {
            onAction?(.rightHalf)
            return
        }

        NSSound.beep()
    }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }
}
