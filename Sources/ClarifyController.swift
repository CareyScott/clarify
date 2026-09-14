import AppKit

final class ClarifyController {
    private let original: String
    private var draft: String
    private var instructions: [String] = []
    private var contextImagesJPEG: [Data] = []
    private var isWorking = false
    private let rewriter: ClaudeRewriter
    private let panel = ClarifyPanel()

    init(original: String, rewriter: ClaudeRewriter) {
        self.original = original
        self.draft = original
        self.rewriter = rewriter
        panel.onSubmit = { [weak self] instruction in self?.submit(instruction) }
        panel.onReplaceSelection = { [weak self] in self?.replaceSelection() }
        panel.onCopy = { [weak self] in self?.copyDraft() }
        panel.onAddScreenshot = { [weak self] in self?.addScreenshot() }
        panel.onPasteImages = { [weak self] images in self?.attachPastedImages(images) }
        panel.onRemoveContextImage = { [weak self] index in self?.removeContextImage(at: index) }
        panel.onCancel = { [weak self] in self?.quit() }
    }

    func start() {
        panel.showNearPointer()
        requestRevision()
    }

    private func requestRevision() {
        isWorking = true
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

    private func submit(_ instruction: String) {
        let trimmed = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { instructions.append(trimmed) }
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
            let screenshot = ScreenCapture.image(ofDisplay: display).flatMap(ContextImage.jpeg(from:))
            DispatchQueue.main.async {
                self.panel.reveal()
                guard let screenshot else {
                    self.showNoteUnlessWorking("Could not take a screenshot.")
                    return
                }
                self.attach([screenshot])
            }
        }
    }

    private func attachPastedImages(_ images: [NSImage]) {
        let jpegs = images.compactMap(ContextImage.jpeg(from:))
        guard !jpegs.isEmpty else {
            showNoteUnlessWorking("Could not read the pasted image.")
            return
        }
        attach(jpegs)
    }

    private func attach(_ jpegs: [Data]) {
        contextImagesJPEG += jpegs
        panel.showContextImages(contextImagesJPEG.compactMap(NSImage.init(data:)))
        showNoteUnlessWorking("Press Return to use the image, or type what to do with it.")
    }

    private func removeContextImage(at index: Int) {
        guard contextImagesJPEG.indices.contains(index) else { return }
        contextImagesJPEG.remove(at: index)
        panel.showContextImages(contextImagesJPEG.compactMap(NSImage.init(data:)))
    }

    private func showNoteUnlessWorking(_ note: String) {
        if !isWorking { panel.showNote(note) }
    }

    private func replaceSelection() {
        guard !isWorking else { return }
        guard FrontAppPaste.isAllowed() else {
            Clipboard.copy(draft)
            panel.showNote("Copied, press ⌘V to paste. To paste in place, allow Accessibility for the app that launched Clarify.")
            return
        }
        panel.hide()
        FrontAppPaste.paste(draft) { NSApp.terminate(nil) }
    }

    private func copyDraft() {
        guard !isWorking else { return }
        Clipboard.copy(draft)
        panel.showNote("Copied.")
    }

    private func quit() {
        rewriter.cancel()
        NSApp.terminate(nil)
    }
}
