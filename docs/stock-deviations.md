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
| **The conversation's layout**, as ChatGPT and Claude have it (2026-11-27, from comparing chat apps, after a large column with no bubble on each side was tried: "A little odd seeing the side of the text reversed"): the author's messages on the right in a bubble one step lighter than the background, in New York; the companion's replies on the left across the width, at reading size; its thinking and what was filed smaller and grey; Send shown only once there's something to send | No chat view | iOS has none: stock text, arranged by the app. |
| **Swipe between reply versions**, beside the "‹ 2 of 3 ›" arrows | The arrows alone | The versions are Kevin's; the swipe is extra. Flagged; it stays unless he says. |
| **Message bar's circles** (the menu, Attach and Send) | `.buttonStyle(.glass)` and `.glassProminent` | Apple's own glass effect, sized to match the field's height; the menu's whole circle takes taps (Kevin, 2026-11-24, dead taps beside its dots). Stock button styles size themselves differently. |
| **A field's value menu** (a menu around a picker) | A menu-style `Picker` | It holds actions too ("New Place…"), which a picker can't, and keeps a long page name on one line. |
| **The pages list's title row** in New York, folded | iOS's large title in the bar | Kevin asked for it large there; iOS gives a large title no menu, and his world's name is his (New York). |
| **The pages list as a book's contents** (Kevin, 2026-11-27, of the grouped list with its Types section: "This looks awful and not inviting or relaxing or frictionless"): a plain list, no lines between rows, the pages under their kind in the plural (Characters, Places…; untyped last, as Other Pages), each with its first line and no date; types renamed and deleted from the world menu's Types | An inset grouped list of cards, with rows and counts for folders | Stock parts (a plain `List`, section headers, `listRowSeparator`, menus); only the arrangement is ours. |
| **Recently Deleted row** that shows those pages in place | Notes' Recently Deleted folder pushes a list | Not yet tried: a stack of its own in the page's side hid its toolbar (2026-11-24). To do, carefully. |
| **Files waiting to go with a message**, as small capsules above the message bar, each with ✕ (Kevin, 2026-11-25: "pdf or text analysis") | Messages shows attachments inside its field | iOS's text field can't hold attachments; the picker itself is iOS's own (`fileImporter`), and a PDF is read by PDFKit. |
| **The companion as two presentations** (iOS's inspector unfolded, a sheet folded) | One inspector, which iOS turns into a sheet when folded | Its sheet form merged the companion's bar into the page's (Kevin, 2026-11-24, "weird companion header"); a toolbar in its column crashed UIKit while folding (2026-11-23). |
| **The companion's column opens at half the screen's width**, unfolded | iOS's default inspector width | Kevin, 2026-11-24. Only where it opens: iOS keeps its own limits for dragging it. |
| **Dark only** (Kevin, 2026-11-27: "Let's stop offering a light mode I'll never use it") | Following the phone's Light or Dark setting | His call. iOS's own switch for it: Info.plist's `UIUserInterfaceStyle` set to Dark. |
| **One look: iOS's dark greys, warmed very slightly** (background #1C1A17, raised #2C2925, text #E6E1D8, one muted amber accent #D4A373), on every screen; what it doesn't colour (menus, alerts, iOS's own sheets) in iOS's softer elevated grey (Kevin, 2026-11-27: "I don't need multiple themes we need to arrive at one layout", decided from research and other apps, not by him: "experience will be [the arbiter]") | Black backgrounds, white text, blue accent | He found the black "cold and plain"; three switchable looks "don't really work when swapped". Writing and chat apps cluster on a near-neutral dark grey with off-white text and one accent; pure black was called "painful", a warm brown "muddy". Set only in iOS's own ways (`containerBackground` for every navigation container, so the colour reaches behind the bars; the window's background and tint; `tint`), never a coloured panel inside grey bars, which is how gruvbox failed. Contrast: text 13.3:1, accent 7.7:1. Whether it shows under the folded Duo's side column is to be seen on the phone. |
| **The pages list shows for an instant at launch**, then the conversation takes its place without a slide | The app opens straight on the conversation | Its rows grew and wobbled into place the first time they slid in (Kevin, 2026-11-27): iOS sized them for the first time inside the slide. Laid out at launch instead (`RootView.settleList`). |
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
