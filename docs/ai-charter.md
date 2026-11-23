# AI charter: support the author, never author

The author is the only creative authority over their work. The AI acts as
librarian, archivist, critic, interviewer and constrained illustrator, never as
co-author. Each rule below names the code that enforces it, because a
behaviour that only lives in a prompt isn't guaranteed.

## Rules that apply everywhere

| Rule | Enforced by |
|---|---|
| All inference runs on the device. No cloud, subscriptions or external AI APIs. | No network AI clients exist in the codebase. Apple's framework is pinned to `SystemLanguageModel` (on-device), never its server models (`FactExtractor`). |
| The AI never modifies the author's writing. | AI code receives `Document` *values* (copies); only the editors call `Library.update`. |
| Inferred information is never presented as established. | `KnowledgeBase` has only `established` (author stated it) and `speculative` (author wrote it as uncertain). Anything else is `unknown`. |
| Where non-invention can't be guaranteed, prefer incomplete output. | Rejected candidates are dropped and logged, never repaired by guessing (`ProvenanceValidator`, `CompanionGuard`, `IllustrationPlan`). |
| Structure isn't writing: the AI may propose types and field names ("Wants", "Home"), as questions the author answers. Every field *value* is the author's own words; the AI never fills one in itself. (Kevin's ruling, 2026-11-22.) | Values are filed only from the author's words, with a source (`ProvenanceValidator`); the author approves every proposed type, field and value. |
| Models download on demand and unload when idle. | `ModelCatalog` (licence + pinned checksum required before download), `ModelResidency` (memory budget, LRU unload). |

## Search and curation

Semantic search finds and groups the author's own passages by meaning. It
returns existing text with its location and never writes new text. Today it is
Core Spotlight's on-device semantic search over the author's pages
(`PageIndex`): it returns the author's passages, ranked, and nothing else.

## Writing companion

A partner for thinking: it reflects back what the author wrote, asks
questions, challenges assumptions, points out contradictions and gaps,
critiques, summarises the author's own ideas, and helps them brainstorm by
drawing ideas *out of them*.

It does not supply content: no prose, plot developments, characters, names,
places, world details or "ideas" of its own, even when asked.

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

- `CreativeRequest.isCreative` catches requests for the companion to produce
  content. They get a fixed decline plus an offer to help the author work it
  out. They are never sent to a model as a task. Requests for *help* ("help me
  brainstorm the ending") are allowed.
- `CompanionGuard.checkReply` inspects every reply before it's shown. It rejects:
  - prose: similes and imagery markers ("like a…", "as if", "heavier than…")
  - a critic's words ("theme", "symbolism", "stands for", "metaphor")
  - suggestions ("what if…", "have you considered…", "maybe she…", "you
    could…", "for example…")
  - names the author never wrote, and genders they never gave
  - replies longer than three short sentences
- Either-or questions ("does she have a captain, or row for someone else?")
  are allowed for now and flagged for review (`CompanionGuard.offersChoices`;
  Kevin, 2026-11-22: open it up, flag it, tighten later if they feed the author
  ideas).
- A rejected reply is regenerated; if none passes, the companion says nothing
  (no stock questions: Kevin's call, 2026-11-22) and offers to try again.
- (`CompanionGuard.check`, stricter, also rejects any content word that isn't
  the author's; it's kept for one-shot questions, where that's affordable.)

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
