//
//  MadorStatusItem.swift
//  Mador
//
//  Created by Ryan Hanson on 6/11/19.
//  Copyright © 2019 Ryan Hanson. All rights reserved.
//

import Cocoa

class MadorStatusItem: NSObject {
    static let instance = MadorStatusItem()
    
    private var nsStatusItem: NSStatusItem?
    private var added: Bool = false
    public var primaryAction: (() -> Void)?
    public var statusMenu: NSMenu? {
        didSet {
            nsStatusItem?.menu = nil
        }
    }
    private override init() {
        super.init()
    }
    
    public func refreshVisibility() {
        if Defaults.hideMenuBarIcon.enabled {
            remove()
        } else {
            add()
        }
    }
    
    public func openMenu() {
        if !added {
            add()
        }
        guard let nsStatusItem, let statusMenu else { return }
        nsStatusItem.menu = statusMenu
        nsStatusItem.button?.performClick(self)
        DispatchQueue.main.async {
            nsStatusItem.menu = nil
        }
    }
    
    private func add() {
        if added, nsStatusItem != nil {
            return
        }
        added = true
        nsStatusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        nsStatusItem?.menu = nil
        nsStatusItem?.button?.image = NSImage(named: "StatusTemplate")
        if nsStatusItem?.button?.image == nil {
            nsStatusItem?.button?.title = "M"
        }
        nsStatusItem?.button?.target = self
        nsStatusItem?.button?.action = #selector(handleClick(_:))
        nsStatusItem?.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        nsStatusItem?.isVisible = true
    }
    
    private func remove() {
        added = false
        guard let nsStatusItem = nsStatusItem else { return }
        NSStatusBar.system.removeStatusItem(nsStatusItem)
        self.nsStatusItem = nil
    }

    @objc private func handleClick(_ sender: NSStatusBarButton) {
        let eventType = NSApp.currentEvent?.type
        let modifierFlags = NSApp.currentEvent?.modifierFlags ?? []
        if modifierFlags.contains(.option) || eventType == .rightMouseUp {
            openMenu()
            return
        }
        primaryAction?()
    }
    
}
