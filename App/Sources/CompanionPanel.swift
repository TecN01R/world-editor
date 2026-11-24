import SwiftUI
import UIKit
import WriterCore

/// The companion, beside the page (a sheet when folded), laid out like the AI
/// chat apps people know: the author's messages in bubbles on the right (New
/// York, their words), the companion's replies as plain text across the panel
/// (San Francisco), newest at the bottom, and a message field below (typed, or
/// dictated with the keyboard's microphone). iOS has no chat view, so the
/// bubbles are the one custom part.
struct CompanionPanel: View {
    @Environment(Library.self) private var library
    @Environment(Companion.self) private var companion
    @Environment(\.scenePhase) private var scenePhase
    @State private var message = ""
    @State private var confirmingNew = false
    /// One height for the whole message bar: the HIG's minimum touch size,
    /// growing with Dynamic Type.
    @ScaledMetric(relativeTo: .body) private var barHeight: CGFloat = 44
    /// The system's standard margin, for the conversation and the message bar.
    private static let margin: CGFloat = 20
    /// Folded, a sheet; unfolded, the inspector column beside the page.
    let inSheet: Bool

    /// Folded, a stock sheet: a navigation bar with the title, Close and the
    /// menu. On the folded Duo a sheet's bar would otherwise go into the side
    /// column (tried 2026-11-23); with a couple of controls Apple's advice is to
    /// keep it horizontal (iOS 27.1, `toolbarVerticalBehavior`). Unfolded, the
    /// inspector's own toolbar holds the menu: a navigation stack nested in the
    /// split view's column destabilised its layout while folding.
    var body: some View {
        if inSheet {
            NavigationStack {
                conversation
                    .navigationTitle("Companion")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close", systemImage: "xmark") { companion.isOpen = false }
                        }
                        if ready { ToolbarItem(placement: .primaryAction) { more } }
                    }
            }
            .toolbarVerticalBehavior(.disabled)
        } else {
            conversation
                .toolbar { if ready { ToolbarItem(placement: .primaryAction) { more } } }
        }
    }

    /// The model is on the phone: until then there's nothing the menu could do.
    private var ready: Bool { companion.download == nil && companion.state != .downloadPaused && !companion.needsDownload }

    private var conversation: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                // Until the model is here, only the download shows (over an empty panel).
                ForEach(companion.needsDownload || companion.download != nil ? [] : companion.conversation.turns) { turn in
                    if let thought = companion.thoughts[turn.id] { reasoning(thought, done: true) }
                    // Its latest reply, still unanswered, can be tried again (hold it).
                    reply(turn.question, canRetry: turn.id == companion.conversation.waiting?.id && companion.state == .idle)
                    if let answer = turn.answer { mine(answer) }
                }
                status
            }
            .padding(.horizontal, Self.margin)   // the system's standard margin
            .padding(.vertical)
        }
        .scrollEdgeEffectStyle(.soft, for: [.top, .bottom])   // softened under the bar and the grab handle, as the page is
        .defaultScrollAnchor(.bottom)
        .defaultScrollAnchor(.top, for: .alignment)          // a short conversation starts at the top
        .defaultScrollAnchor(.bottom, for: .sizeChanges)     // follows new messages
        .scrollDismissesKeyboard(.interactively)
        .overlay {
            if let download = companion.download {
                downloading(download)
            } else if companion.needsDownload {
                downloadOffer
            } else if companion.conversation.turns.isEmpty {
                empty
            }
        }
        .safeAreaBar(edge: .bottom) {
            // Nothing to say until the model is here.
            if ready { composer }
        }
        .task { companion.checkModel() }
        // Back in the app after the download dropped: it picks up where it stopped.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, companion.state == .downloadPaused { retry() }
        }
        .confirmationDialog("Start a new conversation about this page?", isPresented: $confirmingNew,
                            titleVisibility: .visible) {
            Button("New Conversation", role: .destructive) {
                message = ""
                companion.startOver(page: library.document, in: library)
            }
        } message: {
            Text("This conversation, and your messages in it, will be deleted.")
        }
    }

    /// The companion's words: plain text, the width of the panel.
    private func reply(_ text: String, canRetry: Bool = false) -> some View {
        Text(Self.markdown(text))
            .frame(maxWidth: .infinity, alignment: .leading)
            .contextMenu {
                copy(text)
                if canRetry {
                    Button("Try Again", systemImage: "arrow.clockwise", action: retry)
                }
            }
    }

    /// The models write Markdown: bold, italics, code and links show as such
    /// (SwiftUI's own inline Markdown), line breaks kept. Half-written Markdown
    /// while a reply streams shows as typed until it closes.
    static func markdown(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(text)
    }

    /// Hold a message to copy it, as in Messages.
    private func copy(_ text: String) -> some View {
        Button("Copy", systemImage: "doc.on.doc") { UIPasteboard.general.string = text }
    }

    /// The author's words: a glass bubble on the right, in New York.
    private func mine(_ text: String) -> some View {
        Text(text)
            .font(.authored(.body))
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .glassEffect(.regular, in: .rect(cornerRadius: 20))
            .contextMenu { copy(text) }
            .padding(.leading, 48)
            .frame(maxWidth: .infinity, alignment: .trailing)
    }

    /// No conversation yet: what the companion is doing, centred like iOS's own
    /// waiting and empty states (the download's too).
    @ViewBuilder private var empty: some View {
        switch companion.state {
        case .idle:
            ContentUnavailableView("Talk About This Page", systemImage: "bubble.left.and.text.bubble.right",
                                   description: Text("Write a little on this page, and the companion will talk with you about it."))
        case .downloadPaused:
            ContentUnavailableView {
                Label("Download Paused", systemImage: "arrow.down.circle")
            } description: {
                Text("The connection dropped. It picks up where it left off.")
            } actions: { resumeDownload }
        case .failed:
            ContentUnavailableView {
                Label("The Companion Couldn’t Reply", systemImage: "exclamationmark.bubble")
            } actions: { tryAgain }
        case .unavailable(let reason):
            ContentUnavailableView("Companion Unavailable", systemImage: "bubble.left", description: Text(reason))
        case .thinking:
            if partialReply == nil, partialReasoning == nil {   // then its thoughts and words appear in the conversation
                ContentUnavailableView {
                    Label {
                        Text("Thinking")
                    } icon: {
                        Image(systemName: "ellipsis").symbolEffect(.variableColor.iterative, options: .repeating)
                    }
                }
            }
        }
    }

    /// Once there's a conversation, what the companion is doing shows at its end.
    @ViewBuilder private var status: some View {
        switch companion.state {
        case _ where companion.conversation.turns.isEmpty
            && (companion.state != .thinking || (partialReply == nil && partialReasoning == nil)):
            EmptyView()   // centred instead (`empty`)
        case .thinking:
            if let thought = partialReasoning { reasoning(thought, done: partialReply != nil) }
            if let writing = partialReply {
                // As it's written: new words fade in, and a pulsing dot shows it
                // isn't done yet (as the AI apps show it).
                VStack(alignment: .leading, spacing: 8) {
                    reply(writing)
                        .contentTransition(.opacity)
                        .animation(.easeOut(duration: 0.2), value: writing)
                    Image(systemName: "circle.fill")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .symbolEffect(.pulse, options: .repeating)
                        .accessibilityLabel("Writing")
                }
            } else if partialReasoning == nil, companion.download == nil {
                thinking
            }
        case .unavailable(let reason):
            Text(reason).foregroundStyle(.secondary)
        case .failed:
            Text("The companion couldn't reply.").foregroundStyle(.secondary)
            tryAgain
        case .downloadPaused:
            Text("The download’s connection dropped.").foregroundStyle(.secondary)
            resumeDownload
        case .idle:
            EmptyView()
        }
    }

    /// Its reasoning so far, while it thinks before replying.
    private var partialReasoning: String? {
        guard let reasoning = companion.reasoning, !reasoning.isEmpty else { return nil }
        return reasoning
    }

    /// What it thought before a reply: collapsed, like the AI apps' "Thinking"
    /// (a stock disclosure group); open it to read the reasoning.
    private func reasoning(_ text: String, done: Bool) -> some View {
        DisclosureGroup {
            Text(text)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label(done ? "Thought" : "Thinking…", systemImage: "lightbulb")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .symbolEffect(.pulse, options: .repeating, isActive: !done)
        }
        .tint(.secondary)
    }

    /// The reply so far, once it has any words.
    private var partialReply: String? {
        guard let writing = companion.writing, !writing.isEmpty else { return nil }
        return writing
    }

    private var thinking: some View {
        Image(systemName: "ellipsis")
            .font(.title2)
            .foregroundStyle(.secondary)
            .symbolEffect(.variableColor.iterative, options: .repeating)
            .accessibilityLabel("Thinking")
    }

    /// Before the model is on the phone: what it is, how big, and the choice to
    /// download it, never started unasked (it's gigabytes).
    private var downloadOffer: some View {
        ContentUnavailableView {
            Label("Download the Companion", systemImage: "arrow.down.circle")
        } description: {
            Text("The companion runs on your phone, so nothing you write leaves it. It needs a one-time download"
                 + (companion.downloadSize.map { " of \($0.formatted(.byteCount(style: .file)))" } ?? "") + ".")
        } actions: {
            Button("Download") { companion.startDownload(page: library.document, in: library) }
                .buttonStyle(.borderedProminent)
        }
    }

    /// The model's one-time download, centred like any of iOS's waiting states.
    private func downloading(_ download: Download) -> some View {
        ContentUnavailableView {
            Label("Downloading the Companion", systemImage: "arrow.down.circle")
        } description: {
            Text("A one-time download. It keeps going if you leave the app.")
        } actions: {
            // The bar, with Foundation's sizes and time left centred under it, as
            // the title and description above are (a stock ProgressView's own
            // value line always starts at the bar's left edge).
            VStack(spacing: 8) {
                ProgressView(value: Double(download.done), total: Double(max(download.total, 1)))
                Text(download.detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: 280)
        }
    }

    private var tryAgain: some View {
        Button("Try Again", systemImage: "arrow.clockwise", action: retry)
            .buttonStyle(.bordered)
    }

    private var resumeDownload: some View {
        Button("Resume Download", systemImage: "arrow.clockwise", action: retry)
            .buttonStyle(.bordered)
    }

    private func retry() { companion.retry(page: library.document, in: library) }

    /// The message field in Liquid Glass: the field and send, one height
    /// (the stock glass button styles each come in a different one).
    private var composer: some View {
        GlassEffectContainer {
            HStack(alignment: .bottom, spacing: 8) {
                // What they type is theirs (New York); the placeholder is the app's.
                TextField("Message", text: $message, prompt: Text("Message").font(.body), axis: .vertical)
                    .font(.authored(.body))
                    .lineLimit(1...6)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .frame(minHeight: barHeight)
                    .glassEffect(.regular.interactive(), in: .rect(cornerRadius: barHeight / 2))
                    .disabled(companion.conversation.waiting == nil)
                Button(action: send) {
                    Image(systemName: "arrow.up")
                        .fontWeight(.semibold)
                        .foregroundStyle(canSend ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
                        .frame(width: barHeight, height: barHeight)
                }
                .glassEffect(canSend ? .regular.tint(.accentColor).interactive() : .regular.interactive(), in: .circle)
                .disabled(!canSend)
                .accessibilityLabel("Send")
            }
        }
        .padding(.horizontal, Self.margin)
        .padding(.vertical)
    }

    /// Everything that isn't the conversation itself.
    private var more: some View {
        Menu {
            Button("New Conversation", systemImage: "square.and.pencil") { confirmingNew = true }
                .disabled(companion.conversation.turns.isEmpty)
            ShareLink("Share Conversation", item: transcript)
                .disabled(companion.conversation.turns.isEmpty)
            Toggle("Think Before Replying", systemImage: "lightbulb",
                   isOn: Binding { companion.thinks } set: { companion.thinks = $0 })
            Section {
                if let update = companion.modelUpdate {
                    Button(action: companion.updateModel) {
                        Label("Update Available", systemImage: "arrow.down.circle")
                        Text("A newer \(Companion.modelName), \(update.bytes.formatted(.byteCount(style: .file)))")
                    }
                }
                // What it's running, as a line to read (a menu has no plain text).
                Button {} label: {
                    Text(Companion.modelName)
                    Text([companion.modelVersion, Self.appVersion].compactMap { $0 }.joined(separator: " · "))
                }
                .disabled(true)
            }
        } label: {
            Label("More", systemImage: "ellipsis")
        }
    }

    /// "World Editor 0.1.0 (1)".
    private static let appVersion: String? = {
        guard let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String else { return nil }
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        return "World Editor \(version)" + (build.map { " (\($0))" } ?? "")
    }()

    /// The conversation as plain text, to paste anywhere: who said what, and
    /// which model replied (to compare how it's going).
    private var transcript: String {
        let title = library.document.title.isEmpty ? "Untitled page" : library.document.title
        let header = "World Editor companion on “\(title)” (\(Companion.modelName), thinking \(companion.thinks ? "on" : "off"))"
        let turns = companion.conversation.turns.flatMap { turn in
            ["Companion: \(turn.question)"] + (turn.answer.map { ["Me: \($0)"] } ?? [])
        }
        return ([header] + turns).joined(separator: "\n\n")
    }

    private var canSend: Bool {
        companion.conversation.waiting != nil && !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func send() {
        guard canSend else { return }
        companion.answer(message, page: library.document, in: library)
        message = ""
    }
}
