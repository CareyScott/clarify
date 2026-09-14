import AppKit

enum DraftSource {
    case selection
    case scratchpad
}

final class ClarifyController {
    private static let pasteTargetActivationDelay: TimeInterval = 0.35
    private static let useAttachedImagesInstruction = "Take the attached images into account."
    private static let clarifyBundlePrefix = "com.careyscott.clarify"

    private let source: DraftSource
    private let onFinish: (ClarifyController) -> Void
    private var pasteTarget: NSRunningApplication?
    private var original: String
    private var draft: String
    private var instructions: [String] = []
    private var contextImagesJPEG: [Data] = []
    private var hasUnsentImages = false
    private var isWorking = false
    private let rewriter: ClaudeRewriter
    private let panel = ClarifyPanel()
    private var activationObserver: NSObjectProtocol?
    private var appSwitchObserver: NSObjectProtocol?

    static func canReceivePaste(_ app: NSRunningApplication?) -> Bool {
        guard let app else { return false }
        return app.activationPolicy == .regular
            && app.processIdentifier != ProcessInfo.processInfo.processIdentifier
            && !(app.bundleIdentifier ?? "").hasPrefix(clarifyBundlePrefix)
    }

    init(source: DraftSource, original: String, pasteTarget: NSRunningApplication?, rewriter: ClaudeRewriter, onFinish: @escaping (ClarifyController) -> Void) {
        self.source = source
        self.onFinish = onFinish
        self.pasteTarget = Self.canReceivePaste(pasteTarget) ? pasteTarget : nil
        self.original = original
        self.draft = original
        self.rewriter = rewriter
        panel.onClarifyDraft = { [weak self] text in self?.clarify(text) }
        panel.onSendInstruction = { [weak self] instruction in self?.send(instruction) }
        panel.onPrimaryAction = { [weak self] in self?.pasteDraft() }
        panel.onCopy = { [weak self] in self?.copyDraft() }
        panel.onAddScreenshot = { [weak self] in self?.addScreenshot() }
        panel.onAddImages = { [weak self] images in self?.attach(images) }
        panel.onRemoveContextImage = { [weak self] index in self?.removeContextImage(at: index) }
        panel.onCancel = { [weak self] in self?.finish() }
        panel.onOpenSettings = { Self.openSettings() }
        activationObserver = NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            NSApp.setActivationPolicy(.accessory)
            self?.panel.reveal(activatingApp: false)
        }
        if isScratchpad {
            appSwitchObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] notification in
                self?.followPasteTarget(notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)
            }
        }
    }

    func start() {
        showPrimaryAction()
        guard isScratchpad else {
            panel.showNearPointer(activatingApp: false)
            requestRevision()
            return
        }
        guard isComposing else {
            panel.showNearPointer(activatingApp: true)
            requestRevision()
            return
        }
        panel.showComposer()
        panel.showNearPointer(activatingApp: true)
    }

    func reveal() {
        panel.reveal(activatingApp: isScratchpad)
    }

    private var isScratchpad: Bool {
        source == .scratchpad
    }

    private var isComposing: Bool {
        isScratchpad && original.isEmpty
    }

    private func followPasteTarget(_ app: NSRunningApplication?) {
        guard Self.canReceivePaste(app) else { return }
        pasteTarget = app
        showPrimaryAction()
    }

    private func showPrimaryAction() {
        switch (source, pasteTarget) {
        case (.selection, _):
            panel.setPrimaryAction(label: "Replace", showsCopy: true)
        case let (.scratchpad, target?):
            panel.setPrimaryAction(label: "Paste into \(target.localizedName ?? "previous app")", showsCopy: true)
        case (.scratchpad, nil):
            panel.setPrimaryAction(label: "Copy", showsCopy: false)
        }
    }

    private func clarify(_ text: String) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            panel.showNote("Type, paste or dictate something first.")
            return
        }
        original = text
        draft = text
        requestRevision()
    }

    private func requestRevision() {
        isWorking = true
        hasUnsentImages = false
        panel.setHasUnsentImages(false)
        panel.showWorking(diff: WordDiff.segments(from: original, to: draft))
        let request = RevisionRequest(original: original, draft: draft, instructions: instructions, contextImagesJPEG: contextImagesJPEG)
        rewriter.revise(request) { [weak self] result in
            guard let self else { return }
            self.isWorking = false
            switch result {
            case let .success(revision):
                self.draft = revision.text
                self.panel.showRevision(notes: revision.notes, diff: WordDiff.segments(from: self.original, to: revision.text))
            case let .failure(failure):
                self.panel.showRevision(notes: failure.message, diff: WordDiff.segments(from: self.original, to: self.draft))
            }
        }
    }

    private func send(_ instruction: String) {
        let trimmed = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || hasUnsentImages else { return }
        instructions.append(trimmed.isEmpty ? Self.useAttachedImagesInstruction : trimmed)
        requestRevision()
    }

    private func addScreenshot() {
        guard ScreenCapture.hasPermission() else {
            panel.showNote("Needs Screen Recording permission for the app that launched Clarify. System Settings > Privacy & Security > Screen Recording.")
            return
        }
        let display = ScreenCapture.displayNumberUnderPointer()
        panel.hide()
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.25) {
            let screenshot = ScreenCapture.image(ofDisplay: display)
            DispatchQueue.main.async {
                self.panel.reveal(activatingApp: self.isScratchpad)
                guard let screenshot else {
                    self.showNoteUnlessWorking("Could not take a screenshot.")
                    return
                }
                self.attach([screenshot])
            }
        }
    }

    private func attach(_ images: [NSImage]) {
        let jpegs = images.compactMap(ContextImage.jpeg(from:))
        guard !jpegs.isEmpty else {
            showNoteUnlessWorking("Could not read that image.")
            return
        }
        contextImagesJPEG += jpegs
        panel.showContextImages(contextImagesJPEG.compactMap(NSImage.init(data:)))
        if isComposing {
            showNoteUnlessWorking("Image added. It goes to Claude with the draft when you press Clarify.")
            return
        }
        hasUnsentImages = true
        panel.setHasUnsentImages(true)
        showNoteUnlessWorking("Image added but not sent yet. Press ↑ to send it, or type what it is for first.")
    }

    private func removeContextImage(at index: Int) {
        guard contextImagesJPEG.indices.contains(index) else { return }
        contextImagesJPEG.remove(at: index)
        if contextImagesJPEG.isEmpty {
            hasUnsentImages = false
            panel.setHasUnsentImages(false)
        }
        panel.showContextImages(contextImagesJPEG.compactMap(NSImage.init(data:)))
    }

    private func showNoteUnlessWorking(_ note: String) {
        if !isWorking { panel.showNote(note) }
    }

    private func pasteDraft() {
        guard !isWorking else { return }
        if isScratchpad && pasteTarget == nil {
            copyDraft()
            return
        }
        guard AccessibilityPermission.isGranted() else {
            Clipboard.copy(draft)
            panel.showNote("Copied, press ⌘V to paste. To paste directly, allow Accessibility for the app that launched Clarify.")
            return
        }
        panel.hide()
        let activationDelay = bringPasteTargetForward()
        DispatchQueue.main.asyncAfter(deadline: .now() + activationDelay) {
            FrontAppPaste.paste(self.draft) { self.finish() }
        }
    }

    private func bringPasteTargetForward() -> TimeInterval {
        guard isScratchpad, let pasteTarget else { return 0 }
        NSApp.yieldActivation(to: pasteTarget)
        _ = pasteTarget.activate(from: .current)
        return Self.pasteTargetActivationDelay
    }

    private func copyDraft() {
        guard !isWorking else { return }
        Clipboard.copy(draft)
        panel.confirmCopy()
    }

    private static func openSettings() {
        let settingsApp = Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("Clarify Settings.app")
        NSWorkspace.shared.openApplication(at: settingsApp, configuration: NSWorkspace.OpenConfiguration())
    }

    func discard() {
        rewriter.cancel()
        panel.close()
        if let activationObserver { NotificationCenter.default.removeObserver(activationObserver) }
        if let appSwitchObserver { NSWorkspace.shared.notificationCenter.removeObserver(appSwitchObserver) }
        activationObserver = nil
        appSwitchObserver = nil
        NSApp.setActivationPolicy(.accessory)
    }

    private func finish() {
        discard()
        onFinish(self)
    }
}
