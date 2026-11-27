# Design rules

These rules apply to every screen and every change. Kevin, 2026-11-27:
- "when I use this thing I can't know I'm using an app it has to be effortless and just flow without me thinking about it. Everything at my fingertips when I need it exactly when I want it."
- "The UI feels inconsistent between sections and purposes with different headers body size button size button placement etc."
- "the text has to look gorgeous like it was printed but also be easy to read chapter upon chapter of text with ease."

Kevin doesn't choose between design options. Rules come from research (private/reports/), from how successful apps do it, and from what he reports after using the app. One design ships, and it is adjusted from there.

## Principles

1. **The same everywhere.** The same kind of thing looks and sits the same on every screen, so his hands learn it once.
2. **Little on screen.** A screen shows what he's doing. Other actions appear where and when they're needed: a menu on a heading, a tap on a name, a swipe on a row.
3. **His words read like a book.** Everything below about his words serves long, comfortable reading.

## Colour

Grey and white only, in iOS's own colours (`Look`), as ChatGPT has it:
- **Backgrounds:** the elevated greys, never black.
- **Controls:** every one is white.
- **No accent colour.** Links are underlined, and Send is a white circle.
- **Red:** only for deleting.
- **His words:** a soft off-white (`Look.ink`), never pure white, which glares in long reading.

## His words (New York)

| What | Style |
|---|---|
| A page's writing, read or edited | `PageEditor.font`: New York 19 pt, scaled with Dynamic Type. Line height ×1.35, 14 pt between paragraphs, light hyphenation, ragged right. |
| A page's title, read or edited | `PageEditor.titleFont`: New York 34 pt bold |
| His messages, and field values | `.authored(.body)` |
| A page's name in a row or card | `.authored(.headline)` |
| A preview line or a quote | `.authored(.subheadline)` |

- **Read and Edit are the same page.** The title, the kind under it, the facts and the writing keep the same place, size and spacing; only whether he can type changes.
- **Punctuation:** shown as print sets it, with curly quotes, true dashes and ellipses (`Typeset`). What he typed is kept as he typed it.
- **Measure:** at most 33 em of the page font, about 66 characters a line (`Look.column`).

## The app's own words (San Francisco)

| What | Style |
|---|---|
| Text | `.body` |
| Labels and secondary lines (field names, a page's kind, dates) | `.subheadline`, grey |
| Notes under replies (filed lines, look-ups, versions, thinking) and file chips | `.footnote`, grey |
| Headings in lists | iOS's own list header |
| Headings in scrolling content | `.headline`, grey, Title Case |

- No `.caption`.
- No upper case or letter-spacing.

## Layout

- **One margin:** 20 pt at the sides (`Look.margin`).
- **One reading column:** `Look.column(width)`, the smaller of the width less the margins and 33 em of the page font. The page editor, the page read, and the conversation and its message bar all use it. Focus mode keeps its own layout (docs/focus-mode.md).
- **Lists for browsing:** plain, without separators, sharing one page row (name, then its first line). Settings sheets stay Forms.

## Buttons and bars

**Leading** is for getting around only:
- the drawer button (folded);
- Back, naming where it goes;
- Close, Cancel or Exit Focus.

**Trailing pinned** holds the screen's one main action, as an icon:
| Screen | Main action |
|---|---|
| Conversation | New Conversation (`square.and.pencil`) |
| Pages | New Page (`doc.badge.plus`) |
| A page, read | Edit (`pencil`) |
| A page, edited | Read (`book`) |
| Connections | none |

Everything else goes in one **⋯ More** menu, trailing.

- **While typing:** Focus and Done.
- **Bars hold icons only.** iOS's own Edit button is the one exception.
- **Sheets:**
  - ✕ Close when changes apply at once; ✕ Cancel and ✓ Done when there's something to save.
  - Every sheet keeps its bar across the top (`toolbarVerticalBehavior(.disabled)`), not in the folded Duo's side column.
  - Height: medium or large for browsing, large for editing.
- **Undo** has one look everywhere: an icon button labelled Undo.

## Names

- **An untitled page** is "Untitled" everywhere (`Document.displayName`).
- **Screens:**
  - the conversation is titled by the world's name;
  - Pages is "Pages";
  - Connections is "Connections";
  - a page has no bar title, since its title is the page's own.
- **Empty states** name what's missing ("No Pages Yet") and say how it fills: by talking.
