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
    private var layoutManagerWindowController: LayoutManagerWindowController?
    private var pendingExecutionTarget: PendingExecutionTarget?
    private var isTransitioningFromChooserToLayoutManager = false
    
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

    private func showLayoutChooser(captureTarget: Bool) {
        if captureTarget {
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
        }

        if chooserWindowController == nil {
            chooserWindowController = LayoutChooserWindowController(onAction: { layout in
                self.execute(layout: layout)
            }, onManageLayouts: { [weak self] in
                self?.openLayoutManager()
            }, onClose: { [weak self] in
                self?.handleChooserClose()
            })
        }

        NSApp.activate(ignoringOtherApps: true)
        chooserWindowController?.showWindow(self)
        chooserWindowController?.refreshBindings()
        chooserWindowController?.window?.center()
        chooserWindowController?.window?.makeKeyAndOrderFront(self)
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
        guard let pendingExecutionTarget else {
            NSSound.beep()
            return
        }

        guard let screen = ScreenDetection().detectScreens(using: pendingExecutionTarget.windowElement)?.currentScreen else {
            NSSound.beep()
            return
        }

        let visibleFrame = screen.visibleFrame
        let currentFrame = pendingExecutionTarget.windowElement.frame
        let targetFrame = layout.frame(in: visibleFrame).screenFlipped

        AppDelegate.windowHistory.restoreRects[pendingExecutionTarget.windowId] = currentFrame
        AppDelegate.windowHistory.lastRectangleActions.removeValue(forKey: pendingExecutionTarget.windowId)
        pendingExecutionTarget.windowElement.setFrame(targetFrame)
    }

    private func restorePendingExecutionTarget() {
        guard let pendingExecutionTarget else { return }

        pendingExecutionTarget.application.activate(options: .activateIgnoringOtherApps)
        pendingExecutionTarget.windowElement.bringToFront(force: true)
    }

    private func handleChooserClose() {
        chooserWindowController = nil

        guard !isTransitioningFromChooserToLayoutManager else { return }

        restorePendingExecutionTarget()
        pendingExecutionTarget = nil
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

    init(onAction: @escaping (CustomLayout) -> Void, onManageLayouts: @escaping () -> Void, onClose: @escaping () -> Void) {
        chooserViewController = LayoutChooserViewController(onAction: onAction, onManageLayouts: onManageLayouts)
        self.onClose = onClose

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 280),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Choose Layout"
        window.styleMask.insert(.fullSizeContentView)
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

        let visualEffect = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: 360, height: 280))
        visualEffect.translatesAutoresizingMaskIntoConstraints = false
        visualEffect.blendingMode = .behindWindow
        visualEffect.state = .active
        visualEffect.material = .dark
        visualEffect.wantsLayer = true
        visualEffect.layer?.cornerRadius = 14
        visualEffect.layer?.cornerCurve = .continuous
        visualEffect.layer?.masksToBounds = true
        window.contentView = visualEffect

        let contentView = chooserViewController.view
        contentView.translatesAutoresizingMaskIntoConstraints = false
        visualEffect.addSubview(contentView)
        NSLayoutConstraint.activate([
            contentView.topAnchor.constraint(equalTo: visualEffect.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: visualEffect.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: visualEffect.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: visualEffect.bottomAnchor)
        ])

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
        titleLabel.font = NSFont.boldSystemFont(ofSize: 16)
        titleLabel.textColor = .white

        let descriptionLabel = NSTextField(wrappingLabelWithString: "Press the assigned chooser key to place the captured window, or press Esc to cancel.")
        descriptionLabel.textColor = NSColor.white.withAlphaComponent(0.78)
        descriptionLabel.maximumNumberOfLines = 0

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

        let manageButton = NSButton(title: "Manage Layouts", target: self, action: #selector(openLayoutManager))
        manageButton.bezelStyle = .rounded

        let stack = NSStackView(views: [titleLabel, descriptionLabel, rowsContainer, manageButton])
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

        rowsContainer.heightAnchor.constraint(equalToConstant: 140).isActive = true
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
        let keyLabel = NSTextField(labelWithString: layout.triggerKey.isEmpty ? " " : layout.triggerKey)
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
        keyContainer.widthAnchor.constraint(equalToConstant: 48).isActive = true

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

        guard let input = normalizedTriggerKey(event.charactersIgnoringModifiers) else {
            NSSound.beep()
            return
        }

        if let matchedLayout = layouts.first(where: { normalizedTriggerKey($0.triggerKey) == input }) {
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
        window.title = "Manage Layouts"
        window.setContentSize(NSSize(width: 760, height: 520))
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
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

private final class LayoutManagerViewController: NSViewController {
    private enum Column: String, CaseIterable {
        case triggerKey = "Key"
        case name = "Name"
        case position = "Position"
        case size = "Size"
    }

    private let tableView = NSTableView()
    private let scrollView = NSScrollView()
    private var selectedLayoutId: UUID?

    private let nameField = NSTextField()
    private let keyField = NSTextField()
    private let xAnchorButton = NSPopUpButton()
    private let xPercentField = NSTextField()
    private let yAnchorButton = NSPopUpButton()
    private let yPercentField = NSTextField()
    private let widthPercentField = NSTextField()
    private let heightPercentField = NSTextField()
    private let removeButton = NSButton(title: "Remove Selected Layout", target: nil, action: nil)

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 760, height: 520))
        buildInterface()
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

    private func buildInterface() {
        let titleLabel = NSTextField(labelWithString: "Manage Layouts")
        titleLabel.font = NSFont.boldSystemFont(ofSize: 18)

        let descriptionLabel = NSTextField(wrappingLabelWithString: "Set each layout's chooser key and screen-relative frame. Percentages are based on the active screen's visible frame.")
        descriptionLabel.maximumNumberOfLines = 0
        descriptionLabel.textColor = .secondaryLabelColor

        let addButton = NSButton(title: "Add Layout", target: self, action: #selector(addLayout))
        addButton.bezelStyle = .rounded

        let resetButton = NSButton(title: "Reset to Defaults", target: self, action: #selector(resetLayouts))
        resetButton.bezelStyle = .rounded

        let buttonsRow = NSStackView(views: [addButton, resetButton])
        buttonsRow.orientation = .horizontal
        buttonsRow.alignment = .centerY
        buttonsRow.spacing = 10

        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = tableView
        scrollView.borderType = .bezelBorder

        tableView.headerView = NSTableHeaderView()
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.rowHeight = 28
        tableView.delegate = self
        tableView.dataSource = self
        tableView.allowsEmptySelection = false
        tableView.allowsMultipleSelection = false
        tableView.columnAutoresizingStyle = .uniformColumnAutoresizingStyle

        for column in Column.allCases {
            let tableColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(column.rawValue))
            tableColumn.title = column.rawValue
            tableView.addTableColumn(tableColumn)
        }

        removeButton.target = self
        removeButton.action = #selector(removeSelectedLayout)
        removeButton.bezelStyle = .rounded

        let detailView = buildDetailEditor()

        let stack = NSStackView(views: [titleLabel, descriptionLabel, buttonsRow, scrollView, detailView, removeButton])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 20),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            stack.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -20)
        ])

        scrollView.heightAnchor.constraint(equalToConstant: 220).isActive = true
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
            triggerKey: "",
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
    }

    @objc private func resetLayouts() {
        Defaults.customLayouts.value = CustomLayout.defaultLayouts
        selectedLayoutId = Defaults.customLayouts.value.first?.id
        Notification.Name.changeDefaults.post()
        refreshLayouts()
    }

    @objc private func removeSelectedLayout() {
        guard let layout = selectedLayout else { return }
        var layouts = Defaults.customLayouts.value
        layouts.removeAll(where: { $0.id == layout.id })
        Defaults.customLayouts.value = layouts.isEmpty ? CustomLayout.defaultLayouts : layouts
        selectedLayoutId = Defaults.customLayouts.value.first?.id
        Notification.Name.changeDefaults.post()
        refreshLayouts()
    }

    @objc private func editorChanged(_ sender: Any?) {
        guard var layout = selectedLayout else { return }

        layout.name = nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Layout"
            : nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        layout.triggerKey = normalizedTriggerKey(keyField.stringValue) ?? ""
        layout.xAnchor = LayoutHorizontalAnchor.allCases[xAnchorButton.indexOfSelectedItem]
        layout.xPercent = normalizedPercent(xPercentField.doubleValue)
        layout.yAnchor = LayoutVerticalAnchor.allCases[yAnchorButton.indexOfSelectedItem]
        layout.yPercent = normalizedPercent(yPercentField.doubleValue)
        layout.widthPercent = normalizedPercent(widthPercentField.doubleValue, minimum: 1)
        layout.heightPercent = normalizedPercent(heightPercentField.doubleValue, minimum: 1)

        updateLayout(layout)
        populateEditor()
    }

    private func buildDetailEditor() -> NSView {
        let detailTitle = NSTextField(labelWithString: "Selected Layout")
        detailTitle.font = NSFont.boldSystemFont(ofSize: 14)

        [nameField, keyField, xPercentField, yPercentField, widthPercentField, heightPercentField].forEach {
            $0.target = self
            $0.action = #selector(editorChanged(_:))
        }

        LayoutHorizontalAnchor.allCases.forEach { xAnchorButton.addItem(withTitle: $0.title) }
        LayoutVerticalAnchor.allCases.forEach { yAnchorButton.addItem(withTitle: $0.title) }
        xAnchorButton.target = self
        xAnchorButton.action = #selector(editorChanged(_:))
        yAnchorButton.target = self
        yAnchorButton.action = #selector(editorChanged(_:))

        nameField.widthAnchor.constraint(equalToConstant: 240).isActive = true
        keyField.widthAnchor.constraint(equalToConstant: 52).isActive = true
        xPercentField.widthAnchor.constraint(equalToConstant: 80).isActive = true
        yPercentField.widthAnchor.constraint(equalToConstant: 80).isActive = true
        widthPercentField.widthAnchor.constraint(equalToConstant: 80).isActive = true
        heightPercentField.widthAnchor.constraint(equalToConstant: 80).isActive = true

        let grid = NSGridView(views: [
            [NSTextField(labelWithString: "Name"), nameField, NSTextField(labelWithString: "Key"), keyField],
            [NSTextField(labelWithString: "X Anchor"), xAnchorButton, NSTextField(labelWithString: "X %"), xPercentField],
            [NSTextField(labelWithString: "Y Anchor"), yAnchorButton, NSTextField(labelWithString: "Y %"), yPercentField],
            [NSTextField(labelWithString: "Width %"), widthPercentField, NSTextField(labelWithString: "Height %"), heightPercentField]
        ])
        grid.rowSpacing = 8
        grid.columnSpacing = 10

        let stack = NSStackView(views: [detailTitle, grid])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        return stack
    }

    private func syncSelection() {
        guard let selectedLayoutId,
              let row = Defaults.customLayouts.value.firstIndex(where: { $0.id == selectedLayoutId }) else {
            tableView.deselectAll(nil)
            return
        }
        tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
    }

    private var selectedLayout: CustomLayout? {
        Defaults.customLayouts.value.first(where: { $0.id == selectedLayoutId })
    }

    private func populateEditor() {
        guard let layout = selectedLayout else {
            [nameField, keyField, xPercentField, yPercentField, widthPercentField, heightPercentField].forEach {
                $0.stringValue = ""
                $0.isEnabled = false
            }
            [xAnchorButton, yAnchorButton].forEach { $0.isEnabled = false }
            removeButton.isEnabled = false
            return
        }

        [nameField, keyField, xPercentField, yPercentField, widthPercentField, heightPercentField].forEach {
            $0.isEnabled = true
        }
        [xAnchorButton, yAnchorButton].forEach { $0.isEnabled = true }
        removeButton.isEnabled = true

        nameField.stringValue = layout.name
        keyField.stringValue = layout.triggerKey
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

    func tableViewSelectionDidChange(_ notification: Notification) {
        let row = tableView.selectedRow
        guard row >= 0, row < Defaults.customLayouts.value.count else { return }
        selectedLayoutId = Defaults.customLayouts.value[row].id
        populateEditor()
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < Defaults.customLayouts.value.count,
              let tableColumn else { return nil }

        let layout = Defaults.customLayouts.value[row]
        let column = Column(rawValue: tableColumn.identifier.rawValue)
        let text: String

        switch column {
        case .triggerKey:
            text = layout.triggerKey
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

private func normalizedTriggerKey(_ value: String?) -> String? {
    guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
          let character = trimmed.first else {
        return nil
    }
    return String(character).lowercased()
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
