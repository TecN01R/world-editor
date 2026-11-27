# Design specification

This is what every screen is built from and checked against. It comes first: a screen is specified here, built from the shared parts, rendered on the Duo simulator, reviewed (docs/design-review.md), and only then installed.

Kevin, 2026-11-27:
- "when I use this thing I can't know I'm using an app it has to be effortless and just flow without me thinking about it. Everything at my fingertips when I need it exactly when I want it."
- "text has to be consistent, button placement, the text has to look gorgeous like it was printed but also be easy to read chapter upon chapter of text with ease."
- "I want to feel like my world is growing itself and I'm uncovering it."

Kevin doesn't choose between design options. Decisions here come from Apple's guidance for the Duo, research, and how successful apps do it; each names its source. One design ships and is adjusted from what he reports after using it.

**How it's enforced**
- The numbers live in `Packages/WriterKit/Sources/DesignTokens` (tested on Linux: contrast, scales, reading rules).
- The app's fonts, colours and shared parts live in `App/Sources/Design/`. Nothing outside it sets a font, colour, spacing, duration, bar or symbol: `ci/lint_design.sh` fails the push. Files not yet moved over are listed in `ci/design-lint-baseline.txt`, which only shrinks.
- Every screen has a scene (`-scene <name>`, `ci/scenes.txt`) rendered folded, unfolded and at large text on every push that touches the app.

**What's built** (update as work lands)

| Part | State |
|---|---|
| Lint and its baseline | built |
| Tokens, text roles, reading type | install 1 |
| Scenes and the render checks | install 1 |
| Talk and World tabs, navigation, bars, shared parts on every screen | install 2 |
| World's front page (new, only mentioned), search | install 3 |

## Principles

1. **It moves as an iPhone does.** iOS's own tabs, Back, swipe, sheets and overflow, placed by iOS. Nothing hand-made where iOS has a part, so his hands already know it. (Apple, Designing for iPhone Duo: don't override default bar placement.)
2. **The same everywhere.** The same kind of thing looks and sits the same on every screen.
3. **Little on screen.** A screen shows what he's doing. One main action; the rest in iOS's •••, a menu on a heading, a swipe on a row.
4. **His words read like a book.** Everything about his words serves long, comfortable reading.
5. **What the companion did is always visible and undoable,** next to where it happened. (Apple's generative-AI guidance; Microsoft's Guidelines for Human-AI Interaction 9 and 11.)

## Places and movement (install 2)

- **Two tabs, Talk and World,** in a stock `TabView` with no style set. Folded, iOS puts them at the bottom of the side column; unfolded in portrait, in its tab bar. Each tab keeps its own place.
- **Talk:** the list of conversations, newest first, then a conversation. The app opens in the last conversation, at its latest message.
- **World:** the world's front page (its name, with the menu of worlds; Connections; pages by kind), then a page. A name tapped in a page pushes that page; Back retraces the trail.
- **Real navigation only:** a `NavigationStack` per tab with typed routes. No split view and no inspector (every fold and rotation crash in this repo's history was inside iOS's split view).
- **Where he left off:** the tab and both trails are saved per world and restored before the first frame. Edit, Focus and a peeked page are not restored.
- **A page from the conversation:** tapping a page's name under a reply shows the page without leaving: a sheet at half height when folded, beside the conversation when unfolded, where it follows the page his words last went to. (Apple: "Show an additional level of hierarchy on the larger inner display"; "Avoid extreme layout changes as people fold the device".)
- **Read and Edit are the same page.** Edit turns typing on; nothing moves.

## Bars and buttons

The Duo's bar is a column at the right edge when folded and when unfolded in landscape: Back or Close first, then the pinned action, then the rest, with the tabs at the bottom. Unfolded in portrait it is a normal bar. The same items are declared for every pose; iOS places them.

- Every item is `Button(title, systemImage:)`: an item needs a symbol to stand in the column and a title for VoiceOver.
- **Back** is iOS's own. Never hidden, never hand-made.
- **One pinned action** per screen (`topBarPinnedTrailing`), the thing most often wanted there.
- **Everything else** goes in iOS's own overflow (`ToolbarOverflowMenu`). The ellipsis is iOS's; no hand-made ⋯ menu.
- No title in a pushed screen's bar (the page's title is its own first line); the title is still set, for Back's label and VoiceOver.
- While typing, the column has room for Back and two buttons: the conversation and the page ask iOS to keep the buttons before the tabs (`toolbarVerticalCompressionBehavior(.prefersToolbarItems)`).
- Bars and titles are set only by the two scaffolds, `.screen(…)` and `.sheetScaffold(…)`.

| Screen | Pinned | Other | In iOS's ••• |
|---|---|---|---|
| Conversations | New Conversation | | |
| Conversation | New Conversation | unfolded: Show Page | Changes, Look Things Up, Instructions…, Share |
| World | New Page | Connections is the list's first row | Recently Deleted |
| Page, read | Edit | | |
| Page, editing | Read | | Mentions |
| Page, typing | | Focus Mode, Done | |
| Focus | | Exit Focus, Done | (tabs hidden) |
| Page peeked from the conversation | Edit | Close | |

**Sheets:** Close when changes apply at once; Cancel and Done when there's something to save. A sheet with one or two controls keeps its bar across the top. Browsing sheets open at half height and pull up; editing sheets are full height.

**Undo** is one button everywhere, an icon labelled Undo, with a 44 pt target.

## Colour

Grey and white only, iOS's own dark greys one level up (never black), and no accent colour (Kevin, 2026-11-27: "All the mixture of cool and warm colors and random icon colors just seems unprofessional"). Dark only. Contrast is measured (APCA), not judged by eye.

| Token | Value | For |
|---|---|---|
| `surface.base`, `.raised`, `.raised2` | #1C1C1E, #2C2C2E, #3A3A3C | backgrounds; his message's bubble and cards are raised |
| `ink` | #E6E6E6 | his words, and the companion's replies: a soft white that doesn't glare over a long read |
| `ink2` | #C2C2C7 | the app's small text: labels, notes, previews, dates, headings |
| `faint` | iOS's secondary colour | symbols, placeholders, disabled controls, large text only. Too dim for small text |
| `emphasis` | #FFFFFF | controls, Send, the dot on what's new |
| `rule`, `ruleStrong` | ink at 20%, 35% | lines and borders |

- Red only through iOS's delete role.
- A switch keeps iOS's own colour when it's on: tinted white like the other controls, on and off couldn't be told apart (first render, 2026-11-27).
- Links are underlined, not coloured.
- With Increase Contrast on, `ink` is #FFFFFF and `ink2` #DEDEE3.
- No glass in content, and no tint or background on bars: iOS draws its own. (Apple, Liquid Glass guidance.)

## Type

His words are New York wherever they show; the app's own words are San Francisco. New York is set about 1.12 times the size of the San Francisco beside it, so the two look one size. Everything scales with Dynamic Type; nothing is capped.

| Role | Font, size/line | For |
|---|---|---|
| `words.title` | New York Bold 30/36 | a page's title, read or edited |
| `words.body` | New York Regular 19, line by the reading rules | a page's writing; his messages |
| `words.name` | New York Semibold 19/24 | a page's name in a row or card |
| `words.value` | New York Regular 17/22 | a field's value |
| `words.line` | New York Regular 17/22, `ink2` | a preview line or a quote under a name |
| `words.chip` | New York Regular 15/20 | a page's name in a note under a reply |
| `ui.body` | San Francisco 17/22 (replies 17/24) | the companion's replies; the app's sentences |
| `ui.heading` | San Francisco Semibold 17/22, `ink2` | a heading in scrolling content, Title Case |
| `ui.label` | San Francisco 15/20, `ink2` | a field's name, a page's kind, a date |
| `ui.note` | San Francisco 13/18, `ink2` | notes under replies: what was filed, looked up, thought |

- List headers, menus, alerts and bar titles are iOS's own.
- No upper case, no letter-spacing, no other sizes.
- Icons are SF Symbols, outline, one colour, one symbol per meaning (`Symbols`).

## Reading

The page, read or edited, and the conversation share one column.

- **Column:** the width less a 20 pt margin each side, at most 33 em of the body size (627 pt at the default size): about 36 to 40 characters a line folded, 60 to 66 unfolded.
- **Line height by line length** (a longer line needs more room to find the next one): 1.30 times the type size on lines up to 12 em, 1.40 from 16 to 24 em (folded), 1.47 from 28 em (unfolded), easing in a straight line between, so larger text never sets shorter lines. Set as an exact line height on a whole pixel, never as a multiple of the font's own.
- **Hyphenation** more freely on short lines (0.9, 0.6, 0.4 for those three, eased the same way); ragged right; a lone last word pushed out where possible.
- **Between paragraphs** half a line of type (0.5 em); list items a quarter, half after the last.
- **Punctuation** shown as print sets it (`Typeset`: curly quotes, true dashes, ellipses). What he typed is kept as typed.
- **The page, top to bottom:** 8 above the title; 8 to its kind; 16 to its facts (rows 12 apart, columns 16); 24 to the writing; 32 before a heading in the content and 12 after; 32 at the bottom. Read and Edit use the same numbers, and the title wraps in both.
- Focus mode keeps its own layout (docs/focus-mode.md).

## Space, shape and motion

- **Space:** 4, 8, 12, 16, 20, 24, 32. The side margin is 20; between rows 12; between sections 32.
- **Corners:** 12 for a chip, 16 for a card, 20 for a bubble; a shape inside another follows its curve.
- **Touch targets:** at least 44 pt.
- **Motion:** 0.2 s for a small change, 0.3 s for a larger one, 0.6 s (after 0.3 s) for something arriving, such as his sentence landing in a page. With Reduce Motion, a fade.

## Shared parts

| Part | What it is |
|---|---|
| `.screen` | a screen's bar: its title, one pinned action, the overflow |
| `.sheetScaffold` | a sheet's bar and height, for browsing or for editing |
| `PageHeader`, `Facts` | a page's title and kind; its fields as name and value |
| `ReadingText` | his writing set by the reading rules, with links |
| `EntityRow` | a page in a list: its name, one line of its writing, a dot while it's new |
| `EntityCard`, `Chip` | a page in Connections; a page's name where it can be tapped |
| `SectionHeading` | a heading in scrolling content |
| `MessageBubble`, `ReplyText` | what he said (right, raised); what the companion said (left, plain) |
| `NoteLine` | a quiet line under a reply |
| `FilingReceipt` | what his words did: the pages touched as chips and Undo; tapped, every change with its own Undo |
| `Composer` | the message field: +, the field, Send (Stop while it replies) |
| `EmptyState` | what's missing and how it fills: by talking |
| `UndoButton` | Undo |

Stock buttons, lists, menus, alerts and bars are used as they are, never wrapped.

## What the companion did

- Filing happens by itself after every reply; nothing asks for approval.
- While it files: "Adding to your pages…". Then one quiet line under the reply naming the pages, with Undo that never expires. Tapping the line lists each change with its own Undo (Kevin: "each discrete action has its own undo").
- A guess (a "she" or "the guild" sent to the page just talked about) only adds, and shows by the page's name.
- Status lines say what is happening in plain words, never a bare "Thinking…".
- No totals, streaks, progress bars, badges or notifications.

## Names

- A note is a **page**; projects are **worlds**; the two places are **Talk** and **World**; a page is read, or in **Edit** or **Focus** mode.
- An untitled page is "Untitled" everywhere (`Document.displayName`).
- Empty states name what's missing ("No Pages Yet") and say how it fills.

## Accessibility

Dynamic Type on all text; a VoiceOver label on every control; stock controls over custom ones; 44 pt targets; Reduce Motion and Increase Contrast honoured. The render checks fail a control without a label or a target under 44 pt.

## Sources

- Apple: Human Interface Guidelines, "Designing for iPhone Duo", "Launching", "Generative AI"; the Liquid Glass guidance; the iOS 27.1 SDK's own documentation comments.
- Nielsen Norman Group on hidden navigation; Microsoft's Guidelines for Human-AI Interaction.
- Reading research on line length and leading; the APCA contrast method.
- The research report for this app is in git-ignored `private/reports/`.
