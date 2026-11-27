import XCTest
@testable import DesignTokens

final class TextRoleTests: XCTestCase {
    private let authorsRoles: [TextRole] = [
        .words.title, .words.body, .words.name, .words.value, .words.line, .words.chip,
    ]
    private let appsRoles: [TextRole] = [.ui.body, .ui.reply, .ui.heading, .ui.label, .ui.note]

    func testTheRolesAreTheSpecificationsNumbers() {
        XCTAssertEqual(TextRole.words.title, TextRole(.newYork, .bold, 30, line: 36, as: .title1))
        XCTAssertEqual(TextRole.words.body, TextRole(.newYork, .regular, 19, line: nil, as: .body))
        XCTAssertEqual(TextRole.words.name, TextRole(.newYork, .semibold, 19, line: 24, as: .headline))
        XCTAssertEqual(TextRole.words.value, TextRole(.newYork, .regular, 17, line: 22, as: .subheadline))
        XCTAssertEqual(TextRole.words.line, TextRole(.newYork, .regular, 17, line: 22, as: .subheadline))
        XCTAssertEqual(TextRole.words.chip, TextRole(.newYork, .regular, 15, line: 20, as: .footnote))
        XCTAssertEqual(TextRole.ui.body, TextRole(.sanFrancisco, .regular, 17, line: 22, as: .body))
        XCTAssertEqual(TextRole.ui.reply, TextRole(.sanFrancisco, .regular, 17, line: 24, as: .body))
        XCTAssertEqual(TextRole.ui.heading, TextRole(.sanFrancisco, .semibold, 17, line: 22, as: .headline))
        XCTAssertEqual(TextRole.ui.label, TextRole(.sanFrancisco, .regular, 15, line: 20, as: .subheadline))
        XCTAssertEqual(TextRole.ui.note, TextRole(.sanFrancisco, .regular, 13, line: 18, as: .footnote))
    }

    func testSizesStepDown() {
        XCTAssertGreaterThan(TextRole.words.title.size, TextRole.words.body.size)
        XCTAssertGreaterThanOrEqual(TextRole.words.body.size, TextRole.words.name.size)
        XCTAssertGreaterThanOrEqual(TextRole.words.name.size, TextRole.words.line.size)
        XCTAssertGreaterThan(TextRole.words.line.size, TextRole.ui.label.size)
        XCTAssertGreaterThan(TextRole.ui.label.size, TextRole.ui.note.size)
    }

    func testTheFaceSaysWhoseWordsTheyAre() {
        for role in authorsRoles { XCTAssertEqual(role.face, .newYork, "\(role)") }
        for role in appsRoles { XCTAssertEqual(role.face, .sanFrancisco, "\(role)") }
    }

    func testNewYorkIsSetLargerThanTheSanFranciscoBesideIt() {
        // New York's letters are smaller for their point size: about 1.12 times makes the two
        // look one size. Each pair grows together too, so they still do at every text size.
        let beside: [(TextRole, TextRole)] = [
            (.words.body, .ui.body), (.words.name, .ui.heading), (.words.value, .ui.label),
            (.words.line, .ui.label), (.words.chip, .ui.note),
        ]
        for (words, ui) in beside {
            XCTAssertEqual(words.size / ui.size, 1.12, accuracy: 0.06, "\(words.size) beside \(ui.size)")
            XCTAssertEqual(words.scalesAs, ui.scalesAs, "\(words.size) beside \(ui.size)")
        }
    }

    func testOnlyThePagesWritingTakesItsLineHeightFromTheColumn() {
        for role in authorsRoles + appsRoles {
            XCTAssertEqual(role.lineHeight == nil, role == .words.body, "\(role)")
        }
    }

    func testAReplyIsBodyTextWithMoreRoomBetweenLines() throws {
        let body = TextRole.ui.body, reply = TextRole.ui.reply
        XCTAssertEqual(reply.weight, body.weight)
        XCTAssertEqual(reply.size, body.size)
        XCTAssertEqual(reply.scalesAs, body.scalesAs)
        XCTAssertGreaterThan(try XCTUnwrap(reply.lineHeight), try XCTUnwrap(body.lineHeight))
    }
}
