import XCTest
@testable import WriterCore

/// Try Again keeps each reply: the author can go back to one and go on from it, or delete one.
final class ConversationVersionsTests: XCTestCase {
    private func retried(_ replies: [String]) throws -> Conversation {
        var talk = Conversation(page: UUID())
        talk.ask(replies[0])
        for reply in replies.dropFirst() {
            let old = try XCTUnwrap(talk.retract())
            talk.ask(reply, after: old)
        }
        return talk
    }

    func testTryAgainKeepsEveryReplyAndTheNewOneIsChosen() throws {
        let talk = try retried(["A", "B", "C"])
        XCTAssertEqual(talk.turns.count, 1)
        XCTAssertEqual(talk.turns[0].versions, ["A", "B", "C"])
        XCTAssertEqual(talk.waiting?.question, "C")
    }

    func testTheSameReplyAgainIsntASecondVersion() throws {
        XCTAssertNil(try retried(["A", "A"]).turns[0].versions)
        XCTAssertEqual(try retried(["A", "B", "A"]).turns[0].versions, ["B", "A"])
    }

    func testChoosingAVersionIsWhatTheConversationGoesOnFrom() throws {
        var talk = try retried(["A", "B"])
        let turn = talk.turns[0].id
        talk.choose("Z", in: turn)   // not one of its versions
        XCTAssertEqual(talk.turns[0].question, "B")
        talk.choose("A", in: turn)
        talk.answer("yes")
        XCTAssertEqual(talk.turns[0].question, "A")
        talk.choose("B", in: turn)   // answered: the one they answered stays
        talk.delete("A", in: turn)
        XCTAssertEqual(talk.turns[0].question, "A")
        XCTAssertEqual(talk.turns[0].versions, ["A", "B"])
    }

    func testDeletingAVersion() throws {
        var talk = try retried(["A", "B", "C"])
        let turn = talk.turns[0].id
        talk.delete("C", in: turn)   // the chosen one: the one before it is chosen
        XCTAssertEqual(talk.turns[0].versions, ["A", "B"])
        XCTAssertEqual(talk.turns[0].question, "B")
        talk.delete("A", in: turn)   // one left: no versions to show
        XCTAssertNil(talk.turns[0].versions)
        XCTAssertEqual(talk.turns[0].question, "B")
        talk.delete("B", in: turn)   // never the last
        XCTAssertEqual(talk.turns[0].question, "B")
    }

    func testOnlyAWaitingReplyIsRetracted() {
        var talk = Conversation(page: UUID())
        XCTAssertNil(talk.retract())
        talk.ask("A")
        talk.answer("yes")
        XCTAssertNil(talk.retract())
        XCTAssertEqual(talk.turns.count, 1)
    }

    func testOldConversationsLoad() throws {
        let old = #"{"page":"\#(UUID().uuidString)","turns":[{"id":"\#(UUID().uuidString)","question":"Hi","asked":0}]}"#
        let talk = try JSONDecoder().decode(Conversation.self, from: Data(old.utf8))
        XCTAssertNil(talk.turns[0].versions)
        XCTAssertNil(talk.turns[0].searches)
    }

    /// What each reply searched the author's pages for stays with that reply: kept when Try
    /// Again makes another, saved, and gone with a deleted version.
    func testEachReplyKeepsWhatItSearchedFor() throws {
        var talk = Conversation(page: UUID())
        talk.ask("A", searches: ["Kestrel"])
        XCTAssertEqual(talk.turns[0].searches, ["A": ["Kestrel"]])
        talk.ask("B", after: try XCTUnwrap(talk.retract()), searches: ["Port Vell", "salt tolls"])
        talk.ask("C", after: try XCTUnwrap(talk.retract()))
        XCTAssertEqual(talk.turns[0].searches, ["A": ["Kestrel"], "B": ["Port Vell", "salt tolls"]])
        let saved = try JSONDecoder().decode(Conversation.self, from: JSONEncoder().encode(talk))
        XCTAssertEqual(saved.turns[0].searches, talk.turns[0].searches)
        talk.delete("A", in: talk.turns[0].id)
        XCTAssertEqual(talk.turns[0].searches, ["B": ["Port Vell", "salt tolls"]])
        talk.delete("B", in: talk.turns[0].id)
        XCTAssertNil(talk.turns[0].searches)
        talk.ask("D")
        XCTAssertNil(talk.turns[0].searches)
    }

    /// What each reply looked up on Wikipedia stays with that reply, as its searches do; saved
    /// conversations from before look-ups load without them.
    func testEachReplyKeepsWhatItLookedUp() throws {
        let trireme = LookedUp(query: "trireme rowers", sources: [.init(title: "Trireme", url: URL(string: "https://en.wikipedia.org/wiki/Trireme")!)])
        let peat = LookedUp(query: "how peat forms", sources: [])
        var talk = Conversation(page: UUID())
        talk.ask("A", lookups: [trireme])
        XCTAssertEqual(talk.turns[0].lookups, ["A": [trireme]])
        talk.ask("B", after: try XCTUnwrap(talk.retract()), searches: ["Kestrel"], lookups: [peat])
        talk.ask("C", after: try XCTUnwrap(talk.retract()))
        XCTAssertEqual(talk.turns[0].lookups, ["A": [trireme], "B": [peat]])
        XCTAssertEqual(talk.turns[0].searches, ["B": ["Kestrel"]])
        let saved = try JSONDecoder().decode(Conversation.self, from: JSONEncoder().encode(talk))
        XCTAssertEqual(saved.turns[0].lookups, talk.turns[0].lookups)
        talk.delete("A", in: talk.turns[0].id)
        XCTAssertEqual(talk.turns[0].lookups, ["B": [peat]])
        talk.delete("B", in: talk.turns[0].id)
        XCTAssertNil(talk.turns[0].lookups)
        let old = Data(#"{"page":"\#(UUID())","turns":[{"id":"\#(UUID())","question":"Hi","asked":0}]}"#.utf8)
        XCTAssertNil(try JSONDecoder().decode(Conversation.self, from: old).turns[0].lookups)
    }
}

/// The world's conversations: marked, titled by the author's first words, dated by the last turn.
final class WorldConversationListTests: XCTestCase {
    func testAWorldConversationsTitleDateAndMark() throws {
        var talk = Conversation(page: UUID(), aboutWorld: true)
        XCTAssertNil(talk.title)
        talk.answer("Ilsa and Verran\nand the salt wars", at: Date(timeIntervalSince1970: 10))
        talk.ask("They share a harbour.", at: Date(timeIntervalSince1970: 20))
        XCTAssertEqual(talk.title, "Ilsa and Verran")
        XCTAssertEqual(talk.lastActive, Date(timeIntervalSince1970: 20))
        let again = try JSONDecoder().decode(Conversation.self, from: JSONEncoder().encode(talk))
        XCTAssertTrue(again.aboutWorld)
    }

    func testOlderConversationsAreAPagesOwn() throws {
        let old = #"{"page":"\#(UUID().uuidString)","turns":[]}"#
        XCTAssertFalse(try JSONDecoder().decode(Conversation.self, from: Data(old.utf8)).aboutWorld)
    }
}
