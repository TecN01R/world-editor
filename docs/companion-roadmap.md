# Companion: what comes next

A plan, not built yet (Kevin asked for it on 2026-11-23): full web search and
research when a question is asked, and image and text upload and analysis.
`docs/companion.md` describes the companion as it is.

## What stays fixed

- **All inference on the device.** A web search sends search words to a search
  service; nothing else leaves the phone, and the model that reads the results
  is the one on the phone.
- **Their world comes from them.** Search, images and documents feed the
  companion's knowledge of the *real* world and of what the writer hands it.
  They never become a way for it to add to the writer's world.
- **Frictionless.** Nothing to set up before writing. Looking something up is
  something the companion does when asked a question, not a mode to switch on.
- **Stock parts.** Foundation Models' own tool-calling API (through
  AnyLanguageModel, which follows it), `PhotosPicker`, `fileImporter`, PDFKit.

## 1. Looking things up, starting with Wikipedia

The companion gets one tool, `look_up(query)`. It decides when to use it: a
question about the real world it isn't sure of. The app runs the search and
hands back a few numbered passages; the companion answers from them and the app
shows where they came from.

- **Why it comes first:** real-world facts are what the companion gets wrong
  most. On questions like "were trireme rowers slaves or free?" it answers
  confidently and falsely, and telling it to be honest about what it doesn't
  know only made it vaguer (measured; `docs/companion.md`). It has to look
  things up.
- **Why Wikipedia first:** no account, no key, no cost, and it covers most of
  what a worldbuilder asks (history, ships, climate, how things work). Kevin
  agreed to start here.
- **How:** a `Tool` (`name`, `description`, one `query` argument) passed to the
  session; Gemma 4's own tool-call format is already rendered and parsed by
  AnyLanguageModel. `ToolExecutionDelegate` shows "Looking up …" while it runs.
  One search per reply to begin with (`maximumToolRounds`), results trimmed to
  about 1,500 tokens, and the tool's output cleaned the same way the writer's
  text is (`Reasoned.gemmaPlain`), since it comes from outside.
- **What the writer sees:** under the reply, a chip: *Searched Wikipedia for
  "trireme crew size"*, opening the sources. The exact words sent are always
  visible. The first time, one sheet says what looking up means and offers to
  turn it off.
- **Their world stays private:** the instructions tell it to search real-world
  terms only, never the names on their pages; the chip makes any slip visible.
  questions it can't answer for sure, and on fewer than 1 in 20 other turns;
  judged answers contain no made-up specifics. If a model misses the gate, the
  fallback is a **Look It Up** action on a reply, which runs the same search
  with no decision left to the model.
  tool and one line about when to use it, it searched on all 14 real-world
  questions and on none of the other 99 turns, and no name from the writer's
  pages appeared in a search. So the deciding can be left to the model. The
  answers are the open part: a first try that handed it the opening of the
  top articles got the fact right only when that opening contained it (it
  usually doesn't; who rowed a trireme is far down the article), and otherwise
  it fell back on its own wrong belief or said it couldn't tell. The work is
  in choosing passages: rank the paragraphs of the whole article against the
  question. Step 3 needs the same routine for documents, so build it once.

## 2. The whole web, and research

- **Search provider:** Brave Search's "LLM Context" endpoint returns passages
  already extracted and sized to a token budget, which suits a small model.
  It needs a key (about $5 per 1,000 searches, with a monthly credit that
  covers one person's use). To begin: Kevin's own key, kept in the Keychain.
  Before the app ships to others it needs a small relay holding the key, or
  the writer's own key; that is a decision for then. Without a key the tool
  stays on Wikipedia.
- **Research:** several searches for one question (the model asks, reads, asks
  again, up to a small cap), then one answer with numbered sources. A longer
  wait, so it's shown as it goes: each search appears as it's made.
- **Reading a page:** when the writer pastes a link, fetch it and reduce it to
  its text (a reader pass on the device).
- **Gate:** as step 1, plus the answer's claims are found in the passages it
  cites (judged), and the companion says so when the search found nothing.

## 3. Text the writer hands it

- **Bringing it in:** a **+** beside the message field: *Photo*, *File*,
  *Paste*. Files through `fileImporter` (.txt, .md, .pdf via PDFKit; .docx
  later). A long paste into the field is treated as a document, not a message.
- **Reading it:** a short text goes to the model whole. A long one is cut into
  overlapping pieces, and each question gets the few pieces that match it
  (keyword ranking first; Spotlight's on-device semantic search, which the app
  already uses for pages, if that isn't enough). "Summarise this" works through
  it in sections.
- **Whose it is:** an attached text is something to read and answer from, and
  no question is asked about it. If it's the writer's own notes, they can say
  so in the conversation. Turning old notes into pages of the world is a
  different feature (import, where the writer approves each proposed page).
- **Gate:** questions about a document are answered from it, with the passage
  shown; it says when the document doesn't say.

## 4. Images

- **Bringing it in:** `PhotosPicker`, the camera, paste.
- **Seeing it:** Gemma 4 reads images through a second file, its vision
  projector (about 0.6 GB more to download for E2B, fetched the first time an
  image is added). The image is scaled down first, placed before the words in
  the turn, and described once; later turns carry the description, not the
  image, to save room.
- **What it's for:** a map, a sketch, a reference photo, a page of handwritten
  notes. It says what it sees and answers questions about it. What it *means*
  in the writer's world is theirs to say.
- **Unknown until measured:** memory with the projector loaded, and speed, on
  the Duo; E2B is the weakest of its family on documents and small text.
- **Gate:** descriptions judged against the image for made-up detail.

## 5. Its own tools for the writer's pages

Today the companion is shown the opening of the related pages and what bears
on this one from earlier conversations, chosen by shared words. That stops
scaling as a world grows. Next: `find_pages(query)` and `read_page(name)` over
the Spotlight index the app already keeps, and a running summary of a long
conversation in place of dropping its oldest turns. Same gates.

## Order, and what each step needs first

   first-time sheet).
2. Text files and long pastes (needs: the **+** button; no new model files).
3. The whole web (needs: a Brave key; the relay question can wait).
4. Images (needs: projector download; memory and speed measured on the Duo).
5. Page tools and conversation summary.

Speed between turns also needs work before any of this adds to the prompt:
the app builds a fresh session for every reply, so the model re-reads
everything each time. AnyLanguageModel can keep one session for a conversation
and re-read only what changed (`LanguageModelSession(profile:history:)` with a
history transform that drops its earlier reasoning). That has to be tried on
the phone.
