//
//  NSScreen+UUID.swift
//  devNotch
//
//  Created by Alexander on 2025-11-21.
//

import AppKit
import CoreGraphics

extension NSScreen {
    /// Returns a persistent UUID for this display
    var displayUUID: String? {
        guard let number = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return nil
        }
        let displayID = CGDirectDisplayID(number.uint32Value)
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(displayID) else {
            return nil
        }
        let uuidString = CFUUIDCreateString(nil, uuid.takeRetainedValue()) as String
        return uuidString
    }
    
    /// Find a screen by its UUID
    @MainActor static func screen(withUUID uuid: String) -> NSScreen? {
        return NSScreenUUIDCache.shared.screen(forUUID: uuid)
    }
    
    /// Get UUID to NSScreen mapping for all screens
    @MainActor static var screensByUUID: [String: NSScreen] {
        return NSScreenUUIDCache.shared.allScreens
    }

    /// 1-based index of the screen with this UUID within NSScreen.screens,
    /// matching sketchybar's `display = 1/2/3` convention (both are thin
    /// wrappers over the same CGDirectDisplayID active list ordering).
    @MainActor static func index(forUUID uuid: String?) -> Int? {
        guard let uuid else { return nil }
        return NSScreen.screens.firstIndex(where: { $0.displayUUID == uuid }).map { $0 + 1 }
    }
}

/// Cache for UUID to NSScreen mappings to avoid repeated lookups
@MainActor
final class NSScreenUUIDCache {
    static let shared = NSScreenUUIDCache()
    
    private var cache: [String: NSScreen] = [:]
    private var observer: Any?
    
    private init() {
        rebuildCache()
        setupObserver()
    }
    
    deinit {
        if let observer = observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }
    
    private func setupObserver() {
        observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.rebuildCache()
        }
    }
    
    private func rebuildCache() {
        var newCache: [String: NSScreen] = [:]
        
        for screen in NSScreen.screens {
            if let uuid = screen.displayUUID {
                newCache[uuid] = screen
            }
        }
        
        cache = newCache
    }
    
    func screen(forUUID uuid: String) -> NSScreen? {
        return cache[uuid]
    }
    
    var allScreens: [String: NSScreen] {
        return cache
    }
}
