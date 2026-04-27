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
    private static let repeatedCustomLayoutInterval: TimeInterval = 5
    private static let smallScreenWidthThreshold: CGFloat = 1200
    
    let windowManager: WindowManager
    private var chooserWindowController: LayoutChooserWindowController?
    private var layoutManagerWindowController: LayoutManagerWindowController?
    private var pendingExecutionTarget: PendingExecutionTarget?
    private var lastKnownExecutionTarget: PendingExecutionTarget?
    private var isTransitioningFromChooserToLayoutManager = false
    private var lastCustomLayoutExecutions: [CGWindowID: CustomLayoutExecution] = [:]
    
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
        if let dictTransformer = ValueTransformer(forName: NSValueTransformerName(rawValue: MASDictionaryTransformerName)) {
            let dictValue = dictTransformer.reverseTransformedValue(shortcut)
            UserDefaults.standard.setValue(dictValue, forKey: Self.prefixShortcutDefaultsKey)
        }
    }

    @objc private func openLayoutChooser() {
        showLayoutChooser(captureTarget: true)
    }

    public func openChooserFromStatusItem() {
        if chooserWindowController?.window?.isVisible == true {
            chooserWindowController?.close()
            return
        }
        showLayoutChooser(captureTarget: true)
    }

    public func openLayoutManagerFromMenu() {
        pendingExecutionTarget = nil
        isTransitioningFromChooserToLayoutManager = false
        openLayoutManager()
    }

    private func makeChooserWindowController() -> LayoutChooserWindowController {
        LayoutChooserWindowController(onAction: { layout in
            self.execute(layout: layout)
        }, onManageLayouts: { [weak self] in
            self?.openLayoutManager()
        }, onClose: { [weak self] in
            self?.handleChooserClose()
        })
    }

    private func showLayoutChooser(captureTarget: Bool) {
        if captureTarget {
            if let executionTarget = captureCurrentExecutionTarget() {
                pendingExecutionTarget = executionTarget
                lastKnownExecutionTarget = executionTarget
            } else if pendingExecutionTarget == nil {
                pendingExecutionTarget = lastKnownExecutionTarget
            }
        }

        if chooserWindowController == nil {
            chooserWindowController = makeChooserWindowController()
        }

        NSApp.activate(ignoringOtherApps: true)
        chooserWindowController?.refreshBindings()
        chooserWindowController?.showWindow(self)
    }

    private func openLayoutManager() {
        if let chooserWindowController {
            isTransitioningFromChooserToLayoutManager = true
            chooserWindowController.close()
        }

        if layoutManagerWindowController == nil {
            layoutManagerWindowController = LayoutManagerWindowController(onClose: { [weak self] in
                guard let self else { return }
                self.layoutManagerWindowController = nil
                self.isTransitioningFromChooserToLayoutManager = false
                if self.pendingExecutionTarget != nil {
                    self.showLayoutChooser(captureTarget: false)
                }
            })
        }

        NSApp.activate(ignoringOtherApps: true)
        layoutManagerWindowController?.showWindow(self)
        layoutManagerWindowController?.refreshLayouts()
        layoutManagerWindowController?.window?.makeKeyAndOrderFront(self)
    }

    private func execute(layout: CustomLayout) {
        guard let executionTarget = pendingExecutionTarget ?? lastKnownExecutionTarget else {
            NSSound.beep()
            return
        }

        guard let usableScreens = ScreenDetection().detectScreens(using: executionTarget.windowElement) else {
            NSSound.beep()
            return
        }

        let destinationScreen = repeatedCustomLayoutDestinationScreen(
            for: layout,
            target: executionTarget,
            usableScreens: usableScreens
        ) ?? usableScreens.currentScreen
        let visibleFrame = destinationScreen.visibleFrame
        let currentFrame = executionTarget.windowElement.frame
        let targetFrame = layout.frame(in: visibleFrame).screenFlipped

        AppDelegate.windowHistory.restoreRects[executionTarget.windowId] = currentFrame
        AppDelegate.windowHistory.lastRectangleActions.removeValue(forKey: executionTarget.windowId)
        executionTarget.windowElement.setFrame(targetFrame)
        lastCustomLayoutExecutions[executionTarget.windowId] = CustomLayoutExecution(
            layoutId: layout.id,
            timestamp: Date()
        )
        lastKnownExecutionTarget = executionTarget
    }

    private func repeatedCustomLayoutDestinationScreen(
        for layout: CustomLayout,
        target: PendingExecutionTarget,
        usableScreens: UsableScreens
    ) -> NSScreen? {
        guard let previousExecution = lastCustomLayoutExecutions[target.windowId],
              previousExecution.layoutId == layout.id,
              Date().timeIntervalSince(previousExecution.timestamp) <= Self.repeatedCustomLayoutInterval
        else {
            return nil
        }

        guard layout.skipSmallScreen else {
            return usableScreens.adjacentScreens?.next
        }

        return nextEligibleScreen(after: usableScreens.currentScreen, in: usableScreens.screensOrdered)
    }

    private func nextEligibleScreen(after currentScreen: NSScreen, in orderedScreens: [NSScreen]) -> NSScreen? {
        guard orderedScreens.count > 1,
              let currentIndex = orderedScreens.firstIndex(of: currentScreen) else {
            return nil
        }

        for offset in 1..<orderedScreens.count {
            let candidate = orderedScreens[(currentIndex + offset) % orderedScreens.count]
            if candidate.frame.width >= Self.smallScreenWidthThreshold {
                return candidate
            }
        }

        return nil
    }

    private func restorePendingExecutionTarget() {
        guard let pendingExecutionTarget else { return }

        lastKnownExecutionTarget = pendingExecutionTarget
        pendingExecutionTarget.application.activate(options: .activateIgnoringOtherApps)
        DispatchQueue.main.async {
            pendingExecutionTarget.application.activate(options: .activateIgnoringOtherApps)
            pendingExecutionTarget.windowElement.bringToFront(force: true)
        }
    }

    private func handleChooserClose() {
        guard !isTransitioningFromChooserToLayoutManager else { return }

        restorePendingExecutionTarget()
        pendingExecutionTarget = nil
    }

    private func captureCurrentExecutionTarget() -> PendingExecutionTarget? {
        if let frontmostApplication = NSWorkspace.shared.frontmostApplication,
           frontmostApplication.bundleIdentifier != Bundle.main.bundleIdentifier,
           let windowElement = AccessibilityElement.getFrontWindowElement(),
           let windowId = windowElement.getWindowId() {
            return PendingExecutionTarget(
                windowElement: windowElement,
                windowId: windowId,
                application: frontmostApplication
            )
        }

        return lastKnownExecutionTarget
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

        if let windowId = parameters.windowId {
            lastCustomLayoutExecutions.removeValue(forKey: windowId)
        } else if let windowElement = parameters.windowElement ?? AccessibilityElement.getFrontWindowElement(),
                  let windowId = windowElement.getWindowId() {
            lastCustomLayoutExecutions.removeValue(forKey: windowId)
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

private struct CustomLayoutExecution {
    let layoutId: UUID
    let timestamp: Date
}

private final class LayoutChooserWindowController: NSWindowController, NSWindowDelegate {
    private let chooserViewController: LayoutChooserViewController
    private let onClose: () -> Void

    init(onAction: @escaping (CustomLayout) -> Void, onManageLayouts: @escaping () -> Void, onClose: @escaping () -> Void) {
        chooserViewController = LayoutChooserViewController(onAction: onAction, onManageLayouts: onManageLayouts)
        self.onClose = onClose
        let chooserSize = NSSize(width: 280, height: 210)

        let window = NSPanel(
            contentRect: NSRect(origin: .zero, size: chooserSize),
            styleMask: [.titled, .closable, .utilityWindow, .hudWindow],
            backing: .buffered,
            defer: false
        )
        window.title = "Choose Layout"
        window.styleMask.insert(.fullSizeContentView)
        window.contentViewController = chooserViewController
        window.appearance = NSAppearance(named: .vibrantDark)
        window.level = .floating
        window.isFloatingPanel = true
        window.hasShadow = true
        window.animationBehavior = .utilityWindow
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.setContentSize(chooserSize)
        window.contentMinSize = chooserSize
        window.contentMaxSize = chooserSize
        window.aspectRatio = chooserSize
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
    private let rowsStack = NSStackView()
    private let onAction: (CustomLayout) -> Void
    private let onManageLayouts: () -> Void

    init(onAction: @escaping (CustomLayout) -> Void, onManageLayouts: @escaping () -> Void) {
        self.onAction = onAction
        self.onManageLayouts = onManageLayouts
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = keyHandlingView
        keyHandlingView.onAction = { [weak self] layout in
            self?.onAction(layout)
            self?.view.window?.close()
        }
        keyHandlingView.onCancel = { [weak self] in
            self?.view.window?.close()
        }
        buildInterface()
        refreshBindings()
        Notification.Name.changeDefaults.onPost { [weak self] _ in
            self?.refreshBindings()
        }
    }

    func refreshBindings() {
        let layouts = Defaults.customLayouts.value
        keyHandlingView.layouts = layouts
        rebuildRows(layouts: layouts)
    }

    private func buildInterface() {
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor

        let titleLabel = NSTextField(labelWithString: "Choose a Layout")
        titleLabel.font = NSFont.boldSystemFont(ofSize: 14)
        titleLabel.textColor = .white

        let descriptionLabel = NSTextField(wrappingLabelWithString: "Press the assigned chooser key to place the captured window, or press Esc to cancel.")
        descriptionLabel.font = NSFont.systemFont(ofSize: 11)
        descriptionLabel.textColor = NSColor.white.withAlphaComponent(0.78)
        descriptionLabel.maximumNumberOfLines = 2

        rowsStack.orientation = .vertical
        rowsStack.alignment = .leading
        rowsStack.spacing = 10

        let rowsContainer = NSScrollView()
        rowsContainer.borderType = .noBorder
        rowsContainer.hasVerticalScroller = true
        rowsContainer.drawsBackground = false
        rowsContainer.translatesAutoresizingMaskIntoConstraints = false

        let rowsDocumentView = NSView()
        rowsDocumentView.translatesAutoresizingMaskIntoConstraints = false
        rowsContainer.documentView = rowsDocumentView
        rowsDocumentView.addSubview(rowsStack)

        NSLayoutConstraint.activate([
            rowsStack.topAnchor.constraint(equalTo: rowsDocumentView.topAnchor),
            rowsStack.leadingAnchor.constraint(equalTo: rowsDocumentView.leadingAnchor),
            rowsStack.trailingAnchor.constraint(equalTo: rowsDocumentView.trailingAnchor),
            rowsStack.bottomAnchor.constraint(equalTo: rowsDocumentView.bottomAnchor),
            rowsStack.widthAnchor.constraint(equalTo: rowsContainer.contentView.widthAnchor)
        ])

        let manageButton = NSButton(title: "Manage Layouts...", target: self, action: #selector(openLayoutManager))
        manageButton.bezelStyle = .rounded
        manageButton.isBordered = false
        manageButton.contentTintColor = .white
        manageButton.attributedTitle = NSAttributedString(
            string: "Manage Layouts...",
            attributes: [.foregroundColor: NSColor.white]
        )
        manageButton.wantsLayer = true
        manageButton.layer?.cornerRadius = 6
        manageButton.layer?.cornerCurve = .continuous
        manageButton.layer?.borderWidth = 1
        manageButton.layer?.borderColor = NSColor(white: 0.72, alpha: 0.9).cgColor
        manageButton.layer?.backgroundColor = NSColor(white: 1.0, alpha: 0.08).cgColor
        manageButton.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        manageButton.translatesAutoresizingMaskIntoConstraints = false
        manageButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 156).isActive = true
        manageButton.heightAnchor.constraint(equalToConstant: 28).isActive = true

        let stack = NSStackView(views: [titleLabel, descriptionLabel, rowsContainer])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(stack)
        view.addSubview(manageButton)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 16),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: manageButton.topAnchor, constant: -10),
            manageButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            manageButton.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -16)
        ])

        rowsContainer.heightAnchor.constraint(equalToConstant: 92).isActive = true
    }

    private func rebuildRows(layouts: [CustomLayout]) {
        rowsStack.arrangedSubviews.forEach {
            rowsStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }

        for layout in layouts {
            rowsStack.addArrangedSubview(makeRow(layout: layout))
        }
    }

    private func makeRow(layout: CustomLayout) -> NSStackView {
        let keyText = displayString(for: layout.triggerKeyCode, modifiersRawValue: layout.triggerModifiers)
        let keyLabel = NSTextField(labelWithString: keyText.isEmpty ? " " : keyText)
        keyLabel.font = NSFont.monospacedSystemFont(ofSize: 14, weight: .medium)
        keyLabel.alignment = .center
        keyLabel.textColor = .white

        let keyContainer = NSBox()
        keyContainer.boxType = .custom
        keyContainer.cornerRadius = 6
        keyContainer.borderWidth = 1
        keyContainer.borderColor = NSColor.white.withAlphaComponent(0.28)
        keyContainer.fillColor = NSColor.white.withAlphaComponent(0.08)
        keyContainer.contentViewMargins = NSSize(width: 12, height: 6)
        keyContainer.contentView = keyLabel
        keyContainer.translatesAutoresizingMaskIntoConstraints = false
        keyContainer.widthAnchor.constraint(greaterThanOrEqualToConstant: 48).isActive = true

        let titleLabel = NSTextField(labelWithString: layout.name)
        titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        titleLabel.textColor = .white

        let descriptionLabel = NSTextField(labelWithString: layout.summary)
        descriptionLabel.font = NSFont.systemFont(ofSize: 11)
        descriptionLabel.textColor = NSColor.white.withAlphaComponent(0.72)

        let textStack = NSStackView(views: [titleLabel, descriptionLabel])
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 2

        let row = NSStackView(views: [keyContainer, textStack])
        row.orientation = .horizontal
        row.alignment = .top
        row.spacing = 16
        return row
    }

    @objc private func openLayoutManager() {
        onManageLayouts()
    }
}

private final class LayoutChooserKeyHandlingView: NSView {
    var layouts: [CustomLayout] = []
    var onAction: ((CustomLayout) -> Void)?
    var onCancel: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onCancel?()
            return
        }

        let modifiers = chooserRelevantModifierFlags(from: event.modifierFlags).rawValue
        if let matchedLayout = layouts.first(where: {
            $0.triggerKeyCode == event.keyCode && $0.triggerModifiers == modifiers
        }) {
            onAction?(matchedLayout)
            return
        }

        NSSound.beep()
    }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }
}

private final class LayoutManagerWindowController: NSWindowController, NSWindowDelegate {
    private let layoutManagerViewController = LayoutManagerViewController()
    private let onClose: () -> Void

    init(onClose: @escaping () -> Void) {
        self.onClose = onClose

        let window = NSWindow(contentViewController: layoutManagerViewController)
        window.title = "Layout Manager"
        let defaultSize = NSSize(width: 760, height: 520)
        window.setContentSize(defaultSize)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.contentMinSize = defaultSize
        window.contentMaxSize = NSSize(width: defaultSize.width, height: 2000)
        window.center()

        super.init(window: window)
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func refreshLayouts() {
        layoutManagerViewController.refreshLayouts()
    }

    func windowWillClose(_ notification: Notification) {
        onClose()
    }
}

final class LayoutManagerViewController: NSViewController {
    private static let layoutRowPasteboardType = NSPasteboard.PasteboardType("org.kakera.Mador.layout-row")

    private enum Column: String, CaseIterable {
        case triggerKey = "Key"
        case name = "Name"
        case position = "Position"
        case size = "Size"
    }

    private var selectedLayoutId: UUID?

    @IBOutlet private weak var addButton: NSButton!
    @IBOutlet private weak var removeButton: NSButton!
    @IBOutlet private weak var tableView: NSTableView!
    @IBOutlet private weak var nameField: NSTextField!
    @IBOutlet private weak var keyField: KeyCaptureField!
    @IBOutlet private weak var xAnchorButton: NSPopUpButton!
    @IBOutlet private weak var xPercentField: NSTextField!
    @IBOutlet private weak var yAnchorButton: NSPopUpButton!
    @IBOutlet private weak var yPercentField: NSTextField!
    @IBOutlet private weak var widthPercentField: NSTextField!
    @IBOutlet private weak var heightPercentField: NSTextField!
    @IBOutlet private weak var skipSmallScreenButton: NSButton!

    init() {
        super.init(nibName: NSNib.Name("LayoutManagerViewController"), bundle: .main)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.appearance = NSAppearance(named: .aqua)
        configureInterface()
        refreshLayouts()
    }

    func refreshLayouts() {
        let layouts = Defaults.customLayouts.value
        if selectedLayoutId == nil || !layouts.contains(where: { $0.id == selectedLayoutId }) {
            selectedLayoutId = layouts.first?.id
        }
        tableView.reloadData()
        syncSelection()
        populateEditor()
    }

    private func configureInterface() {
        addButton.target = self
        addButton.action = #selector(addLayout)
        addButton.bezelStyle = .rounded

        removeButton.target = self
        removeButton.action = #selector(removeSelectedLayout)
        removeButton.bezelStyle = .rounded

        applyEditorSizing()
        applyEditorAppearance()

        tableView.usesAlternatingRowBackgroundColors = true
        tableView.rowHeight = 28
        tableView.delegate = self
        tableView.dataSource = self
        tableView.allowsEmptySelection = false
        tableView.allowsMultipleSelection = false
        tableView.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        tableView.registerForDraggedTypes([Self.layoutRowPasteboardType])
        tableView.setDraggingSourceOperationMask(.move, forLocal: true)

        [nameField, xPercentField, yPercentField, widthPercentField, heightPercentField].forEach {
            $0.target = self
            $0.action = #selector(editorChanged(_:))
        }
        skipSmallScreenButton.target = self
        skipSmallScreenButton.action = #selector(editorChanged(_:))
        keyField.onKeyCapture = { [weak self] _, _ in
            self?.editorChanged(nil)
        }

        if xAnchorButton.itemArray.isEmpty {
            LayoutHorizontalAnchor.allCases.forEach { xAnchorButton.addItem(withTitle: $0.title) }
        }
        if yAnchorButton.itemArray.isEmpty {
            LayoutVerticalAnchor.allCases.forEach { yAnchorButton.addItem(withTitle: $0.title) }
        }
        xAnchorButton.target = self
        xAnchorButton.action = #selector(editorChanged(_:))
        yAnchorButton.target = self
        yAnchorButton.action = #selector(editorChanged(_:))
    }

    private func applyEditorSizing() {
        let widths: [(NSView, CGFloat)] = [
            (nameField, 220),
            (keyField, 110),
            (xAnchorButton, 96),
            (xPercentField, 72),
            (yAnchorButton, 96),
            (yPercentField, 72),
            (widthPercentField, 72),
            (heightPercentField, 72)
        ]

        for (view, width) in widths {
            if let constraint = view.constraints.first(where: {
                $0.firstAttribute == .width && $0.relation == .equal && $0.firstItem as? NSView === view
            }) {
                constraint.constant = width
            } else {
                view.widthAnchor.constraint(equalToConstant: width).isActive = true
            }
        }
    }

    private func applyEditorAppearance() {
        let editableFields = [nameField, keyField, xPercentField, yPercentField, widthPercentField, heightPercentField].compactMap { $0 }
        editableFields.forEach {
            $0.isBezeled = true
            $0.isBordered = true
            $0.drawsBackground = true
            $0.backgroundColor = .textBackgroundColor
            $0.textColor = .textColor
            $0.focusRingType = .default
        }

        [xAnchorButton, yAnchorButton].compactMap { $0 }.forEach {
            $0.appearance = NSAppearance(named: .aqua)
        }
    }

    private func updateLayout(_ updatedLayout: CustomLayout) {
        var layouts = Defaults.customLayouts.value
        guard let index = layouts.firstIndex(where: { $0.id == updatedLayout.id }) else { return }
        layouts[index] = updatedLayout
        Defaults.customLayouts.value = layouts
        Notification.Name.changeDefaults.post()
        tableView.reloadData(forRowIndexes: IndexSet(integer: index), columnIndexes: IndexSet(integersIn: 0..<tableView.numberOfColumns))
    }

    @objc private func addLayout() {
        var layouts = Defaults.customLayouts.value
        let layout = CustomLayout(
            name: "New Layout",
            triggerKeyCode: nil,
            triggerModifiers: 0,
            skipSmallScreen: false,
            xAnchor: .left,
            xPercent: 0,
            yAnchor: .top,
            yPercent: 0,
            widthPercent: 50,
            heightPercent: 50
        )
        layouts.append(layout)
        Defaults.customLayouts.value = layouts
        selectedLayoutId = layout.id
        Notification.Name.changeDefaults.post()
        refreshLayouts()

        guard let row = Defaults.customLayouts.value.firstIndex(where: { $0.id == layout.id }) else { return }
        tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        tableView.scrollRowToVisible(row)
        populateEditor()
        view.window?.makeFirstResponder(nameField)
        nameField.currentEditor()?.selectedRange = NSRange(location: 0, length: nameField.stringValue.count)
    }

    @objc private func removeSelectedLayout() {
        guard let layout = selectedLayout else { return }
        var layouts = Defaults.customLayouts.value
        layouts.removeAll(where: { $0.id == layout.id })
        Defaults.customLayouts.value = layouts
        selectedLayoutId = Defaults.customLayouts.value.first?.id
        Notification.Name.changeDefaults.post()
        refreshLayouts()
    }

    @objc private func editorChanged(_ sender: Any?) {
        guard var layout = selectedLayout else { return }

        layout.name = nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Layout"
            : nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        layout.triggerKeyCode = keyField.capturedKeyCode
        layout.triggerModifiers = keyField.capturedModifierFlagsRawValue
        layout.skipSmallScreen = skipSmallScreenButton.state == .on
        layout.xAnchor = LayoutHorizontalAnchor.allCases[xAnchorButton.indexOfSelectedItem]
        layout.xPercent = normalizedPercent(xPercentField.doubleValue)
        layout.yAnchor = LayoutVerticalAnchor.allCases[yAnchorButton.indexOfSelectedItem]
        layout.yPercent = normalizedPercent(yPercentField.doubleValue)
        layout.widthPercent = normalizedPercent(widthPercentField.doubleValue, minimum: 1)
        layout.heightPercent = normalizedPercent(heightPercentField.doubleValue, minimum: 1)

        updateLayout(layout)
        populateEditor()
    }

    private func syncSelection() {
        guard let selectedLayoutId,
              let row = Defaults.customLayouts.value.firstIndex(where: { $0.id == selectedLayoutId }) else {
            tableView.deselectAll(nil)
            return
        }
        tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        tableView.scrollRowToVisible(row)
    }

    private var selectedLayout: CustomLayout? {
        Defaults.customLayouts.value.first(where: { $0.id == selectedLayoutId })
    }

    private func populateEditor() {
        guard let layout = selectedLayout else {
            [nameField, xPercentField, yPercentField, widthPercentField, heightPercentField].forEach {
                $0.stringValue = ""
                $0.isEnabled = false
            }
            keyField.setShortcut(keyCode: nil, modifiersRawValue: 0)
            keyField.isEnabled = false
            skipSmallScreenButton.state = .off
            skipSmallScreenButton.isEnabled = false
            [xAnchorButton, yAnchorButton].forEach { $0.isEnabled = false }
            removeButton.isEnabled = false
            return
        }

        [nameField, xPercentField, yPercentField, widthPercentField, heightPercentField].forEach {
            $0.isEnabled = true
        }
        keyField.isEnabled = true
        skipSmallScreenButton.isEnabled = true
        [xAnchorButton, yAnchorButton].forEach { $0.isEnabled = true }
        removeButton.isEnabled = true

        nameField.stringValue = layout.name
        keyField.setShortcut(keyCode: layout.triggerKeyCode, modifiersRawValue: layout.triggerModifiers)
        skipSmallScreenButton.state = layout.skipSmallScreen ? .on : .off
        xAnchorButton.selectItem(withTitle: layout.xAnchor.title)
        xPercentField.stringValue = percentString(layout.xPercent)
        yAnchorButton.selectItem(withTitle: layout.yAnchor.title)
        yPercentField.stringValue = percentString(layout.yPercent)
        widthPercentField.stringValue = percentString(layout.widthPercent)
        heightPercentField.stringValue = percentString(layout.heightPercent)
    }

    private func percentString(_ value: Double) -> String {
        String(format: "%.1f", value)
    }

    private func normalizedPercent(_ value: Double, minimum: Double = 0) -> Double {
        min(100, max(minimum, value))
    }
}

extension LayoutManagerViewController: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int {
        Defaults.customLayouts.value.count
    }

    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> (any NSPasteboardWriting)? {
        guard row >= 0, row < Defaults.customLayouts.value.count else { return nil }

        let item = NSPasteboardItem()
        item.setString(String(row), forType: Self.layoutRowPasteboardType)
        return item
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        let row = tableView.selectedRow
        guard row >= 0, row < Defaults.customLayouts.value.count else { return }
        selectedLayoutId = Defaults.customLayouts.value[row].id
        populateEditor()
    }

    func tableView(_ tableView: NSTableView, validateDrop info: NSDraggingInfo, proposedRow row: Int,
                   proposedDropOperation dropOperation: NSTableView.DropOperation) -> NSDragOperation {
        guard dropOperation == .above,
              info.draggingSource as? NSTableView === tableView else { return [] }

        return .move
    }

    func tableView(_ tableView: NSTableView, acceptDrop info: NSDraggingInfo, row: Int,
                   dropOperation: NSTableView.DropOperation) -> Bool {
        guard dropOperation == .above,
              let sourceRowString = info.draggingPasteboard.string(forType: Self.layoutRowPasteboardType),
              let sourceRow = Int(sourceRowString)
        else {
            return false
        }

        var layouts = Defaults.customLayouts.value
        guard sourceRow >= 0, sourceRow < layouts.count else { return false }

        let movedLayout = layouts.remove(at: sourceRow)
        let destinationRow = min(max(row - (sourceRow < row ? 1 : 0), 0), layouts.count)
        layouts.insert(movedLayout, at: destinationRow)

        Defaults.customLayouts.value = layouts
        selectedLayoutId = movedLayout.id
        Notification.Name.changeDefaults.post()
        refreshLayouts()
        tableView.selectRowIndexes(IndexSet(integer: destinationRow), byExtendingSelection: false)
        tableView.scrollRowToVisible(destinationRow)
        populateEditor()
        return true
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < Defaults.customLayouts.value.count,
              let tableColumn else { return nil }

        let layout = Defaults.customLayouts.value[row]
        let column = Column(rawValue: tableColumn.identifier.rawValue)
        let text: String

        switch column {
        case .triggerKey:
            text = displayString(for: layout.triggerKeyCode, modifiersRawValue: layout.triggerModifiers)
        case .name:
            text = layout.name
        case .position:
            text = "x \(layout.xAnchor.title) \(layout.xPercent)% / y \(layout.yAnchor.title) \(layout.yPercent)%"
        case .size:
            text = "w \(layout.widthPercent)% / h \(layout.heightPercent)%"
        case .none:
            text = ""
        }

        let identifier = NSUserInterfaceItemIdentifier("Cell-\(tableColumn.identifier.rawValue)")
        let cellView = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView ?? {
            let cell = NSTableCellView()
            let label = NSTextField(labelWithString: "")
            label.translatesAutoresizingMaskIntoConstraints = false
            label.lineBreakMode = .byTruncatingTail
            cell.addSubview(label)
            cell.textField = label
            cell.identifier = identifier
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 6),
                label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -6),
                label.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
            ])
            return cell
        }()

        cellView.textField?.stringValue = text
        return cellView
    }
}

private extension CustomLayout {
    var summary: String {
        "x: \(xAnchor.title) \(xPercent)%  y: \(yAnchor.title) \(yPercent)%  w: \(widthPercent)%  h: \(heightPercent)%"
    }

    func frame(in visibleFrame: CGRect) -> CGRect {
        let width = floor(visibleFrame.width * CGFloat(widthPercent / 100))
        let height = floor(visibleFrame.height * CGFloat(heightPercent / 100))
        let xOffset = floor(visibleFrame.width * CGFloat(xPercent / 100))
        let yOffset = floor(visibleFrame.height * CGFloat(yPercent / 100))

        let originX: CGFloat
        switch xAnchor {
        case .left:
            originX = visibleFrame.minX + xOffset
        case .right:
            originX = visibleFrame.maxX - xOffset - width
        }

        let originY: CGFloat
        switch yAnchor {
        case .bottom:
            originY = visibleFrame.minY + yOffset
        case .top:
            originY = visibleFrame.maxY - yOffset - height
        }

        return CGRect(x: originX, y: originY, width: width, height: height)
    }
}

final class KeyCaptureField: NSTextField {
    var onKeyCapture: ((UInt16?, UInt) -> Void)?
    private(set) var capturedKeyCode: UInt16?
    private(set) var capturedModifierFlagsRawValue: UInt = 0

    override var acceptsFirstResponder: Bool { isEnabled }

    override func awakeFromNib() {
        super.awakeFromNib()
        isEditable = false
        isSelectable = false
        focusRingType = .default
        updateDisplay()
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
    }

    override func becomeFirstResponder() -> Bool {
        let didBecome = super.becomeFirstResponder()
        if didBecome {
            currentEditor()?.selectedRange = NSRange(location: 0, length: stringValue.count)
        }
        return didBecome
    }

    override func keyDown(with event: NSEvent) {
        let modifiers = chooserRelevantModifierFlags(from: event.modifierFlags)

        switch event.keyCode {
        case 53 where modifiers.isEmpty:
            window?.makeFirstResponder(nil)
        case 51 where modifiers.isEmpty, 117 where modifiers.isEmpty:
            capturedKeyCode = nil
            capturedModifierFlagsRawValue = 0
            updateDisplay()
            onKeyCapture?(nil, 0)
        default:
            capturedKeyCode = event.keyCode
            capturedModifierFlagsRawValue = modifiers.rawValue
            updateDisplay()
            onKeyCapture?(capturedKeyCode, capturedModifierFlagsRawValue)
        }
    }

    func setShortcut(keyCode: UInt16?, modifiersRawValue: UInt) {
        capturedKeyCode = keyCode
        capturedModifierFlagsRawValue = keyCode == nil ? 0 : modifiersRawValue
        updateDisplay()
    }

    private func updateDisplay() {
        stringValue = displayString(for: capturedKeyCode, modifiersRawValue: capturedModifierFlagsRawValue)
    }
}

private func displayString(for keyCode: UInt16?, modifiersRawValue: UInt) -> String {
    guard let keyCode else { return "" }

    let modifiers = NSEvent.ModifierFlags(rawValue: modifiersRawValue)
    let modifierPrefix = modifierDisplayString(for: modifiers)

    return modifierPrefix + keyDisplayString(for: keyCode)
}

private func keyDisplayString(for keyCode: UInt16) -> String {
    switch keyCode {
    case 0: return "A"
    case 1: return "S"
    case 2: return "D"
    case 3: return "F"
    case 4: return "H"
    case 5: return "G"
    case 6: return "Z"
    case 7: return "X"
    case 8: return "C"
    case 9: return "V"
    case 11: return "B"
    case 12: return "Q"
    case 13: return "W"
    case 14: return "E"
    case 15: return "R"
    case 16: return "Y"
    case 17: return "T"
    case 18: return "1"
    case 19: return "2"
    case 20: return "3"
    case 21: return "4"
    case 22: return "6"
    case 23: return "5"
    case 24: return "="
    case 25: return "9"
    case 26: return "7"
    case 27: return "-"
    case 28: return "8"
    case 29: return "0"
    case 30: return "]"
    case 31: return "O"
    case 32: return "U"
    case 33: return "["
    case 34: return "I"
    case 35: return "P"
    case 37: return "L"
    case 38: return "J"
    case 39: return "'"
    case 40: return "K"
    case 41: return ";"
    case 42: return "\\"
    case 43: return ","
    case 44: return "/"
    case 45: return "N"
    case 46: return "M"
    case 47: return "."
    case 48: return "⇥"
    case 49: return "Space"
    case 36: return "↩"
    case 51: return "⌫"
    case 53: return "⎋"
    case 76: return "⌅"
    case 96: return "F5"
    case 97: return "F6"
    case 98: return "F7"
    case 99: return "F3"
    case 100: return "F8"
    case 101: return "F9"
    case 103: return "F11"
    case 105: return "F13"
    case 106: return "F16"
    case 107: return "F14"
    case 109: return "F10"
    case 111: return "F12"
    case 113: return "F15"
    case 114: return "Help"
    case 115: return "↖"
    case 116: return "⇞"
    case 117: return "⌦"
    case 118: return "F4"
    case 119: return "↘"
    case 120: return "F2"
    case 121: return "⇟"
    case 122: return "F1"
    case 123: return "←"
    case 124: return "→"
    case 125: return "↓"
    case 126: return "↑"
    default: return "Key \(keyCode)"
    }
}

private func modifierDisplayString(for flags: NSEvent.ModifierFlags) -> String {
    let relevantFlags = chooserRelevantModifierFlags(from: flags)
    var components: [String] = []

    if relevantFlags.contains(.control) {
        components.append("⌃")
    }
    if relevantFlags.contains(.option) {
        components.append("⌥")
    }
    if relevantFlags.contains(.shift) {
        components.append("⇧")
    }
    if relevantFlags.contains(.command) {
        components.append("⌘")
    }

    return components.joined()
}

private func chooserRelevantModifierFlags(from flags: NSEvent.ModifierFlags) -> NSEvent.ModifierFlags {
    flags.intersection([.command, .option, .control, .shift])
}
