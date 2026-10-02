import AppKit
@testable import FluidVoice_Debug
import XCTest

@MainActor
final class UpdatePromptIntegrationTests: XCTestCase {
    func testOfferWithQueuedFailureTransitionsToOnlyInstallStatus() async throws {
        let presenter = UpdatePromptPresenter.shared
        let updater = SimpleUpdater()
        presenter.dismissAll()
        defer {
            presenter.dismissAll()
            updater.dismissUpdateInstallStatus()
        }
        let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let keyWindow = NSApp.keyWindow
        let firstResponder = keyWindow?.firstResponder
        var installActions = 0
        var failureActions = 0
        let version = "offer-test-\(UUID().uuidString)"

        presenter.presentFloatingPrompt(title: "Update Available", message: "Your dictation can continue.", actions: [
            FloatingPromptAction(title: "Install Now") {
                installActions += 1
                updater.showUpdateInstallStatus(version: version)
            },
            FloatingPromptAction(title: "Later") {},
        ])
        let offer = try self.visibleWindow("Update Available")
        let install = try self.button("Install Now", in: offer)
        presenter.presentFloatingPrompt(title: "Update Check Failed", message: "Queued notice", actions: [
            FloatingPromptAction(title: "OK") { failureActions += 1 },
        ])
        install.performClick(nil)

        XCTAssertEqual(installActions, 1)
        XCTAssertFalse(offer.isVisible)
        XCTAssertFalse(self.isVisible("Update Check Failed"))
        let status = try self.visibleWindow("Installing FluidVoice \(version)")
        let progress = try XCTUnwrap(status.contentView?.subviews.compactMap { $0 as? NSProgressIndicator }.first)
        XCTAssertTrue(progress.isIndeterminate)
        XCTAssertFalse(progress.isHidden)
        XCTAssertFalse(updater.isUpdateInProgress, "UI-only status must not begin an install or download")
        XCTAssertNil(NSApp.modalWindow)
        XCTAssertEqual(NSWorkspace.shared.frontmostApplication?.processIdentifier, frontmostPID)
        XCTAssertTrue(NSApp.keyWindow === keyWindow)
        XCTAssertTrue(keyWindow?.firstResponder === firstResponder)

        var mainActorRan = false
        await Task { @MainActor in mainActorRan = true }.value
        XCTAssertTrue(mainActorRan && status.isVisible)
        install.performClick(nil)
        XCTAssertEqual(installActions, 1, "A retained button cannot start installation twice")

        // Mirror failure cleanup: progress closes before the nonmodal error opens.
        updater.dismissUpdateInstallStatus()
        XCTAssertFalse(status.isVisible)
        presenter.presentFloatingPrompt(title: "Update Check Failed", message: "Simulated failure", actions: [
            FloatingPromptAction(title: "OK") { failureActions += 1 },
        ])
        let failure = try self.visibleWindow("Update Check Failed")
        XCTAssertNil(NSApp.modalWindow)
        XCTAssertEqual(NSWorkspace.shared.frontmostApplication?.processIdentifier, frontmostPID)
        XCTAssertTrue(NSApp.keyWindow === keyWindow)
        XCTAssertTrue(keyWindow?.firstResponder === firstResponder)
        mainActorRan = false
        await Task { @MainActor in mainActorRan = true }.value
        XCTAssertTrue(mainActorRan && failure.isVisible)
        failure.cancelOperation(nil)
        XCTAssertEqual(failureActions, 1, "Discarded queued notice must never run its handler")
        XCTAssertFalse(failure.isVisible)
    }

    func testDirectInstallStatusInvalidatesOutstandingOfferAndQueue() throws {
        let presenter = UpdatePromptPresenter.shared
        let updater = SimpleUpdater()
        presenter.dismissAll()
        defer {
            presenter.dismissAll()
            updater.dismissUpdateInstallStatus()
        }
        var staleActions = 0
        presenter.presentFloatingPrompt(title: "Update Available", message: "Outstanding offer", actions: [
            FloatingPromptAction(title: "Install Now") { staleActions += 1 },
        ])
        let offer = try self.visibleWindow("Update Available")
        let staleInstall = try self.button("Install Now", in: offer)
        presenter.presentFloatingPrompt(title: "Update Check Failed", message: "Queued notice", actions: [
            FloatingPromptAction(title: "OK") { staleActions += 1 },
        ])
        let version = "direct-test-\(UUID().uuidString)"
        updater.showUpdateInstallStatus(version: version)
        let status = try self.visibleWindow("Installing FluidVoice \(version)")
        XCTAssertFalse(offer.isVisible)
        XCTAssertFalse(self.isVisible("Update Check Failed"))
        staleInstall.performClick(nil)
        XCTAssertEqual(staleActions, 0)
        XCTAssertTrue(status.isVisible)
        updater.dismissUpdateInstallStatus()
        XCTAssertFalse(status.isVisible)
        XCTAssertFalse(updater.isUpdateInProgress)
        XCTAssertNil(NSApp.modalWindow)
    }

    private func visibleWindow(_ title: String) throws -> NSWindow {
        try XCTUnwrap(NSApp.windows.first { $0.isVisible && $0.title == title })
    }

    private func isVisible(_ title: String) -> Bool {
        NSApp.windows.contains { $0.isVisible && $0.title == title }
    }

    private func button(_ title: String, in window: NSWindow) throws -> NSButton {
        try XCTUnwrap(window.contentView?.subviews.compactMap { $0 as? NSButton }.first { $0.title == title })
    }
}
