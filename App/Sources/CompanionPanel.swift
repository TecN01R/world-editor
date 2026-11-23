import SwiftUI
import UIKit
import WriterCore

/// The companion beside the page, laid out like the AI chat apps people know:
/// the author's messages in bubbles on the right (New York, their words), the
/// companion's replies as plain text across the panel (San Francisco), newest at
/// the bottom, and a message field below (typed, or dictated with the keyboard's
/// microphone). iOS has no chat view, so the bubbles are the one custom part.
struct CompanionPanel: View {
    @Environment(Library.self) private var library
    @Environment(Companion.self) private var companion
    @State private var message = ""
    @State private var confirmingNew = false
    /// One height for the whole message bar: the HIG's minimum touch size,
    /// growing with Dynamic Type.
    @ScaledMetric(relativeTo: .body) private var barHeight: CGFloat = 44
    /// Folded and resting at the bottom: just the latest line.
    var resting = false

    // No toolbar or NavigationStack: on the Duo any toolbar, even a sheet's,
    // joins the app's own in the side column (tried 2026-11-23), and a nested
    // stack's title leaked into the pages list's bar when folded.
    var body: some View {
        if resting { latest } else { conversation }
    }

    /// What the companion last said (or is doing), a glance without opening it.
    private var latest: some View {
        Text(Self.markdown(companion.glance))
            .lineLimit(2)
            .foregroundStyle(companion.conversation.waiting == nil ? .secondary : .primary)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.horizontal)
            .padding(.top, 20)   // below the drag indicator
            .accessibilityHint("Swipe up to open the conversation")
    }

    private var conversation: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                ForEach(companion.conversation.turns) { turn in
                    // Its latest reply, still unanswered, can be tried again (hold it).
                    reply(turn.question, canRetry: turn.id == companion.conversation.waiting?.id && companion.state == .idle)
                    if let answer = turn.answer { mine(answer) }
                }
                status
            }
            .padding()
        }
        .scrollEdgeEffectStyle(.soft, for: [.top, .bottom])   // softened under the bar and the grab handle, as the page is
        .defaultScrollAnchor(.bottom)
        .defaultScrollAnchor(.top, for: .alignment)          // a short conversation starts at the top
        .defaultScrollAnchor(.bottom, for: .sizeChanges)     // follows new messages
        .scrollDismissesKeyboard(.interactively)
        .overlay {
            if companion.conversation.turns.isEmpty, companion.state == .idle {
                ContentUnavailableView("Talk About This Page", systemImage: "bubble.left.and.text.bubble.right",
                                       description: Text("Write a little on this page, and the companion will talk with you about it."))
            }
        }
        .safeAreaBar(edge: .bottom) { composer }
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

    @ViewBuilder private var status: some View {
        switch companion.state {
        case .thinking:
            if let writing = companion.writing, !writing.isEmpty {
                reply(writing)   // as it's written
            } else {
                thinking
            }
        case .unavailable(let reason):
            Text(reason).foregroundStyle(.secondary)
        case .failed:
            Text("The companion couldn't reply.").foregroundStyle(.secondary)
            tryAgain
        case .quiet:
            Text("Nothing worth saying yet.").foregroundStyle(.secondary)
            tryAgain
        case .idle:
            EmptyView()
        }
    }

    private var thinking: some View {
        Image(systemName: "ellipsis")
            .font(.title2)
            .foregroundStyle(.secondary)
            .symbolEffect(.variableColor.iterative, options: .repeating)
            .accessibilityLabel("Thinking")
    }

    private var tryAgain: some View {
        Button("Try Again", systemImage: "arrow.clockwise", action: retry)
            .buttonStyle(.bordered)
    }

    private func retry() { companion.retry(page: library.document, in: library) }

    /// The message field in Liquid Glass: more, the field and send, all one
    /// height (the stock glass button styles each come in a different one).
    private var composer: some View {
        GlassEffectContainer {
            HStack(alignment: .bottom, spacing: 8) {
                more
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
        .padding()
    }

    /// Everything that isn't the conversation itself.
    private var more: some View {
        Menu {
            Button("New Conversation", systemImage: "square.and.pencil") { confirmingNew = true }
                .disabled(companion.conversation.turns.isEmpty)
            ShareLink("Share Conversation", item: transcript)
                .disabled(companion.conversation.turns.isEmpty)
            Section("Trial") {   // TRIAL: with and without the guard
                Toggle("Check Replies", systemImage: "checkmark.shield",
                       isOn: Binding { companion.guarded } set: { companion.guarded = $0 })
            }
        } label: {
            Image(systemName: "ellipsis")
                .frame(width: barHeight, height: barHeight)
                .glassEffect(.regular.interactive(), in: .circle)
        }
        .tint(.primary)   // a menu's label takes the tint, not a foreground style
        .accessibilityLabel("More")
    }

    /// The conversation as plain text, to paste anywhere: who said what, and
    /// which model replied (to compare how it's going).
    private var transcript: String {
        let title = library.document.title.isEmpty ? "Untitled page" : library.document.title
        let header = "World Editor companion on “\(title)” (\(Companion.modelFile.replacingOccurrences(of: ".gguf", with: "")), "
            + "Check Replies \(companion.guarded ? "on" : "off"))"
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
