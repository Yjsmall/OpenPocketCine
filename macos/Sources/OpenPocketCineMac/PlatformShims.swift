import AppKit
import Foundation
import SwiftUI
#if os(iOS)
    import UIKit
#endif

/// Platform shim for the iOS shell's `UIApplication.isIdleTimerDisabled` and
/// active/inactive notifications. A monitor should stay lit on both platforms.
enum KeepScreenAwake {
    private static var activity: NSObjectProtocol?

    static var resignActiveNotification: Notification.Name {
        #if os(iOS)
            return UIApplication.willResignActiveNotification
        #else
            return NSApplication.willResignActiveNotification
        #endif
    }

    static var becameActiveNotification: Notification.Name {
        #if os(iOS)
            return UIApplication.didBecomeActiveNotification
        #else
            return NSApplication.didBecomeActiveNotification
        #endif
    }

    static func setEnabled(_ enabled: Bool) {
        #if os(iOS)
            UIApplication.shared.isIdleTimerDisabled = enabled
        #else
            if enabled, activity == nil {
                activity = ProcessInfo.processInfo.beginActivity(
                    options: [.idleDisplaySleepDisabled, .userInitiated],
                    reason: "OpenPocketCine monitor is live"
                )
            } else if !enabled, let activity {
                ProcessInfo.processInfo.endActivity(activity)
                self.activity = nil
            }
        #endif
    }
}

/// AppKit twin of the iOS impact-haptic helpers sprinkled through the shell.
@MainActor
enum ImpactHaptics {
    static func light() {
        NSHapticFeedbackManager.defaultPerformer.perform(
            .alignment, performanceTime: .default)
    }

    static func rigid() {
        NSHapticFeedbackManager.defaultPerformer.perform(
            .generic, performanceTime: .default)
    }

    static func soft(intensities: [CGFloat]) {
        // NSHapticFeedbackManager has no intensity control; one tick stands in.
        light()
    }
}

/// macOS host for the operator's full-screen settings / legal panels
/// (`AppPanelHost` lives in the iOS MediaLibraryStub file).
struct AppPanelHost: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        switch model.homePanel {
        case .settings:
            SettingsRootView(safeArea: EdgeInsets())
        case .privacy: LegalDocumentView(kind: .privacy)
        case .terms: LegalDocumentView(kind: .terms)
        case .licenses: LegalDocumentView(kind: .licenses)
        case .notice: LegalDocumentView(kind: .notice)
        case .media, nil: EmptyView()
        }
    }
}
