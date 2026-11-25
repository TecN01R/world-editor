# Where the app differs from stock iOS

Kevin, 2026-11-24: "I want to deviate as little from stock as possible, so flag
anywhere we deviate from a functionality that isn't provided by stock." This is
that list. Anything new that isn't iOS's own component or behaviour gets a line
here, with why, and is named to Kevin when it ships.

"Stock" means iOS's own component, used as it comes, in iOS's place for it.
Built from stock parts but arranged or behaving our own way still counts as a
deviation.

## Custom, and why

| What | What iOS has | Why it stays |
|---|---|---|
| **Format bar** floating above the keyboard (Bold, Italic, two lists, Open for a link) | The keyboard's accessory bar; the edit menu's Format; the "Aa" formatting panel (`UITextFormattingViewController`) | Kevin allows this one. The accessory bar counts as keyboard on the Duo: it shortens the side column and pushes toolbar items into "•••". Its actions are iOS's own (`toggleBoldface`, `toggleItalics`); lists are the page's, undoable. iOS has no public call to show its "Aa" panel from an app's button. |
| **Editing toolbar** (Kevin, 2026-11-24): while the page's own writing, title or a field has the keyboard, folded and unfolded show the same three: Back or the sidebar button, Focus, and Done (blue); the companion and Mentions wait for the keyboard to go down | Notes keeps its bar and adds Done | His call. Built from stock toolbar items; only what shows when is ours. |
| **The edit menu's Format** holds Bold, Italic, Bulleted List and Numbered List (Kevin, 2026-11-24: "Perfect") | iOS's Format: Bold, Italic, and More… (its whole Format panel: fonts, sizes, colours, text styles, alignment) | Pages keep only these; what More… offered was lost on the next redraw. iOS's own Bold and Italic, through the text view's public edit-menu delegate; its panel, if reached another way, offers only text styles and lists. |
| **`@` mention menu** (a popover of pages as you type `@`) | No public mention or autocomplete API for text views (Notes' `>>` is private) | Nothing stock to use. Built from a stock popover and list cells. |
| **Title field and fields above the writing**, inside the page's text view | Notes uses the first line as the title | The page's name and its fields are separate from the writing by design. |
| **Empty fields hidden**, listed in Add Field's menu (one picked shows, ready to fill in) | Contacts shows only what's filled in and offers the rest in its Edit mode | Kevin, 2026-11-24: not every field of a type fits every page, and empty ones cluttered it. A page has no Edit mode, so the stock menu under the fields stands in for it. |
| **Focus mode** (one paragraph per page, sized to fit, never scrolls) | Nothing like it | Kevin's own feature (`docs/focus-mode.md`). |
| **Focus mode's paragraph dots** (`ParagraphRail`) | `UIPageControl`, vertical | Not yet swapped; the page control would bring scrubbing and VoiceOver's adjustable action. To do. |
| **Changes timeline** (a rail with a point per message) | A grouped list | Kevin: "it should be a timeline". |
| **Download bar's line under it**, centred | `ProgressView`'s value label, at the bar's left edge | Kevin, 2026-11-24: the bar's width moved with the text. |
| **Model download** (Wi-Fi only, resumes, repacks as it goes) | A background `URLSession` or Background Assets | The engine repacks the model while it streams, to avoid needing 29 GB at once; a stock download would need that done shard by shard. |
| **Chat bubbles** for the author's messages | No chat view | iOS has none; a plain fill (not glass, which Apple keeps off content). |
| **Swipe between reply versions**, beside the "‹ 2 of 3 ›" arrows | The arrows alone | The versions are Kevin's; the swipe is extra. Flagged; it stays unless he says. |
| **Message bar's circles** (the menu, Attach and Send) | `.buttonStyle(.glass)` and `.glassProminent` | Apple's own glass effect, sized to match the field's height; the menu's whole circle takes taps (Kevin, 2026-11-24, dead taps beside its dots). Stock button styles size themselves differently. |
| **A field's value menu** (a menu around a picker) | A menu-style `Picker` | It holds actions too ("New Place…"), which a picker can't, and keeps a long page name on one line. |
| **The pages list's title row** in New York, folded | iOS's large title in the bar | Kevin asked for it large there; iOS gives a large title no menu, and his world's name is his (New York). |
| **World conversations in the pages list's place**, with a "Pages" button back | A navigation stack in the sidebar (real Back, swipe back) | Not yet tried: a stack of its own in the page's side hid its toolbar (2026-11-24). To do, carefully. |
| **Type and Recently Deleted rows** that filter the list in place | Notes' folders push a filtered list | Same as above. |
| **Files waiting to go with a message**, as small capsules above the message bar, each with ✕ (Kevin, 2026-11-25: "pdf or text analysis") | Messages shows attachments inside its field | iOS's text field can't hold attachments; the picker itself is iOS's own (`fileImporter`), and a PDF is read by PDFKit. |
| **The companion as two presentations** (iOS's inspector unfolded, a sheet folded) | One inspector, which iOS turns into a sheet when folded | Its sheet form merged the companion's bar into the page's (Kevin, 2026-11-24, "weird companion header"); a toolbar in its column crashed UIKit while folding (2026-11-23). |
| **The companion's column opens at half the screen's width**, unfolded | iOS's default inspector width | Kevin, 2026-11-24. Only where it opens: iOS keeps its own limits for dragging it. |
| **Pasting and dropping as plain text** | Rich paste | Other apps' fonts and colours (black text, unreadable in dark mode) never get in. Through iOS's paste delegate. |

## Made stock on 2026-11-24 (the audit)

- The split view and the companion: iOS lays them out; the app no longer moves the
  pages list while the Duo rotates, folds or unfolds. The companion's column is dragged
  within iOS's own limits (the app's 320–640 points were dropped, 2026-11-24).
- Back and the sidebar button never disappear while typing.
- Bold and Italic through iOS's own commands (with Undo).
- Paste and drop through iOS's paste delegate.
- A link's own long-press menu has Open.
- The model and version as the companion menu's title, not a disabled button.
- The author's bubbles in a plain fill, not glass.
