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
- **Stock parts.** The model's own tool-call format, as its chat template
  renders it (`GemmaChat`, tested against llama.cpp's rendering; `search_pages`
  runs this way since 2026-11-25), `PhotosPicker`, `fileImporter`, PDFKit.

## 1. Looking things up, starting with Wikipedia

**Built 2026-11-25** (Kevin: "go for it with the web stuff"; `WebLookup`, `ReplyTools`):
`look_up` beside `search_pages`, English Wikipedia's search, the two best articles read
whole for the paragraphs that answer, "Searched Wikipedia for …" under the reply with
its sources, Look Things Up in the companion's menu (on by default). Never sent: their
pages' names and every name they wrote, unless the phone's dictionary knows it. Requests
name the app by its public repository (Kevin's choice), which Wikimedia's policy asks for
(200 requests a minute, not 10). What follows is the design as planned.

The companion gets one tool, `look_up(query)`. It decides when to use it: a
question about the real world it isn't sure of. The app runs the search and
hands back a few numbered passages; the companion answers from them and the app
shows where they came from.

- **Why it comes first:** a small model's real-world facts are unreliable. On
  questions like "were trireme rowers slaves or free?" it can answer
  confidently and falsely. It has to look things up.
- **Why Wikipedia first:** no account, no key, no cost, and it covers most of
  what a worldbuilder asks (history, ships, climate, how things work). Kevin
  agreed to start here.
- **How:** one tool (`name`, `description`, one `query` argument) declared
  beside `search_pages` in the model's chat format (`GemmaChat`);
  `LlamaModel` runs the call as it runs `search_pages`, shows "Looking up …"
  meanwhile, and goes on with its output in the model's turn. One search per
  reply to begin with, results trimmed to about 1,500 tokens, and the tool's
  output cleaned the same way the writer's text is (`Reasoned.gemmaPlain`),
  since it comes from outside. Replies think first (capped), as the model is
  made to.
- **What the writer sees:** under the reply, a chip: *Searched Wikipedia for
  "trireme crew size"*, opening the sources. The exact words sent are always
  visible. The first time, one sheet says what looking up means and offers to
  turn it off.
- **Their world stays private:** the instructions tell it to search real-world
  terms only, never the names on their pages; the chip makes any slip visible.
- **Choosing passages:** an article's opening often lacks the answer (who
  rowed a trireme is far down the article), so the paragraphs of the whole
  article are ranked against the question. Step 3 needs the same routine for
  documents, so build it once.

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

## 3. Text the writer hands it

**Built 2026-11-25** (Kevin: "when can we get picture analysis and pdf or text analysis"): a
paperclip beside the message field opens iOS's file picker (PDF, text, Markdown; several at
once); PDFKit reads a PDF's text. A document up to 8,000 characters goes to the model whole in
the author's turn; a longer one with its opening, and `search_document` finds the rest in
overlapping pieces (`Documents`). Not yet: Paste as a document, .docx, scanned PDFs (no text).

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

## 4. Images

- **Bringing it in:** `PhotosPicker`, the camera, paste.
- **Seeing it:** the companion's model reads images through its vision
  projector (NVIDIA publishes one beside the model, about 1 GB more to
  download, fetched the first time an image is added; llama.cpp's `mtmd`
  runs it; whether the Duo holds both is to be measured). The image is scaled down first, placed before the
  words in the turn, and described once; later turns carry the description,
  not the image, to save room.
- **What it's for:** a map, a sketch, a reference photo, a page of handwritten
  notes. It says what it sees and answers questions about it. What it *means*
  in the writer's world is theirs to say.
- **Unknown until measured:** whether the image pack runs on the Duo at all,
  and its memory and speed there.

## 5. Its own tools for the writer's pages

Today the companion is shown the opening of the related pages and what bears
on this one from earlier conversations, chosen by shared words. That stops
scaling as a world grows. Next: `find_pages(query)` and `read_page(name)` over
the Spotlight index the app already keeps, and a running summary of a long
conversation in place of dropping its oldest turns.

## Order, and what each step needs first

1. Wikipedia look-up (needs: the chip and the first-time sheet).
2. Text files and long pastes (needs: the **+** button; no new model files).
3. The whole web (needs: a Brave key; the relay question can wait).
4. Images (needs: the image pack's download; whether it runs on the Duo, and
   its memory and speed there).
5. Page tools and conversation summary.

Speed between turns also needs work before any of this adds to the prompt:
the model re-reads its whole prompt for most replies. llama.cpp keeps what
it has read (its KV cache) and reads only from where a prompt differs from the
last one (`Loaded.start` in `LlamaModel`), but the companion's prompt changes
near its start with each message (the background), and filing reads a prompt of
its own in between. Keeping the background fixed through a conversation, and
filing without losing the reply's cache, has to be tried on the phone.
