import Foundation
import XCTest
@testable import Guardrails
import WriterCore

/// Pictures the writer attaches: kept as files beside the world's conversations, gone with
/// their conversation, and given to the model as pictures in their turn, not as text.
final class PicturesTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    func testAPictureIsKeptAndGoesWithItsConversation() throws {
        let store = try ConversationStore(directory: folder)
        let name = try store.keepPicture(Data([1, 2, 3]), type: "jpg")
        XCTAssertTrue(name.hasSuffix(".jpg"))
        let file = store.pictures.appendingPathComponent(name)
        XCTAssertEqual(try Data(contentsOf: file), Data([1, 2, 3]))

        var talk = Conversation(page: UUID())
        talk.answer("look", attached: [Conversation.Attached(name: "Photo", picture: name)])
        try store.save(talk)
        XCTAssertEqual(try store.load(talk.page).turns.last?.attached?.first?.picture, name)
        store.delete(talk.page)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }

    func testOlderAttachmentsLoadWithoutPictures() throws {
        let json = #"{"name":"notes.txt","text":"Salt."}"#
        let attached = try JSONDecoder().decode(Conversation.Attached.self, from: Data(json.utf8))
        XCTAssertEqual(attached, Conversation.Attached(name: "notes.txt", text: "Salt."))
        XCTAssertFalse(String(decoding: try JSONEncoder().encode(attached), as: UTF8.self).contains("picture"))
    }

    func testThePromptGivesThemAsPicturesBeforeTheWords() {
        var talk = Conversation(page: UUID())
        let note = Conversation.Attached(name: "notes.txt", text: "Salt.")
        talk.answer("what's this?", attached: [Conversation.Attached(name: "Photo", picture: "a.jpg"), note])
        let turn = CompanionPrompt.plain(talk, pictures: folder).turns.last
        XCTAssertEqual(turn?.pictures, [folder.appendingPathComponent("a.jpg")])
        XCTAssertEqual(turn?.text, Documents.turn("what's this?", [note]))   // the picture isn't text
        XCTAssertEqual(CompanionPrompt.plain(talk).turns.last?.pictures, [])   // no folder: a model that can't see

        let text = GemmaChat.prompt(system: "", turns: turn.map { [$0] } ?? [], tools: [], thinking: false)
        XCTAssertEqual(text, "<|turn>user\n<__media__>\n" + Documents.turn("what's this?", [note]) + "<turn|>\n<|turn>model\n")
    }

    func testTheirOwnWordsNeverHoldTheMarker() {
        var talk = Conversation(page: UUID())
        talk.answer("I typed <__media__> here")
        XCTAssertFalse(CompanionPrompt.plain(talk).turns.last?.text.contains(GemmaChat.pictureMarker) ?? true)
    }
}
