#if DEBUG
import Combine
import SwiftUI
import UIKit

/// When a scene's screen is in its final state, CI takes its picture: the app makes an empty
/// `scene-ready` in its Documents folder (ci/screenshots.sh waits for it), half a second after
/// the last of what the scene waits for (`LaunchScene.waits`) is on screen, for animations to end.
/// The only place the marker is made or removed. The page's measurements are written with it
/// (`SceneMetrics`).
@MainActor
final class SceneStage {
    enum Step: Hashable, Sendable {
        /// The app has drawn its first frame.
        case firstFrame
        /// What the scene presents (a sheet, an alert, Recently Deleted, Focus mode's controls).
        case shown
        /// The keyboard is up.
        case keyboard
        /// The companion's script holds the state the scene shows (thinking, writing, filing,
        /// downloading), or has failed.
        case held
    }

    static let shared = SceneStage()
    private var waiting = LaunchScene.current?.waits ?? []
    private var presented: Set<LaunchScene.Shows> = []

    private nonisolated static var marker: URL { URL.documentsDirectory.appendingPathComponent("scene-ready") }

    /// At launch, before anything else: the marker left by the scene before goes, with its measurements.
    nonisolated static func clearMarker() {
        try? FileManager.default.removeItem(at: marker)
        try? FileManager.default.removeItem(at: SceneMetrics.file)
    }

    /// `step` is on screen; the last one makes the marker, after the animations.
    func reached(_ step: Step) {
        guard let scene = LaunchScene.current, waiting.remove(step) != nil, waiting.isEmpty else { return }
        Task {
            try? await Task.sleep(for: .milliseconds(500))
            SceneMetrics.write(scene: scene.name)
            FileManager.default.createFile(atPath: Self.marker.path, contents: Data())
        }
    }

    /// `step` is on screen, from off the main actor (the companion's model).
    nonisolated static func report(_ step: Step) async {
        await MainActor.run { shared.reached(step) }
    }

    /// Whether to present `what` now: once per launch, if the scene presents it.
    fileprivate func presents(_ what: LaunchScene.Shows) -> Bool {
        guard LaunchScene.current?.presents(what) == true else { return false }
        return presented.insert(what).inserted
    }
}

/// How long a tap's presentation (a sheet's slide, a push) takes to finish.
private let presenting = Duration.milliseconds(600)
/// How long after the first frame a scene's taps come.
private let afterLaunch = Duration.seconds(1)

extension View {
    /// The scene's set-up after the first frame, at the app's root (inside its environment):
    /// what the root presents, the keyboard, the download started; and the marker's first frame
    /// and keyboard.
    func sceneDirector() -> some View { modifier(SceneDirector()) }

    /// Presents `what` from this view when the scene shows it, after the first frame, as a tap
    /// would: sets `shown`.
    func sceneShows(_ what: LaunchScene.Shows, _ shown: Binding<Bool>) -> some View {
        sceneShows(what) { shown.wrappedValue = true }
    }

    /// Does what presents `what` from this view when the scene shows it, after the first frame,
    /// as a tap would.
    func sceneShows(_ what: LaunchScene.Shows, perform present: @escaping @MainActor () -> Void) -> some View {
        task {
            guard SceneStage.shared.presents(what) else { return }
            try? await Task.sleep(for: afterLaunch)
            present()
            guard LaunchScene.current?.shows == what else { return }   // only the way to it
            try? await Task.sleep(for: presenting)
            SceneStage.shared.reached(.shown)
        }
    }
}

private struct SceneDirector: ViewModifier {
    @Environment(Library.self) private var library
    @Environment(Companion.self) private var companion

    func body(content: Content) -> some View {
        content
            .task { await direct() }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidShowNotification)) { _ in
                SceneStage.shared.reached(.keyboard)
            }
    }

    private func direct() async {
        guard let scene = LaunchScene.current else { return }
        let drawn = Duration.milliseconds(300)   // the first frame is drawn by now
        try? await Task.sleep(for: drawn)
        SceneStage.shared.reached(.firstFrame)
        try? await Task.sleep(for: afterLaunch - drawn)
        // The page's fields ask for their sheets through the library (`PageFields`).
        if scene.shows == .typeFields || scene.shows == .field {
            library.fieldsRequest = scene.shows == .field ? .editField(LaunchScene.field) : .editFields(type: LaunchScene.character)
            try? await Task.sleep(for: presenting)
            SceneStage.shared.reached(.shown)
        }
        // The download's Download button.
        if scene.script == .downloading, let conversation = library.lastWorldConversation {
            companion.startDownload(page: library.worldSubject(conversation), in: library)
        }
        if scene.keyboard { raiseKeyboard(typing: scene.typed) }
    }

    /// The keyboard, for the first place to write on screen (the page's writing, the message
    /// field), as a tap there brings it, and `words` typed.
    private func raiseKeyboard(typing words: String?) {
        let windows = UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }
        guard let field = windows.lazy.compactMap({ Self.firstEditable(in: $0) }).first else { return }
        field.becomeFirstResponder()
        // The caret stepped off and back, as a tap moves it: the page then sees where it is (its @ menu).
        let caret = field.selectedRange
        if caret.location > 0 {
            field.selectedRange = NSRange(location: caret.location - 1, length: 0)
            field.selectedRange = caret
        }
        field.scrollRangeToVisible(caret)
        if let words { field.insertText(words) }
    }

    private static func firstEditable(in view: UIView) -> UITextView? {
        if let text = view as? UITextView, text.isEditable, !text.isHidden { return text }
        return view.subviews.lazy.compactMap { firstEditable(in: $0) }.first
    }
}
#endif
