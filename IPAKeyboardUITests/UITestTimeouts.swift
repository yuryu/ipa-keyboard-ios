//
//  UITestTimeouts.swift
//  IPAKeyboardUITests
//
//  Shared synchronisation deadlines for the UI-test target (issue #96).
//  Call sites pass these explicitly; helper default parameter values keep
//  the shorter suite defaults for waits within an already-presented screen.
//

import Foundation

extension TimeInterval {
    /// Deadline for the FIRST element wait after a navigation event — cold
    /// launch, NavigationStack push or pop, sheet/alert presentation, and
    /// dismissal/back. On an overloaded CI runner the transition plus SwiftUI
    /// list composition can far outlast the suite-default 10s: in issue #96 a
    /// nominal-10s wait expired ~13s wall-clock after a push, with each
    /// existence poll itself taking ~7s, while the detail screen was still
    /// settling. `waitForExistence` returns the moment the element appears,
    /// so the headroom costs nothing at normal speed; later waits on an
    /// already-composed screen keep their shorter defaults.
    static let postNavigation: TimeInterval = 30
}
