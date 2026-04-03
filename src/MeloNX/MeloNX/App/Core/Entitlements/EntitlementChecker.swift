//
//  EntitlementChecker.swift
//  MeloNX
//
//  Created by Stossy11 on 15/02/2025.
//

import Foundation
import Security

typealias SecTaskRef = OpaquePointer

@_silgen_name("SecTaskCopyValueForEntitlement")
func SecTaskCopyValueForEntitlement(
    _ task: SecTaskRef,
    _ entitlement: NSString,
    _ error: NSErrorPointer
) -> CFTypeRef?

@_silgen_name("SecTaskCopyTeamIdentifier")
func SecTaskCopyTeamIdentifier(
    _ task: SecTaskRef,
    _ error: NSErrorPointer
) -> NSString?

@_silgen_name("SecTaskCreateFromSelf")
func SecTaskCreateFromSelf(
    _ allocator: CFAllocator?
) -> SecTaskRef?

@_silgen_name("CFRelease")
func CFRelease(_ cf: CFTypeRef)

@_silgen_name("SecTaskCopyValuesForEntitlements")
func SecTaskCopyValuesForEntitlements(
    _ task: SecTaskRef,
    _ entitlements: CFArray,
    _ error: UnsafeMutablePointer<Unmanaged<CFError>?>?
) -> CFDictionary?

func releaseSecTask(_ task: SecTaskRef) {
    let cf = unsafeBitCast(task, to: CFTypeRef.self)
    CFRelease(cf)
}

func checkAppEntitlements(_ ents: [String]) -> [String: Any] {
    guard let task = SecTaskCreateFromSelf(nil) else {
        return [:]
    }
    defer {
        releaseSecTask(task)
    }

    guard let entitlements = SecTaskCopyValuesForEntitlements(task, ents as CFArray, nil) else {
        return [:]
    }

    return (entitlements as NSDictionary) as? [String: Any] ?? [:]
}

func checkAppEntitlement(_ ent: String) -> Bool {
    guard let task = SecTaskCreateFromSelf(nil) else {
        return false
    }
    defer {
        releaseSecTask(task)
    }

    func parseEntitlementValue(_ value: CFTypeRef?) -> Bool {
        guard let value else {
            return false
        }

        if let number = value as? NSNumber {
            return number.boolValue
        }

        if let bool = value as? Bool {
            return bool
        }

        if let string = value as? NSString {
            let normalized = String(string).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return normalized == "1" || normalized == "true" || normalized == "yes"
        }

        return false
    }

    func checkEntitlementValue(_ key: String) -> Bool {
        let value = SecTaskCopyValueForEntitlement(task, key as NSString, nil)
        return parseEntitlementValue(value)
    }

    if checkEntitlementValue(ent) {
        return true
    }

    if ent == "com.apple.developer.kernel.increased-memory-limit" {
        if ProcessInfo.processInfo.hasTXM {
            return true
        }

        if ProcessInfo.processInfo.environment["HAS_TXM"] == "1" || ProcessInfo.processInfo.environment["DUAL_MAPPED_JIT"] == "1" {
            return true
        }

        return checkEntitlementValue("dynamic-codesigning") ||
            checkEntitlementValue("com.apple.security.cs.allow-jit") ||
            checkEntitlementValue("com.apple.developer.kernel.extended-virtual-addressing") ||
            checkEntitlementValue("com.apple.private.memorystatus")
    }

    return false
}
