import AppKit

@main
private enum UpdatePromptTests {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        DispatchQueue.global().asyncAfter(deadline: .now() + 15) {
            print("FAIL: prompt blocked the main actor")
            exit(2)
        }
        DispatchQueue.main.async {
            Task { @MainActor in
                await self.run()
                exit(0)
            }
        }
        app.run()
    }

    @MainActor
    private static func run() async {
        let originalApp = NSWorkspace.shared.frontmostApplication
        defer { originalApp?.activate(options: []) }
        let presenter = UpdatePromptPresenter()
        var installed = 0
        var postponed = 0
        let actions = [
            FloatingPromptAction(title: "Install Now") { installed += 1 },
            FloatingPromptAction(title: "Later") { postponed += 1 },
        ]
        let frontmostPID = originalApp?.processIdentifier
        let keyWindow = NSApp.keyWindow
        let firstResponder = keyWindow?.firstResponder
        presenter.presentFloatingPrompt(title: "Update Available", message: "FluidVoice v1.6.10 is now available. The app will restart automatically after installation.", actions: actions)
        assert(NSWorkspace.shared.frontmostApplication?.processIdentifier == frontmostPID)
        assert(NSApp.keyWindow === keyWindow && keyWindow?.firstResponder === firstResponder)
        assert(NSApp.modalWindow == nil)
        let offer = self.visiblePanel("Update Available")
        assert(offer.styleMask.contains(.nonactivatingPanel))
        assert(!offer.isKeyWindow && offer.level == .floating)
        assert(installed == 0 && postponed == 0)
        let primary = self.button("Install Now", in: offer)
        let later = self.button("Later", in: offer)
        assert(primary.acceptsFirstMouse(for: nil))
        self.checkLayout(offer)

        // A queued dictation/hotkey job must run before the unanswered prompt is dismissed.
        var callbackRan = false
        let callback = Task { @MainActor in callbackRan = true }
        await callback.value
        try? await Task.sleep(nanoseconds: 20_000_000)
        assert(callbackRan && offer.isVisible)
        assert(installed == 0 && postponed == 0)

        presenter.presentFloatingPrompt(title: "Update Available", message: "duplicate", actions: actions)
        presenter.presentFloatingPrompt(title: "Update Check Failed", message: "The download failed. Please try again later.", actions: [FloatingPromptAction(title: "OK") {}])
        assert(NSApp.windows.filter { $0.title == "Update Available" && $0.isVisible }.count == 1)
        later.performClick(nil)
        assert(postponed == 1 && installed == 0 && !offer.isVisible)
        primary.performClick(nil) // A stale button must not answer the next prompt or start installation.
        assert(installed == 0)
        let failure = self.visiblePanel("Update Check Failed")
        failure.cancelOperation(nil)
        assert(!failure.isVisible)

        // Keep our own text destination key too, while FluidVoice is already active.
        let destination = NSWindow(contentRect: NSRect(x: 40, y: 40, width: 360, height: 120), styleMask: [.titled], backing: .buffered, defer: false)
        destination.isReleasedWhenClosed = false
        destination.title = "Dictation destination"
        let field = NSTextField(frame: NSRect(x: 20, y: 40, width: 320, height: 24))
        destination.contentView?.addSubview(field)
        NSApp.activate(ignoringOtherApps: true)
        destination.makeKeyAndOrderFront(nil)
        destination.makeFirstResponder(field)
        try? await Task.sleep(nanoseconds: 100_000_000)
        guard let editor = destination.firstResponder as? NSTextView else { fatalError("No text destination") }
        editor.insertText("Current dictation", replacementRange: editor.selectedRange())
        presenter.presentFloatingPrompt(title: "Update Available", message: "Your dictation can continue.", actions: actions)
        assert(NSApp.keyWindow === destination && destination.firstResponder === editor)
        editor.insertText(" completes", replacementRange: editor.selectedRange())
        assert(editor.string == "Current dictation completes")
        let secondOffer = self.visiblePanel("Update Available")
        self.savePreview(secondOffer)
        secondOffer.makeKey()
        assert(secondOffer.performKeyEquivalent(with: self.returnKey(for: secondOffer)))
        assert(installed == 1 && postponed == 1 && !secondOffer.isVisible)
        destination.close()

        // Repeated checks stay bounded and every retained prompt still gets its action.
        var answered: [Int] = []
        for index in 0..<8 {
            presenter.presentFloatingPrompt(title: "Queue \(index)", message: "Check \(index)", actions: [FloatingPromptAction(title: "OK") { answered.append(index) }])
        }
        for index in 0..<4 {
            self.visiblePanel("Queue \(index)").cancelOperation(nil)
        }
        assert(answered == [0, 1, 2, 3])
        assert(!NSApp.windows.contains { $0.isVisible && $0.title.hasPrefix("Queue ") })
        presenter.presentFloatingPrompt(title: "Empty", message: "No actions", actions: [])
        assert(!NSApp.windows.contains { $0.isVisible && $0.title == "Empty" })
        presenter.presentFloatingPrompt(title: "Recovered", message: "Ready for the next update", actions: [FloatingPromptAction(title: "OK") {}])
        self.visiblePanel("Recovered").cancelOperation(nil)

        // Installation/dismissal clears every waiting notice and invalidates retained buttons.
        presenter.presentFloatingPrompt(title: "Update Available", message: "Dismissed offer", actions: actions)
        let dismissedOffer = self.visiblePanel("Update Available")
        let staleInstall = self.button("Install Now", in: dismissedOffer)
        presenter.presentFloatingPrompt(title: "Queued failure", message: "Discarded notice", actions: [FloatingPromptAction(title: "OK") { postponed += 1 }])
        presenter.dismissAll()
        presenter.dismissAll()
        assert(!dismissedOffer.isVisible)
        assert(!NSApp.windows.contains { $0.isVisible && $0.title == "Queued failure" })
        staleInstall.performClick(nil)
        assert(installed == 1 && postponed == 1)
        presenter.presentFloatingPrompt(title: "Update Available", message: "Fresh offer", actions: actions)
        staleInstall.performClick(nil)
        assert(installed == 1 && self.visiblePanel("Update Available").isVisible)
        self.visiblePanel("Update Available").cancelOperation(nil)
        assert(postponed == 2)
        print("PASS: main actor responsive; focus preserved; text completes; actions, direct cancellation, duplicates, stale buttons, bounded queue, dismiss-all and recovery checks")
    }

    @MainActor
    private static func visiblePanel(_ title: String) -> NSWindow {
        guard let panel = NSApp.windows.first(where: { $0.title == title && $0.isVisible }) else { fatalError("Missing prompt: \(title)") }
        return panel
    }

    @MainActor
    private static func button(_ title: String, in panel: NSWindow) -> NSButton {
        guard let button = panel.contentView?.subviews.compactMap({ $0 as? NSButton }).first(where: { $0.title == title }) else { fatalError("Missing button: \(title)") }
        return button
    }

    @MainActor
    private static func checkLayout(_ panel: NSWindow) {
        guard let content = panel.contentView else { fatalError("Missing content") }
        for view in content.subviews {
            assert(content.bounds.contains(view.frame))
            if let label = view as? NSTextField { assert(label.frame.height >= ceil(label.fittingSize.height)) }
            if let button = view as? NSButton { assert(button.frame.width >= ceil(button.fittingSize.width)) }
        }
    }

    @MainActor
    private static func returnKey(for panel: NSWindow) -> NSEvent {
        guard let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: panel.windowNumber, context: nil, characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36) else {
            fatalError("Cannot create return-key event")
        }
        return event
    }

    @MainActor
    private static func savePreview(_ panel: NSWindow) {
        guard let view = panel.contentView, let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { fatalError("Cannot render preview") }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        guard let data = bitmap.representation(using: .png, properties: [:]) else { fatalError("Cannot encode preview") }
        do {
            try data.write(to: URL(fileURLWithPath: "/tmp/fluidvoice-update-prompt.png"))
        } catch {
            fatalError("Cannot save preview: \(error)")
        }
    }
}
