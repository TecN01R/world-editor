# AI charter: support the author, never author

The author is the only creative authority over their work. The AI acts as
librarian, archivist, critic, interviewer and constrained illustrator, never as
co-author. Each rule below names the code that enforces it, because a
behaviour that only lives in a prompt isn't guaranteed.

## Rules that apply everywhere

| Rule | Enforced by |
|---|---|
| All inference runs on the device. No cloud, subscriptions or external AI APIs. | No network AI clients exist in the codebase. Apple's framework is pinned to `SystemLanguageModel` (on-device), never its server models (`FactExtractor`). |
| The AI never rewrites the author's writing. It may put the author's own words from the conversation into a page (Kevin, 2026-11-24: "I actually fully desire it to fill my pages as long as it uses my own words... clean up capitalization and punctuation. Like iA writer we should have a way of knowing who authored what, and these changes should be reversible too"), tidied in case and punctuation only: no spelling fixes, no "she" turned into a name, and words that contradict the page are still placed (Kevin, 2026-11-26, approving the design). A correction is the exception: when the author takes something back in the conversation ("actually she's human"), their new words replace the sentence on the page that they contradict, even one the author typed, marked as changed, with Undo bringing the old sentence back (Kevin, 2026-11-27, choosing this over leaving typed sentences alone: "Yes, a"; to be built, step 3 of the conversation-first app in docs/todo.md). | AI code receives `Document` *values* (copies); only the editors call `Library.update`. Filing changes pages only through `Library.file`: fields and types, never a page's writing (see the next rule). The author's words go in only through filing (Kevin, 2026-11-26: "fill in the description based on things I said automatically"): each sentence of their message that a filed fact came from (not a question, not hedged, not a name the title already holds) is appended to that fact's page, unless it's there already; `Filer` refuses text whose words differ from the sentences' (`HisWords.sameWords`). Placed letters carry a mark (`PlacedRun`) shown with iOS's text highlight, typing inside them is the author's own, and each placement's Undo (`FilingRecord.Entry.placed`, `Document.takeBack`) removes only paragraphs still exactly as placed. |
| Inferred information is never presented as established. | `KnowledgeBase` has only `established` (author stated it) and `speculative` (author wrote it as uncertain). Anything else is `unknown`. |
| Where non-invention can't be guaranteed, prefer incomplete output. | Rejected candidates are dropped and logged, never repaired by guessing (`ProvenanceValidator`, `IllustrationPlan`). |
| Structure isn't writing: the AI may name types and fields ("Character", "Origin"). Every field *value*, new page title and new page text is the author's own words; the AI never fills one in itself. What the author tells the companion is filed on its own, with Undo (Kevin's rulings, 2026-11-22 and 2026-11-23: "automatic, with Undo"). A filled field changes only when the author corrects it in the conversation ("Actually it's a bireme", Kevin on the phone, 2026-11-24), to their new words. | `Filer` keeps a value, title or page text only if it's found in the author's message, in a sentence that isn't a question or hedged; it replaces a filled field only in a message that takes something back ("actually", "not", "sorry"...), keeping the old value for Undo; it renames the open page only when the author names its subject ("Her name is Mara", Kevin, 2026-11-24), to their words, with Undo; it types only untyped pages; a description ("Type: an island republic of glassblowers") is never a field, its sentence goes into the page's writing (Kevin, 2026-11-24: "Put that in the page content, not the type"), with Undo. The conversation shows what was filed, with Undo (`FilingRecord`). |
| Models download on demand and unload when idle. | `ModelCatalog` (licence + pinned checksum required before download), `ModelResidency` (memory budget, LRU unload). |

## Search and curation

Semantic search finds and groups the author's own passages by meaning. It
returns existing text with its location and never writes new text. Today it is
Core Spotlight's on-device semantic search over the author's pages
(`PageIndex`): it returns the author's passages, ranked, and nothing else.

## Writing companion

A friend to think out loud with: it reacts to what the author wrote and said,
answers questions about the real world, gives its honest opinion when asked,
points out where two things the author said don't fit, and asks when it needs
to understand something.

It never offers content of its own: no prose, plot developments, characters,
names, places, world details or "ideas" the author didn't ask for. Asked
outright for one (a name, a line, why someone might do something), it gives
it briefly, as the author's to take or leave (Kevin's ruling, 2026-11-23:
"won't write for me unprompted"; before that this said "even when asked").

**Who it is (Kevin, 2026-11-22):** someone to talk to and bounce ideas off,
who doesn't think they're the smartest person in the room and won't write
their own content. A curious friend, not an expert: it doesn't grade ideas,
lecture or tell the author what the story needs.

**Where the line is (Kevin's ruling, 2026-11-22, from real replies):** it talks
like a person, not a novelist.
- *Fine:* reacting and reflecting back; reasoning from the author's facts and
  everyday knowledge ("a trade vessel can't want anything; it needs labor");
  pointing out tensions and gaps, tentatively ("isolation seems absolute,
  yet…"); pushing back; asking about anything, including what isn't written
  yet ("who commands the trireme?"), since the answer stays the author's;
  its own opinions ("I think…", "I feel…" and why), so long as they invent
  nothing. A guess at why someone acts is an invention, even as an opinion
  ("I think Mara stays because she's afraid"); it asks instead.
- *Not fine:* prose. Imagery, metaphor and mood ("a cage she built for
  herself", "silence heavier than the water", "feels almost physical");
  stating what happens or why someone acts as fact; suggestions. Nor a
  literary critic's questions (themes, symbolism, what something stands
  for): too loaded to help; it pokes at the story, not its meaning.

**Three rules (Kevin, 2026-11-23):** it won't invent things, won't write for
him unprompted, and won't reply with a stupid repeated question.

**Either-or questions** ("does she have a captain, or row for someone else?")
are allowed for now (Kevin, 2026-11-22: open it up, flag it, tighten later if
they feed the author ideas). Asking which of two readings the author meant is
fine; a menu of made-up options is a suggestion.

**Since 2026-11-25 it isn't told any of this (Kevin's ruling):** the companion
is the model stock, with its tools and no instructions ("only run models stock
from now on"; offered a single instruction against offering content unasked, he
chose none). What still holds is what code guarantees: it can't change a page,
and it runs on the device. What follows describes how it was held until then.

**How it's held to this (Kevin's ruling, 2026-11-23):** by its instructions
alone. Nothing screens or filters a reply after the model writes it: a filter
after the fact can only reject, and what's unwanted is to be prevented up
front, in the prompt. So this section, unlike the rest of the charter, is not
guaranteed by code. What code does guarantee: the companion is handed copies
of pages and has no way to change one, and it runs on the device. The
instructions were in `CompanionPrompt`.

## Knowledge and continuity

Apple's on-device model proposes *candidate* statements from each paragraph
using guided generation. `ProvenanceValidator` keeps a candidate only if:

1. it cites a source paragraph, and the quote appears in it verbatim
2. its value is the author's own words, found in the quote (no paraphrase)
3. it isn't marked established when the quote is hedged ("maybe", "might", "?")

Editing a paragraph invalidates every fact sourced from it. Asking about an
attribute with no fact returns `.unknown`, which callers must handle.

## Source-grounded illustration

`IllustrationPlan` decides what a picture may show before any pixels exist:

- Each kind (character, place, object, scene) has a fixed set of slots that a
  picture would otherwise have to invent (hair, clothing, terrain, sky…).
- A slot is filled only by an **established** fact, in the author's words.
  Speculative facts are not drawn.
- Unknown slots map to regions that are masked out of diffusion and rendered
  as neutral wash, negative space or unfinished areas.
- The prompt is the fixed, content-free style line plus the author's words.
  The negative prompt suppresses detail, ornament and extra subjects.
- Denoising strength and step count scale with completeness, so a sparsely
  described subject is a faint study and fills in as the author writes more.
- The seed is derived from the subject name, so the composition is stable
  across revisions instead of reshuffling.
