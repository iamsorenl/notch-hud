//
//  EnvironmentValues+Extensions.swift
//  DynamicNotchKit
//  [NotchHUD] Patched: @Entry macro replaced with manual EnvironmentKey so the
//  package builds under Command Line Tools (no SwiftUIMacros plugin). Behavior identical.
//

import SwiftUI

private struct NotchStyleKey: EnvironmentKey {
    static let defaultValue: DynamicNotchStyle = .auto
}

private struct NotchSectionKey: EnvironmentKey {
    static let defaultValue: DynamicNotchSection = .expanded
}

extension EnvironmentValues {
    var notchStyle: DynamicNotchStyle {
        get { self[NotchStyleKey.self] }
        set { self[NotchStyleKey.self] = newValue }
    }

    var notchSection: DynamicNotchSection {
        get { self[NotchSectionKey.self] }
        set { self[NotchSectionKey.self] = newValue }
    }
}

enum DynamicNotchSection {
    case expanded
    case compactLeading
    case compactTrailing
}
