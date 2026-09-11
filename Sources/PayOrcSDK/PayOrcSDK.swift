// PayOrcSDK.swift
// Public umbrella — re-exports all public API surface of the PayOrc iOS SDK.
//
// Host apps should import PayOrcSDK and access everything through this module.

// MARK: - Core
@_exported import Foundation

// All public types are declared in their respective files.
// Swift modules expose them automatically — no explicit re-export needed.

// MARK: - SDK Version

/// The current PayOrc iOS SDK version string.
public let PayOrcSDKVersion = "1.0.0"
