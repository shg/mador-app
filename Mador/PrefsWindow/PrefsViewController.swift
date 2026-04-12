//
//  PrefsViewController.swift
//  Mador
//
//  Created by Ryan Hanson on 6/18/19.
//  Copyright © 2019 Ryan Hanson. All rights reserved.
//

import Cocoa
import MASShortcut
import ServiceManagement

class PrefsViewController: NSViewController {
    
    var actionsToViews = [WindowAction: MASShortcutView]()
    
    @IBOutlet weak var leftHalfShortcutView: MASShortcutView!
    @IBOutlet weak var rightHalfShortcutView: MASShortcutView!
    @IBOutlet weak var centerHalfShortcutView: MASShortcutView!
    @IBOutlet weak var topHalfShortcutView: MASShortcutView!
    @IBOutlet weak var bottomHalfShortcutView: MASShortcutView!
    
    @IBOutlet weak var topLeftShortcutView: MASShortcutView!
    @IBOutlet weak var topRightShortcutView: MASShortcutView!
    @IBOutlet weak var bottomLeftShortcutView: MASShortcutView!
    @IBOutlet weak var bottomRightShortcutView: MASShortcutView!
    
    @IBOutlet weak var nextDisplayShortcutView: MASShortcutView!
    @IBOutlet weak var previousDisplayShortcutView: MASShortcutView!
    
    @IBOutlet weak var makeLargerShortcutView: MASShortcutView!
    @IBOutlet weak var makeSmallerShortcutView: MASShortcutView!
    
    @IBOutlet weak var maximizeShortcutView: MASShortcutView!
    @IBOutlet weak var almostMaximizeShortcutView: MASShortcutView!
    @IBOutlet weak var maximizeHeightShortcutView: MASShortcutView!
    @IBOutlet weak var centerShortcutView: MASShortcutView!
    @IBOutlet weak var restoreShortcutView: MASShortcutView!
    
    // Additional
    @IBOutlet weak var firstThirdShortcutView: MASShortcutView!
    @IBOutlet weak var firstTwoThirdsShortcutView: MASShortcutView!
    @IBOutlet weak var centerThirdShortcutView: MASShortcutView!
    @IBOutlet weak var centerTwoThirdsShortcutView: MASShortcutView!
    @IBOutlet weak var lastTwoThirdsShortcutView: MASShortcutView!
    @IBOutlet weak var lastThirdShortcutView: MASShortcutView!
    
    @IBOutlet weak var moveLeftShortcutView: MASShortcutView!
    @IBOutlet weak var moveRightShortcutView: MASShortcutView!
    @IBOutlet weak var moveUpShortcutView: MASShortcutView!
    @IBOutlet weak var moveDownShortcutView: MASShortcutView!
    
    @IBOutlet weak var firstFourthShortcutView: MASShortcutView!
    @IBOutlet weak var secondFourthShortcutView: MASShortcutView!
    @IBOutlet weak var thirdFourthShortcutView: MASShortcutView!
    @IBOutlet weak var lastFourthShortcutView: MASShortcutView!
    @IBOutlet weak var firstThreeFourthsShortcutView: MASShortcutView!
    @IBOutlet weak var centerThreeFourthsShortcutView: MASShortcutView!
    @IBOutlet weak var lastThreeFourthsShortcutView: MASShortcutView!
    
    @IBOutlet weak var topLeftSixthShortcutView: MASShortcutView!
    @IBOutlet weak var topCenterSixthShortcutView: MASShortcutView!
    @IBOutlet weak var topRightSixthShortcutView: MASShortcutView!
    @IBOutlet weak var bottomLeftSixthShortcutView: MASShortcutView!
    @IBOutlet weak var bottomCenterSixthShortcutView: MASShortcutView!
    @IBOutlet weak var bottomRightSixthShortcutView: MASShortcutView!

    
    @IBOutlet weak var showMoreButton: NSButton!
    @IBOutlet weak var additionalShortcutsStackView: NSStackView!
    
    // Settings
    override func awakeFromNib() {
        
        actionsToViews = [
            .leftHalf: leftHalfShortcutView,
            .rightHalf: rightHalfShortcutView,
            .centerHalf: centerHalfShortcutView,
            .topHalf: topHalfShortcutView,
            .bottomHalf: bottomHalfShortcutView,
            .topLeft: topLeftShortcutView,
            .topRight: topRightShortcutView,
            .bottomLeft: bottomLeftShortcutView,
            .bottomRight: bottomRightShortcutView,
            .nextDisplay: nextDisplayShortcutView,
            .previousDisplay: previousDisplayShortcutView,
            .maximize: maximizeShortcutView,
            .almostMaximize: almostMaximizeShortcutView,
            .maximizeHeight: maximizeHeightShortcutView,
            .center: centerShortcutView,
            .larger: makeLargerShortcutView,
            .smaller: makeSmallerShortcutView,
            .restore: restoreShortcutView,
            .firstThird: firstThirdShortcutView,
            .firstTwoThirds: firstTwoThirdsShortcutView,
            .centerThird: centerThirdShortcutView,
            .centerTwoThirds: centerTwoThirdsShortcutView,
            .lastTwoThirds: lastTwoThirdsShortcutView,
            .lastThird: lastThirdShortcutView,
            .moveLeft: moveLeftShortcutView,
            .moveRight: moveRightShortcutView,
            .moveUp: moveUpShortcutView,
            .moveDown: moveDownShortcutView,
            .firstFourth: firstFourthShortcutView,
            .secondFourth: secondFourthShortcutView,
            .thirdFourth: thirdFourthShortcutView,
            .lastFourth: lastFourthShortcutView,
            .firstThreeFourths: firstThreeFourthsShortcutView,
            .centerThreeFourths: centerThreeFourthsShortcutView,
            .lastThreeFourths: lastThreeFourthsShortcutView,
            .topLeftSixth: topLeftSixthShortcutView,
            .topCenterSixth: topCenterSixthShortcutView,
            .topRightSixth: topRightSixthShortcutView,
            .bottomLeftSixth: bottomLeftSixthShortcutView,
            .bottomCenterSixth: bottomCenterSixthShortcutView,
            .bottomRightSixth: bottomRightSixthShortcutView
        ]
        
        for (action, view) in actionsToViews {
            view.setAssociatedUserDefaultsKey(action.name, withTransformerName: MASDictionaryTransformerName)
        }
        
        if Defaults.allowAnyShortcut.enabled {
            let passThroughValidator = PassthroughShortcutValidator()
            actionsToViews.values.forEach { $0.shortcutValidator = passThroughValidator }
        }
        
        subscribeToAllowAnyShortcutToggle()
        
        additionalShortcutsStackView.isHidden = true
    }
    
    @IBAction func toggleShowMore(_ sender: NSButton) {
        additionalShortcutsStackView.isHidden = !additionalShortcutsStackView.isHidden
        showMoreButton.title = additionalShortcutsStackView.isHidden
            ? "▶︎ ⋯" : "▼"
    }
    
    private func subscribeToAllowAnyShortcutToggle() {
        Notification.Name.allowAnyShortcut.onPost { notification in
            guard let enabled = notification.object as? Bool else { return }
            let validator = enabled ? PassthroughShortcutValidator() : MASShortcutValidator()
            self.actionsToViews.values.forEach { $0.shortcutValidator = validator }
        }
    }
    
}

class PassthroughShortcutValidator: MASShortcutValidator {
    
    override func isShortcutValid(_ shortcut: MASShortcut!) -> Bool {
        return true
    }
    
    override func isShortcutAlreadyTaken(bySystem shortcut: MASShortcut!, explanation: AutoreleasingUnsafeMutablePointer<NSString?>!) -> Bool {
        return false
    }
    
    override func isShortcut(_ shortcut: MASShortcut!, alreadyTakenIn menu: NSMenu!, explanation: AutoreleasingUnsafeMutablePointer<NSString?>!) -> Bool {
        return false
    }
    
}

final class BasicPreferencesWindowController: NSWindowController {
    init() {
        let viewController = BasicPreferencesViewController()
        let window = NSWindow(contentViewController: viewController)
        window.title = "Mador"
        window.setContentSize(NSSize(width: 480, height: 240))
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.center()
        super.init(window: window)
        shouldCascadeWindows = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

final class BasicPreferencesViewController: NSViewController {
    private let prefixShortcutView = MASShortcutView(frame: NSRect(x: 0, y: 0, width: 180, height: 19))
    private let leftKeyButton = KeyCaptureButton(defaults: Defaults.layoutChooserLeftKey)
    private let rightKeyButton = KeyCaptureButton(defaults: Defaults.layoutChooserRightKey)

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 480, height: 240))
        buildInterface()
        configureControls()
    }

    private func buildInterface() {
        let mainStack = NSStackView()
        mainStack.orientation = .vertical
        mainStack.alignment = .leading
        mainStack.spacing = 14
        mainStack.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = NSTextField(labelWithString: "Keyboard Shortcuts")
        titleLabel.font = NSFont.boldSystemFont(ofSize: 15)

        let descriptionLabel = NSTextField(wrappingLabelWithString: "Press the prefix shortcut to open the chooser window. Then press the key assigned to Left Half or Right Half.")
        descriptionLabel.textColor = .secondaryLabelColor
        descriptionLabel.maximumNumberOfLines = 0

        let prefixRow = makePrefixRow()
        let leftRow = makeKeyRow(title: "Left Half", image: WindowAction.leftHalf.image, button: leftKeyButton)
        let rightRow = makeKeyRow(title: "Right Half", image: WindowAction.rightHalf.image, button: rightKeyButton)

        let restoreButton = NSButton(title: "Reset Controls to Defaults", target: self, action: #selector(resetShortcuts))
        restoreButton.bezelStyle = .rounded

        mainStack.addArrangedSubview(titleLabel)
        mainStack.addArrangedSubview(descriptionLabel)
        mainStack.addArrangedSubview(prefixRow)
        mainStack.addArrangedSubview(leftRow)
        mainStack.addArrangedSubview(rightRow)
        mainStack.addArrangedSubview(restoreButton)

        view.addSubview(mainStack)

        NSLayoutConstraint.activate([
            mainStack.topAnchor.constraint(equalTo: view.topAnchor, constant: 20),
            mainStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            mainStack.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -20)
        ])
    }

    private func configureControls() {
        prefixShortcutView.setAssociatedUserDefaultsKey(ShortcutManager.prefixShortcutDefaultsKey, withTransformerName: MASDictionaryTransformerName)

        if Defaults.allowAnyShortcut.enabled {
            let validator = PassthroughShortcutValidator()
            prefixShortcutView.shortcutValidator = validator
        }

        Notification.Name.allowAnyShortcut.onPost { [weak self] notification in
            guard let enabled = notification.object as? Bool else { return }
            let validator: MASShortcutValidator = enabled ? PassthroughShortcutValidator() : MASShortcutValidator()
            self?.prefixShortcutView.shortcutValidator = validator
        }
    }

    private func makePrefixRow() -> NSStackView {
        let titleLabel = NSTextField(labelWithString: "Chooser Shortcut")
        titleLabel.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        titleLabel.setContentHuggingPriority(.defaultHigh, for: .horizontal)

        let row = NSStackView(views: [titleLabel, prefixShortcutView])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 16
        return row
    }

    private func makeKeyRow(title: String, image: NSImage, button: NSButton) -> NSStackView {
        let imageView = NSImageView(frame: NSRect(x: 0, y: 0, width: 30, height: 20))
        imageView.image = image
        imageView.image?.size = NSSize(width: 30, height: 20)

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)

        let titleStack = NSStackView(views: [titleLabel, imageView])
        titleStack.orientation = .horizontal
        titleStack.alignment = .centerY
        titleStack.spacing = 10
        titleStack.setHuggingPriority(.defaultHigh, for: .horizontal)

        let row = NSStackView(views: [titleStack, button])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 16
        return row
    }

    @objc private func resetShortcuts() {
        UserDefaults.standard.removeObject(forKey: ShortcutManager.prefixShortcutDefaultsKey)
        Defaults.layoutChooserLeftKey.value = "["
        Defaults.layoutChooserRightKey.value = "]"
        leftKeyButton.refreshTitle()
        rightKeyButton.refreshTitle()
        Notification.Name.changeDefaults.post()
    }
}

private final class KeyCaptureButton: NSButton {
    private let defaults: StringDefault
    private var isCapturing = false
    private var previousTitle = ""

    init(defaults: StringDefault) {
        self.defaults = defaults
        super.init(frame: NSRect(x: 0, y: 0, width: 80, height: 28))
        bezelStyle = .rounded
        target = self
        action = #selector(beginCapture)
        refreshTitle()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool { true }

    func refreshTitle() {
        title = defaults.value ?? ""
    }

    @objc private func beginCapture() {
        guard let window else { return }
        previousTitle = title
        isCapturing = true
        title = "Type Key"
        window.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        guard isCapturing else {
            super.keyDown(with: event)
            return
        }

        if event.keyCode == 53 {
            cancelCapture()
            return
        }

        guard let input = event.characters, input.count == 1 else {
            NSSound.beep()
            return
        }

        defaults.value = input
        isCapturing = false
        title = input
        Notification.Name.changeDefaults.post()
    }

    override func resignFirstResponder() -> Bool {
        if isCapturing {
            cancelCapture()
        }
        return super.resignFirstResponder()
    }

    private func cancelCapture() {
        isCapturing = false
        title = previousTitle
    }
}
