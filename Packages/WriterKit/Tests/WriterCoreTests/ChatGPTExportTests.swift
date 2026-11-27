import XCTest
@testable import WriterCore

final class ChatGPTExportTests: XCTestCase {
    /// A conversation as ChatGPT exports it: a tree of messages, the shown branch ending at
    /// `current_node`, with an edited message's older branch left behind.
    private let sample = """
    [{
      "title": "The salt flats",
      "create_time": 1700000000.5,
      "current_node": "d",
      "mapping": {
        "root": {"id": "root", "message": null, "parent": null, "children": ["sys"]},
        "sys": {"id": "sys", "parent": "root", "children": ["ctx"],
                "message": {"author": {"role": "system"}, "content": {"content_type": "text", "parts": [""]}}},
        "ctx": {"id": "ctx", "parent": "sys", "children": ["a", "old"],
                "message": {"author": {"role": "user"}, "create_time": 1700000001,
                            "content": {"content_type": "user_editable_context", "user_profile": "I write fantasy.", "user_instructions": "Be brief."},
                            "metadata": {"is_visually_hidden_from_conversation": true,
                                         "user_context_message_data": {"about_user_message": "I write fantasy.", "about_model_message": "Be brief."}}}},
        "old": {"id": "old", "parent": "ctx", "children": [],
                "message": {"author": {"role": "user"}, "content": {"content_type": "text", "parts": ["An edited-away draft."]}}},
        "a": {"id": "a", "parent": "ctx", "children": ["b"],
              "message": {"author": {"role": "user"}, "create_time": 1700000002,
                          "content": {"content_type": "multimodal_text", "parts": [{"content_type": "image_asset_pointer"}, "Mira cuts salt on the flats."]}}},
        "b": {"id": "b", "parent": "a", "children": ["t"],
              "message": {"author": {"role": "assistant"}, "content": {"content_type": "text", "parts": ["Does she still walk the Salt Road?"]}}},
        "t": {"id": "t", "parent": "b", "children": ["d"],
              "message": {"author": {"role": "tool"}, "content": {"content_type": "text", "parts": ["search results"]}}},
        "d": {"id": "d", "parent": "t", "children": [],
              "message": {"author": {"role": "user"}, "content": {"content_type": "text", "parts": ["  every spring  "]}}}
      }
    },
    {"title": "Only ChatGPT spoke", "current_node": "x", "mapping": {
      "x": {"id": "x", "parent": null, "children": [], "message": {"author": {"role": "assistant"}, "content": {"content_type": "text", "parts": ["Hello"]}}}
    }}]
    """

    func testTheAuthorsOwnSideOfTheShownBranch() throws {
        let export = try ChatGPTExport(Data(sample.utf8))
        XCTAssertEqual(export.conversations.count, 1)   // one where only ChatGPT spoke has nothing of theirs
        let talk = export.conversations[0]
        XCTAssertEqual(talk.title, "The salt flats")
        XCTAssertEqual(talk.created, Date(timeIntervalSince1970: 1700000000.5))
        // Their words in order, trimmed; a picture's part and the edited-away draft left out.
        XCTAssertEqual(talk.turns.map(\.said), ["Mira cuts salt on the flats.", "every spring"])
        // Each with what ChatGPT said just before it (a tool's output isn't that).
        XCTAssertEqual(talk.turns.map(\.answered), [nil, "Does she still walk the Salt Road?"])
        XCTAssertEqual(talk.turns[0].date, Date(timeIntervalSince1970: 1700000002))
    }

    func testTheirCustomInstructionsAreReadButNeverAsAMessage() throws {
        let export = try ChatGPTExport(Data(sample.utf8))
        XCTAssertEqual(export.instructions, ChatGPTExport.Instructions(aboutMe: "I write fantasy.", howToReply: "Be brief."))
        XCTAssertFalse(export.conversations[0].turns.contains { $0.said.contains("fantasy") })
    }

    func testABranchThatLoopsEndsInsteadOfHanging() throws {
        let looped = """
        [{"title": "Loop", "current_node": "a", "mapping": {
          "a": {"id": "a", "parent": "b", "children": [], "message": {"author": {"role": "user"}, "content": {"content_type": "text", "parts": ["one"]}}},
          "b": {"id": "b", "parent": "a", "children": [], "message": {"author": {"role": "user"}, "content": {"content_type": "text", "parts": ["two"]}}}
        }}]
        """
        XCTAssertEqual(try ChatGPTExport(Data(looped.utf8)).conversations.first?.turns.map(\.said), ["two", "one"])
    }

    func testSomethingThatIsntAnExportIsAnError() {
        XCTAssertThrowsError(try ChatGPTExport(Data("{\"not\": \"a list\"}".utf8)))
    }
}
