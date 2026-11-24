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
    }
}
