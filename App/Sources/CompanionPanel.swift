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
    @State private var showingChanges = false
    /// Where the conversation is scrolled: the newest message, as in Messages.
    @State private var position = ScrollPosition(edge: .bottom)
    /// One height for the whole message bar: the HIG's minimum touch size,
    /// growing with Dynamic Type.
    @ScaledMetric(relativeTo: .body) private var barHeight: CGFloat = 44
    /// The system's standard margin, for the conversation and the message bar.
    private static let margin: CGFloat = 20
    /// Folded, a sheet; unfolded, the column beside the page.
    let inSheet: Bool
    /// A conversation about the whole world, beside (unfolded) or over (folded) the
    /// world's conversation list (`WorldConversationList`): its bar has Changes and the menu.
    var worldConversation: UUID? = nil
    /// Starts another world conversation (its menu's New Conversation).
    var newConversation: (() -> Void)? = nil
    private var aboutWorld: Bool { worldConversation != nil }

    /// Folded, a stock sheet: a navigation bar with the title, Close, Changes
    /// and the menu. On the folded Duo a sheet's bar would otherwise go into the side
    /// column (tried 2026-11-23); with a couple of controls Apple's advice is to
    /// keep it horizontal (iOS 27.1, `toolbarVerticalBehavior`). Unfolded, the
    /// column has no bar of its own (see below).
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
                        if ready {
                            ToolbarItem(placement: .primaryAction) { changesButton }
                            ToolbarItem(placement: .primaryAction) { more }
                        }
                    }
            }
            .toolbarVerticalBehavior(.disabled)
        } else if aboutWorld {
            conversation
                .navigationTitle(companion.conversation.title ?? "New Conversation")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    if ready {
                        ToolbarItem(placement: .primaryAction) { changesButton }
                        ToolbarItem(placement: .primaryAction) { more }
                    }
                }
        } else {
            // No toolbar in the column: merged into the split view's bar, it
            // crashed UIKit's layout while the Duo folded (2026-11-23, twice).
            // The menu sits beside the message field instead.
            conversation
        }
    }

    /// What the conversation is about: the open page, or the world as a whole.
    private var subject: WriterCore.Document { worldConversation.map(library.worldSubject) ?? library.document }

    /// The model is on the phone: until then there's nothing the menu could do.
    private var ready: Bool { companion.download == nil && companion.state != .downloadPaused && !companion.needsDownload }

    private var conversation: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                // Until the model is here, only the download shows (over an empty panel).
                let turns = companion.needsDownload || companion.download != nil ? [] : companion.conversation.turns
                ForEach(Array(turns.enumerated()), id: \.element.id) { i, turn in
                    if let thought = companion.thoughts[turn.question] { reasoning(thought, done: true) }
                    if !turn.question.isEmpty { reply(turn) }   // empty: the author began
                    // What was filed from the author's message before this reply shows under the
                    // reply, as the companion's doing, in the order it happens: filing runs once
                    // the reply is done (Kevin, 2026-11-24).
                    if i > 0, let record = turns[i - 1].filed, !record.isEmpty { filed(record, from: turns[i - 1].id) }
                    if let answer = turn.answer { mine(answer) }
                    // No reply after it (being tried again): under the message meanwhile.
                    if i == turns.count - 1, let record = turn.filed, !record.isEmpty { filed(record, from: turn.id) }
                }
                status
            }
            .padding(.horizontal, Self.margin)   // the system's standard margin
            .padding(.vertical)
        }
        .scrollEdgeEffectStyle(.soft, for: [.top, .bottom])   // softened under the bar and the grab handle, as the page is
        .defaultScrollAnchor(.bottom)
        .defaultScrollAnchor(.top, for: .alignment)          // a short conversation starts at the top
        // Sending brings the conversation to the bottom (send()); the reply
        // then grows below without moving it, so you read at your own pace (Kevin).
        .defaultScrollAnchor(.top, for: .sizeChanges)
        .scrollPosition($position)
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
        .task { companion.readModelVersion() }
        // Back in the app after the download dropped: it picks up where it stopped.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, companion.state == .downloadPaused { resume() }
        }
        .sheet(isPresented: $showingChanges) { ChangesView().environment(library).environment(companion) }
        .confirmationDialog("Start a new conversation about this page?", isPresented: $confirmingNew,
                            titleVisibility: .visible) {
            Button("New Conversation", role: .destructive) {
                message = ""
                companion.startOver(page: subject, in: library)
            }
        } message: {
            Text("This conversation, and your messages in it, will be deleted.")
        }
    }

    /// The companion's words: plain text, the width of the panel.
    private func words(_ text: String) -> some View {
        Text(Self.markdown(text))
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// A reply. Its latest, unanswered one can be tried again (hold it), and
    /// each try is kept: swipe between them, or use "‹ 2 of 3 ›" under it. The
    /// one showing when the author answers is the one the conversation goes on
    /// from; after that it stays (Kevin, 2026-11-24).
    private func reply(_ turn: Conversation.Turn) -> some View {
        let waiting = turn.id == companion.conversation.waiting?.id && companion.state == .idle
        let versions = waiting ? turn.versions ?? [] : []
        let at = versions.firstIndex(of: turn.question) ?? 0
        func show(_ i: Int) {
            guard versions.indices.contains(i) else { return }
            withAnimation(.smooth(duration: 0.25)) { companion.choose(versions[i], in: turn.id) }
        }
        return VStack(alignment: .leading, spacing: 4) {
            words(turn.question)
                .id(turn.question)
                .transition(.opacity)
                .contextMenu {
                    copy(turn.question)
                    if waiting {
                        Button("Try Again", systemImage: "arrow.clockwise", action: retry)
                    }
                    if versions.count > 1 {
                        Button("Delete This Version", systemImage: "trash", role: .destructive) {
                            companion.delete(turn.question, in: turn.id)
                        }
                    }
                }
                // Left for the next try, right for the one before, as pages turn.
                .simultaneousGesture(DragGesture(minimumDistance: 30).onEnded { drag in
                    let (x, y) = (drag.translation.width, drag.translation.height)
                    guard versions.count > 1, abs(x) > 2 * abs(y) else { return }
                    show(x < 0 ? at + 1 : at - 1)
                })
            if versions.count > 1 {
                HStack(spacing: 0) {
                    versionButton("Previous Version", "chevron.left") { show(at - 1) }
                        .disabled(at == 0)
                    Text("\(at + 1) of \(versions.count)")
                        .monospacedDigit()
                    versionButton("Next Version", "chevron.right") { show(at + 1) }
                        .disabled(at == versions.count - 1)
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
                // One adjustable element for VoiceOver: swipe up or down to change version.
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Version")
                .accessibilityValue("\(at + 1) of \(versions.count)")
                .accessibilityAdjustableAction { show($0 == .increment ? at + 1 : at - 1) }
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

    /// An arrow beside "2 of 3", with the HIG's minimum touch size.
    private func versionButton(_ title: LocalizedStringKey, _ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .labelStyle(.iconOnly)
                .frame(minWidth: barHeight, minHeight: barHeight)
                .contentShape(.rect)
        }
        .buttonStyle(.borderless)
    }

    /// What the companion added to the pages from this conversation, with Undo.
    private var changesButton: some View {
        Button("Changes", systemImage: "clock.arrow.circlepath") { showingChanges = true }
            .disabled(filedTurns.isEmpty)
    }

    /// The turns something is still filed from.
    private var filedTurns: [Conversation.Turn] {
        companion.conversation.turns.filter { !($0.filed?.isEmpty ?? true) }
    }

    /// Undo goes newest first: what a later message changed waits until that's undone (Kevin, 2026-11-24).
    private func undo(_ line: FilingLine, from turn: UUID) -> some View {
        let waits = companion.conversation.changedLater(line.action, in: turn, elsewhere: companion.others)
        return Button("Undo", systemImage: "arrow.uturn.backward") {
            companion.undoFiling(line.action, from: turn, in: library)
        }
        .labelStyle(.iconOnly)
        .disabled(waits)
        .accessibilityLabel(Text("Undo: \(filed(line))"))
        .accessibilityHint(waits ? Text("Something filed since changed this. Undo that first.") : Text(""))
    }

    /// A filed line, saying so when a later message changed it.
    private func filed(_ line: FilingLine, from turn: UUID) -> Text {
        companion.conversation.changedLater(line.action, in: turn, elsewhere: companion.others)
            ? Text("\(filed(line)) · changed since") : filed(line)
    }

    /// What was filed from the author's message, under the companion's reply to it,
    /// left-aligned with the reply: each page made, type given and field filled, in
    /// their words (New York), with its own Undo.
    private func filed(_ record: FilingRecord, from turn: UUID) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Added to Your Pages", systemImage: "square.stack.3d.up")
            ForEach(library.describe(record), id: \.self) { line in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    filed(line, from: turn)
                    undo(line, from: turn)
                }
            }
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// "New page: Myriddea (Place)", "Casperica · Character", "Casperica · Origin: Myriddea".
    private func filed(_ line: FilingLine) -> Text {
        let page = Text(line.page).font(.authored(.footnote))
        if case .renamed(_, let was, _) = line.action {
            let old = was.isEmpty ? Text("untitled") : Text(was).font(.authored(.footnote))
            return Text("\(page) · renamed, was \(old)")
        }
        if line.isNew {
            let type = line.type.map { Text(" (\(Text($0).font(.authored(.footnote))))") } ?? Text("")
            return Text("New page: \(page)\(type)")
        }
        return Text("\(page) · \(Text(line.detail ?? "").font(.authored(.footnote)))")
    }

    /// No conversation yet: what the companion is doing, centred like iOS's own
    /// waiting and empty states (the download's too).
    @ViewBuilder private var empty: some View {
        switch companion.state {
        case .idle:
            if aboutWorld {
                ContentUnavailableView("Talk About Your World", systemImage: "bubble.left.and.text.bubble.right",
                                       description: Text("The companion knows all your pages. Talk with it about any of them, or all of them."))
            } else {
                ContentUnavailableView("Talk About This Page", systemImage: "bubble.left.and.text.bubble.right",
                                       description: Text("Write a little on this page, and the companion will talk with you about it."))
            }
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
                } actions: {
                    if let fraction = companion.reading { reading(fraction) }
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
                    words(writing)
                        .contentTransition(.opacity)
                        .animation(.easeOut(duration: 0.2), value: writing)
                    if companion.reading == nil {
                        Image(systemName: "circle.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .symbolEffect(.pulse, options: .repeating)
                            .accessibilityLabel("Writing")
                    }
                }
            }
            if let fraction = companion.reading {
                reading(fraction)
            } else if partialReply == nil, partialReasoning == nil, companion.download == nil {
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

    /// While the model reads its prompt before writing (tens of seconds on the 26B): how
    /// far it has got, so it doesn't look stuck (Kevin, 2026-11-24). Having already written
    /// some, it's going on from there after the author left the app.
    private func reading(_ fraction: Double) -> some View {
        let label: LocalizedStringKey = if partialReply != nil || partialReasoning != nil {
            "Picking up where it left off…"
        } else if aboutWorld {
            "Reading your world…"
        } else {
            "Reading your page…"
        }
        return ProgressView(value: fraction) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 0, idealWidth: 240, maxWidth: 240, alignment: .leading)
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
            // With why it couldn't go ahead last time, if it couldn't (too little free space).
            Text("The companion runs on your phone, so nothing you write leaves it. It needs a one-time download"
                 + (companion.downloadSize.map { " of \($0.formatted(.byteCount(style: .file)))" } ?? "") + "."
                 + (companion.downloadNote.map { "\n\n" + $0 } ?? ""))
        } actions: {
            Button("Download") { companion.startDownload(page: subject, in: library) }
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
            // value line always starts at the bar's left edge). The bar keeps one
            // width while the line under it changes (Kevin, 2026-11-24: it grew and
            // shrank with the text), and the digits keep theirs.
            VStack(spacing: 8) {
                ProgressView(value: Double(download.done), total: Double(max(download.total, 1)))
                Text(download.detail)
                    .font(.footnote)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(minWidth: 0, idealWidth: 280, maxWidth: 280)
        }
    }

    private var tryAgain: some View {
        Button("Try Again", systemImage: "arrow.clockwise", action: retry)
            .buttonStyle(.bordered)
    }

    private var resumeDownload: some View {
        Button("Resume Download", systemImage: "arrow.clockwise", action: resume)
            .buttonStyle(.bordered)
    }

    private func retry() { companion.retry(page: subject, in: library) }
    private func resume() { companion.startDownload(page: subject, in: library) }

    /// The message field in Liquid Glass: (unfolded) the menu, the field and
    /// send, one height (the stock glass button styles each come in a different one).
    private var composer: some View {
        GlassEffectContainer {
            HStack(alignment: .bottom, spacing: 8) {
                if !inSheet && !aboutWorld {
                    more
                        .labelStyle(.iconOnly)
                        .frame(width: barHeight, height: barHeight)
                        .glassEffect(.regular.interactive(), in: .circle)
                        .tint(.primary)   // a menu's label takes the tint, not a foreground style
                }
                // What they type is theirs (New York); the placeholder is the app's.
                TextField("Message", text: $message, prompt: Text("Message").font(.body), axis: .vertical)
                    .font(.authored(.body))
                    .lineLimit(1...6)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .frame(minHeight: barHeight)
                    .glassEffect(.regular.interactive(), in: .rect(cornerRadius: barHeight / 2))
                    .disabled(!canWrite)
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
            Button("New Conversation", systemImage: "square.and.pencil") {
                // A world conversation: another one, this one kept in the list; a page's: after confirming.
                if let newConversation { newConversation() } else { confirmingNew = true }
            }
            .disabled(companion.conversation.turns.isEmpty)
            ShareLink("Share Conversation", item: transcript)
                .disabled(companion.conversation.turns.isEmpty)
            if !inSheet && !aboutWorld { changesButton }   // the sheet (Kevin, 2026-11-24) and the world's screen have it beside the menu
            // TRIAL (Kevin, 2026-11-24): the model on its own.
            Toggle(isOn: Binding { companion.plain } set: { companion.plain = $0 }) {
                Label("Plain Model", systemImage: "cube")
                Text("No instructions or pages, only the conversation")
            }
            Section {
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
        let title: String
        if aboutWorld {
            title = library.world.name
        } else {
            title = library.document.title.isEmpty ? "Untitled page" : library.document.title
        }
        let header = "World Editor companion on “\(title)” (\(Companion.modelName)" + (companion.plain ? ", plain model" : "") + ")"
        let turns = companion.conversation.turns.flatMap { turn in
            (turn.question.isEmpty ? [] : ["Companion: \(turn.question)"]) + (turn.answer.map { ["Me: \($0)"] } ?? [])
        }
        return ([header] + turns).joined(separator: "\n\n")
    }

    /// Its reply is waiting for an answer, or nothing has been said yet (the author may begin).
    private var canWrite: Bool {
        companion.conversation.waiting != nil || companion.conversation.turns.isEmpty
    }

    private var canSend: Bool {
        canWrite && !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func send() {
        guard canSend else { return }
        companion.answer(message, page: subject, in: library)
        message = ""
        scrollToEnd()
    }

    private func scrollToEnd() {
        withAnimation { position.scrollTo(edge: .bottom) }
    }
}
