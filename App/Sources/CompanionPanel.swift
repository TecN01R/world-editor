import PhotosUI
import SwiftUI
import UIKit
import WriterCore

/// The companion, in the world's conversation (`RootView`), laid out as ChatGPT and Claude are: the
/// author's messages on the right in a bubble (New York, their words), the companion's replies on
/// the left across the width (San Francisco), newest at the bottom, and a message field below
/// (typed, or dictated with the keyboard's microphone) whose Send appears once there's something
/// to send. iOS has no chat view: the conversation is stock text, arranged by the app.
struct CompanionPanel: View {
    @Environment(Library.self) private var library
    @Environment(Companion.self) private var companion
    @Environment(\.scenePhase) private var scenePhase
    @State private var message = ""
    /// Files chosen to go with the next message (`AttachedFile`), and why one couldn't be read.
    @State private var attached: [Conversation.Attached] = []
    @State private var attaching = false
    @State private var scanning = false
    /// Pictures for it to see (Kevin, 2026-11-26): from Photos, or the camera; and, until it
    /// can see them, the offer of what it needs.
    @State private var choosingPhotos = false
    @State private var photos: [PhotosPickerItem] = []
    @State private var takingPhoto = false
    @State private var offeringEyes = false
    /// Files being read (a picture of a page takes a moment), by name.
    @State private var beingRead: [String] = []
    @State private var unreadable: String?
    @State private var showingChanges = false
    @State private var editingInstructions = false
    /// Where the conversation is scrolled: the newest message, as in Messages.
    @State private var position = ScrollPosition(edge: .bottom)
    /// One height for the whole message bar: the HIG's minimum touch size,
    /// growing with Dynamic Type.
    @ScaledMetric(relativeTo: .body) private var barHeight: CGFloat = 44
    /// The system's standard margin, for the conversation and the message bar.
    private static let margin: CGFloat = 20
    /// The world conversation shown, where the author starts (`RootView`).
    let worldConversation: UUID
    /// Starts another world conversation (the menu's New Conversation).
    let newConversation: () -> Void
    /// Shows the world's connections (`WorldMapView`), from the bar.
    let openMap: () -> Void

    /// The world's name in the bar, with Connections and the menu.
    var body: some View {
        conversation
            .navigationTitle(library.world.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // The world growing, a tap away; Changes is in the menu (no more than three
                // buttons on a screen, as Apple advises).
                ToolbarItem(placement: .primaryAction) {
                    Button("Connections", systemImage: "point.3.connected.trianglepath.dotted", action: openMap)
                }
                if ready {
                    ToolbarItem(placement: .primaryAction) { more }
                }
            }
    }

    /// What the conversation is about: the world as a whole (a stand-in page, `Library.worldSubject`).
    private var subject: WriterCore.Document { library.worldSubject(worldConversation) }

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
                    // reply, as the companion's doing, in the order it happens: filing runs after
                    // the reply, once the conversation pauses (Kevin, 2026-11-24).
                    if i > 0, let record = turns[i - 1].filed, !record.isEmpty { filed(record, from: turns[i - 1].id) }
                    if let answer = turn.answer { mine(answer, attached: turn.attached ?? []) }
                    // No reply after it (being tried again): under the message meanwhile.
                    if i == turns.count - 1, let record = turn.filed, !record.isEmpty { filed(record, from: turn.id) }
                }
                Live { status }   // as the reply is written, only this redraws, not every message
            }
            .padding(.horizontal, Self.margin)   // the system's standard margin
            .padding(.vertical)
        }
        .scrollEdgeEffectStyle(.soft, for: [.top, .bottom])   // softened under the bars, as the page is
        .defaultScrollAnchor(.bottom)
        .defaultScrollAnchor(.top, for: .alignment)          // a short conversation starts at the top
        // Sending brings the conversation to the bottom (send()); the reply
        // then grows below without moving it, so you read at your own pace (Kevin).
        .defaultScrollAnchor(.top, for: .sizeChanges)
        .scrollPosition($position)
        .scrollDismissesKeyboard(.interactively)
        .lookBackground()
        .overlay {
            Live {   // the download's progress and the first reply redraw only this
                if let download = companion.download {
                    downloading(download)
                } else if companion.needsDownload {
                    downloadOffer
                } else if companion.conversation.turns.isEmpty {
                    empty
                }
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
        .sheet(isPresented: $editingInstructions) { CompanionInstructions().environment(companion) }
    }

    /// Content that reads what changes as a reply is written (each word, the reading bar)
    /// in a view of its own, so only it redraws then, not the whole conversation.
    private struct Live<Content: View>: View {
        @ViewBuilder let content: () -> Content
        var body: some View { content() }
    }

    /// The companion's words: plain text across the width, as ChatGPT and Claude show replies, at
    /// reading size and not dimmed, so a long one reads comfortably.
    private func words(_ text: String) -> some View {
        Text(Self.markdown(text))
            .foregroundStyle(Color(Look.ink))
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// What it looked up in the real world for a reply, under it: the words that left the
    /// phone, exactly, and the articles it read (iOS's own menu of links, opened in Safari).
    @ViewBuilder private func lookedUp(_ lookup: LookedUp) -> some View {
        let label = Label("Searched Wikipedia for \u{201C}\(lookup.query)\u{201D}", systemImage: "globe")
        Group {
            if lookup.sources.isEmpty {
                label
            } else {
                Menu {
                    ForEach(lookup.sources, id: \.url) { source in Link(source.title, destination: source.url) }
                } label: { label }
            }
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .tint(.secondary)
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
            // What it looked up for this reply, under it, and the instructions it added (opening them).
            ForEach(Array((turn.lookups?[turn.question] ?? []).enumerated()), id: \.offset) { _, lookup in
                lookedUp(lookup)
            }
            ForEach(Array((turn.instructions?[turn.question] ?? []).enumerated()), id: \.offset) { _, instruction in
                Button { editingInstructions = true } label: {
                    Label("Added to Instructions: \u{201C}\(instruction)\u{201D}", systemImage: "text.badge.plus")
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
                .tint(.secondary)
                .accessibilityHint("Opens your instructions for the companion")
            }
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

    /// The author's words, under the files they attached to it (Kevin, 2026-11-25: "pdf or text
    /// analysis"): in New York, their words, in a bubble one step lighter than the background, as
    /// every chat app shows the author's side (a large column with no bubble was tried on
    /// 2026-11-27; no successful chat app sets one without a shape).
    private func mine(_ text: String, attached: [Conversation.Attached]) -> some View {
        VStack(alignment: .trailing, spacing: 6) {
            ForEach(Array(attached.enumerated()), id: \.offset) { _, document in
                if let picture = document.picture {
                    PictureThumbnail(url: companion.pictures?.appendingPathComponent(picture))
                } else {
                    Label(document.name, systemImage: "doc.text")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            if !text.isEmpty {
                Text(text)
                    .font(.authored(.body))
                    .foregroundStyle(Color(Look.ink))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color(Look.raised), in: .rect(cornerRadius: 20))
                    .contextMenu { copy(text) }
            }
        }
        // On the right, as every chat app has the author's side (Kevin, 2026-11-27, of them on
        // the left: "A little odd seeing the side of the text reversed").
        .padding(.leading, Self.authorInset)
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    /// How far in from the left the author's messages start, leaving the left to the companion.
    private static let authorInset: CGFloat = 48

    /// The files waiting to go with the next message, each with a way to take it off.
    @ViewBuilder private var waitingFiles: some View {
        if let download = companion.picturesDownload {
            // What it needs to see pictures, coming beside the conversation.
            VStack(alignment: .leading, spacing: 4) {
                Text("Downloading what the companion needs to see pictures")
                ProgressView(value: Double(download.done), total: Double(max(download.total, 1)))
                Text(download.detail).monospacedDigit().foregroundStyle(.secondary)
            }
            .font(.footnote)
        } else if let note = companion.picturesNote {
            Text(note).font(.footnote).foregroundStyle(.secondary)
        }
        if !attached.isEmpty || !beingRead.isEmpty {
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(Array(beingRead.enumerated()), id: \.offset) { _, name in
                        HStack(spacing: 4) {
                            ProgressView().controlSize(.mini)
                            Text("Reading \u{201C}\(name)\u{201D}\u{2026}").lineLimit(1)
                        }
                        .font(.footnote)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.fill.secondary, in: .capsule)
                    }
                    ForEach(Array(attached.enumerated()), id: \.offset) { i, document in
                        HStack(spacing: 4) {
                            if let picture = document.picture {
                                PictureThumbnail(url: companion.pictures?.appendingPathComponent(picture), height: 28)
                            } else {
                                Label(document.name, systemImage: "doc.text")
                                    .lineLimit(1)
                            }
                            Button("Remove \(document.name)", systemImage: "xmark.circle.fill") { remove(at: i) }
                                .labelStyle(.iconOnly)
                                .foregroundStyle(.secondary)
                        }
                        .font(.footnote)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.fill.secondary, in: .capsule)
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
    }

    /// Takes a waiting file off; a picture's own file goes too, as nothing else has it.
    private func remove(at i: Int) {
        if let picture = attached[i].picture, let folder = companion.pictures {
            try? FileManager.default.removeItem(at: folder.appendingPathComponent(picture))
        }
        attached.remove(at: i)
    }

    /// Photos or the camera, once it can see pictures; until then, the offer of what it needs.
    private func pickPictures(_ show: Binding<Bool>) {
        if companion.seesPictures { show.wrappedValue = true } else { offeringEyes = true }
    }

    /// Pictures chosen in Photos, kept to go with the next message.
    private func attachPhotos(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        photos = []
        for item in items {
            read("Photo") {
                guard let data = try await item.loadTransferable(type: Data.self), let image = UIImage(data: data)
                else { throw AttachedFile.Unreadable(name: "Photo") }
                return try keep(image, named: "Photo")
            }
        }
    }

    /// `image` kept as a picture to go with the next message.
    private func keep(_ image: UIImage, named name: String) throws -> Conversation.Attached {
        guard let jpeg = AttachedPicture.jpeg(image), let picture = companion.keepPicture(jpeg, named: name)
        else { throw AttachedFile.Unreadable(name: name) }
        return picture
    }

    /// The files the picker returned, read into text; one that can't be read is said why.
    private func attach(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result else { return }
        for url in urls {
            read(url.lastPathComponent) { try await AttachedFile.read(url) }
        }
    }

    /// Pages from the scanner, read into text as one file.
    private func attachScan(_ pages: [CGImage]) {
        guard !pages.isEmpty else { return }
        let name = "Scanned Document"
        read(name) { try await AttachedFile.scanned(pages, name: name) }
    }

    /// Reads `name` with `load`, shown as being read meanwhile; then it waits to go, or is said why it can't.
    private func read(_ name: String, _ load: @escaping () async throws -> Conversation.Attached) {
        beingRead.append(name)
        Task {
            defer { if let i = beingRead.firstIndex(of: name) { beingRead.remove(at: i) } }
            do { attached.append(try await load()) } catch {
                unreadable = (error as? LocalizedError)?.errorDescription ?? "\u{201C}\(name)\u{201D} couldn\u{2019}t be read."
            }
        }
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
    /// their words, with its own Undo.
    private func filed(_ record: FilingRecord, from turn: UUID) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Added to Your Pages", systemImage: "square.stack.3d.up")
            ForEach(library.describe(record), id: \.self) { line in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    // A line opens its page: what was just added, where it now lives (Kevin,
                    // 2026-11-27, of watching the world grow).
                    if let id = line.action.page, library.pages.contains(where: { $0.id == id }) {
                        Button { library.selection = id } label: { filed(line, from: turn) }
                            .buttonStyle(.plain)
                            .accessibilityHint("Opens \(line.page)")
                    } else {
                        filed(line, from: turn)
                    }
                    undo(line, from: turn)
                }
            }
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// "New page: Myriddea (Place)", "Casperica · Character", "Casperica · Origin: Myriddea":
    /// page names and filed words in New York, types and fields in San Francisco. The page
    /// name is in the accent colour, as a tap opens the page.
    private func filed(_ line: FilingLine) -> Text {
        func authored(_ s: String) -> Text { Text(s).font(.authored(.footnote)) }
        let page: Text = authored(line.page).foregroundStyle(Color(Look.accent))
        if case .renamed(_, let was, _) = line.action {
            return Text("\(page) · renamed, was \(was.isEmpty ? Text("untitled") : authored(was))")
        }
        if line.isNew {
            return Text("New page: \(page)\(line.type.map { " (\($0))" } ?? "")")
        }
        let words = line.words.map { words in
            Text("\(authored(words))\(line.was.map { Text(" (was \(authored($0)))") } ?? Text(""))")
        }
        let detail = switch (line.label, words) {
        case let (label?, words?): Text("\(label): \(words)")
        case (let label?, nil): Text(label)
        case (nil, let words?): words
        case (nil, nil): Text("")
        }
        return Text("\(page) · \(detail)")
    }

    /// No conversation yet: what the companion is doing, centred like iOS's own
    /// waiting and empty states (the download's too).
    @ViewBuilder private var empty: some View {
        switch companion.state {
        case .idle:
            ContentUnavailableView("Your World", systemImage: "bubble.left.and.text.bubble.right",
                                   description: Text("Write about it however it comes out, and talk it through with the companion."))
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
                // As it's written, with a pulsing dot while it isn't done yet (as the AI apps
                // show it). No fade per word: it faded the whole reply each time.
                VStack(alignment: .leading, spacing: 8) {
                    words(writing)
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

    /// While the model reads its prompt before writing (seconds, more on a long one): how
    /// far it has got, so it doesn't look stuck (Kevin, 2026-11-24). Having already written
    /// some, it's going on from there after the author left the app.
    private func reading(_ fraction: Double) -> some View {
        let label: LocalizedStringKey = if partialReply != nil || partialReasoning != nil {
            "Picking up where it left off…"
        } else {
            "Reading your world…"
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

    /// The message field in Liquid Glass: attach, the field and send, one height (the
    /// stock glass button styles each come in a different one); the files waiting to go
    /// above it.
    private var composer: some View {
        VStack(alignment: .leading, spacing: 8) {
            waitingFiles
            GlassEffectContainer {
                HStack(alignment: .bottom, spacing: 8) {
                    // Something for it to see or read (Kevin, 2026-11-25; 2026-11-26: pictures,
                    // scans and pictures of pages too): pictures from Photos or the camera, pages
                    // scanned with iOS's own scanner, or a file from iOS's picker.
                    Menu {
                        if companion.picturesDownloadSize != nil {
                            Button("Photo Library", systemImage: "photo.on.rectangle") { pickPictures($choosingPhotos) }
                            if CameraPicker.isAvailable {
                                Button("Take Photo", systemImage: "camera") { pickPictures($takingPhoto) }
                            }
                        }
                        if DocumentScanner.isSupported {
                            Button("Scan Documents", systemImage: "doc.viewfinder") { scanning = true }
                        }
                        Button("Choose File", systemImage: "folder") { attaching = true }
                    } label: {
                        Label("Attach", systemImage: "plus")
                            .labelStyle(.iconOnly)
                            .frame(width: barHeight, height: barHeight)
                            .contentShape(.circle)
                    }
                    .glassEffect(.regular.interactive(), in: .circle)
                    .tint(.primary)
                    .disabled(!canWrite)
                    .fileImporter(isPresented: $attaching, allowedContentTypes: AttachedFile.types,
                                  allowsMultipleSelection: true, onCompletion: attach)
                    .fullScreenCover(isPresented: $scanning) {
                        DocumentScanner { pages in
                            scanning = false
                            attachScan(pages)
                        }
                        .ignoresSafeArea()
                    }
                    .photosPicker(isPresented: $choosingPhotos, selection: $photos, maxSelectionCount: 5, matching: .images)
                    .onChange(of: photos) { attachPhotos(photos) }
                    .fullScreenCover(isPresented: $takingPhoto) {
                        CameraPicker { image in
                            takingPhoto = false
                            if let image { read("Photo") { try keep(image, named: "Photo") } }
                        }
                        .ignoresSafeArea()
                    }
                    .alert("See Pictures?", isPresented: $offeringEyes) {
                        Button("Download") { companion.downloadPictures() }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("To see pictures, the companion needs a one-time download of "
                             + "\((companion.picturesDownloadSize ?? 0).formatted(.byteCount(style: .file))), over Wi\u{2011}Fi. "
                             + "Its model was trained on words, so how well it sees is for you to judge.")
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
                    // Only when there's something to send, as ChatGPT and Messages have it.
                    if canSend {
                        Button(action: send) {
                            Image(systemName: "arrow.up")
                                .fontWeight(.semibold)
                                .foregroundStyle(Color(Look.background))   // 7.7:1 on the accent
                                .frame(width: barHeight, height: barHeight)
                        }
                        .glassEffect(.regular.tint(Color(Look.accent)).interactive(), in: .circle)
                        .accessibilityLabel("Send")
                        .transition(.scale.combined(with: .opacity))
                    }
                }
                .animation(.smooth(duration: 0.2), value: canSend)   // Send grows in, rather than popping
            }
        }
        .alert("Couldn\u{2019}t Attach the File", isPresented: Binding { unreadable != nil } set: { if !$0 { unreadable = nil } }) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(unreadable ?? "")
        }
        .padding(.horizontal, Self.margin)
        .padding(.vertical)
    }

    /// Everything that isn't the conversation itself. What it's running heads the menu, as a
    /// menu's own title (a line to read; a menu has no plain text).
    private var more: some View {
        Menu {
            Section([Companion.modelName, companion.modelVersion, Self.appVersion].compactMap { $0 }.joined(separator: " · ")) {
                items
            }
        } label: { Label("More", systemImage: "ellipsis") }
    }

    @ViewBuilder private var items: some View {
        // Another world conversation, this one kept in the list.
        Button("New Conversation", systemImage: "square.and.pencil", action: newConversation)
            .disabled(companion.conversation.turns.isEmpty)
        ShareLink("Share Conversation", item: transcript)
            .disabled(companion.conversation.turns.isEmpty)
        changesButton
        Toggle(isOn: Binding { companion.looksUp } set: { companion.looksUp = $0 }) {
            Label("Look Things Up", systemImage: "globe")
            Text("On Wikipedia, for questions about the real world")
        }
        Button("Instructions…", systemImage: "text.document") { editingInstructions = true }
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
        let header = "World Editor companion on “\(library.world.name)” (\(Companion.modelName))"
        let turns = companion.conversation.turns.flatMap { turn -> [String] in
            let files = (turn.attached ?? []).map { "[Attached: \($0.name)] " }.joined()
            return (turn.question.isEmpty ? [] : ["Companion: \(turn.question)"]) + (turn.answer.map { ["Me: " + files + $0] } ?? [])
        }
        return ([header] + turns).joined(separator: "\n\n")
    }

    /// Its reply is waiting for an answer, or nothing has been said yet (the author may begin).
    private var canWrite: Bool {
        companion.conversation.waiting != nil || companion.conversation.turns.isEmpty
    }

    private var canSend: Bool {
        canWrite && (!message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attached.isEmpty)
    }

    private func send() {
        guard canSend else { return }
        companion.answer(message, attached: attached, page: subject, in: library)
        message = ""
        attached = []
        scrollToEnd()
    }

    private func scrollToEnd() {
        withAnimation { position.scrollTo(edge: .bottom) }
    }
}
