# To do

The working list for World Editor. Kevin and Claude both edit it. Delete a line once
it's on the phone and checked, or answered; git history keeps what's done.

**No new companion features until Kevin has caught up** (Kevin, 2026-11-27: "all the features are
outgrowing the pace at which I can understand their development"): only fixes to what he reports.
Testing is using it: when a reply is bad or something feels off, he says so, and Claude pulls the
conversation and the phone's log to find out why.

## The correction (Kevin, 2026-11-27; plan approved)
Kevin, after a day of patch installs: "This is not at all reaching any of the goals of frictionless
use, consistency, or professional development that I desire of this app. Please correct it using the
latest techniques and research." His yardstick: "I can't know I'm using an app it has to be effortless
and just flow"; "the text has to look gorgeous like it was printed but also be easy to read chapter
upon chapter"; "I want to feel like my world is growing itself and I'm uncovering it". What was wrong
underneath: filing waited two minutes and lost whatever was still waiting; "she", "he", "it" and "they"
weren't filed in the world's conversation; screens were swapped rather than pushed; every screen set
its own fonts and spacing; nothing was looked at on a screen before it reached him. Three installs,
each rendered on the Duo simulator and reviewed before it reaches his phone.
- [ ] 0 Groundwork, nothing on the phone: a sample world and a scene for every screen; the Mac jobs rendering them folded, unfolded and at large text; checks by script; named sizes, colours and text styles; test screens for the Duo's side column, tabs and panes
- [ ] 1 Install 1, his words reach his pages and read like print: filed right after every reply ("Adding to your pages…"); nothing lost when the app closes; "she", "he", "it", "they" and "the guild" go to the page just talked about (only ever adding, with Undo); filing in its own lane so replies stay as fast; line spacing, grey text and the Read and Edit layouts corrected
- [ ] 2 Install 2, one app: Talk and World tabs placed by iOS; real Back, swipe and trail; reopening where he left off; one quiet line of page names under a reply, a page peeked from it (beside the conversation when unfolded); Send becomes Stop; every screen rebuilt from the same parts. The drawer, the hand-made Back buttons and the ⋯ menus go. Then, by him: a minute of folding, unfolding and rotating in each tab
- [ ] 3 Install 3, his world pulls him back (after he has used 2): what's new, and the names only mentioned so far, on World's front page; a new conversation showing one line of his own words; search in its own place
- Changed with his approval: tabs in place of the drawer (the conversation list is Talk's first screen, one swipe back); "each discrete action has its own undo" kept one tap deeper (the line's own Undo takes back everything that message did)
- Never: totals, streaks, progress bars, badges, notifications
- The research behind it is in git-ignored private/reports/; Kevin doesn't choose between design options ("experience will be [the arbiter] and so will research and comparing to other apps")

## What the app is for (Kevin, 2026-11-27)
"Literally this app should enable me to finally write my novel, conceptualize how everything looks by
the art it generates, help me with prompts and refinements, and make it so writing doesn't seem scary
and no brainblocks exist." Order proposed: the world filling itself from talk (now), then art from his
pages (on the phone), then the novel itself (chapters drafted in Focus mode with the world and the
companion at hand). "Refinements", answered: "I want it to help me when I am stuck, not by giving me
ideas, but by coaxing it out of me": questions that draw his own ideas out, never ideas of its own.
The companion runs stock with blank instructions, so this goes in as his own instruction (he tells it
"from now on…", and it adds it to Instructions)

## The conversation first (Kevin, 2026-11-27)
The goal, in his words: "I'll just usually talk with ChatGPT and never actually formalize anything so
as long as it feels like that experience but things are actually created frictionlessly then that's
what I want."
Kevin: "I want to write it conversationally or in any messy way and be able to refine it back and
forth and that populates my pages. I do want them to be structured. And they need to be malleable
enough that everything about them can change and the system is smart enough to adapt." The app is
pages first today; this makes the conversation the place he writes and the pages what comes out of it.
- [ ] 1 The conversation as the home screen: opening a world lands in its conversation, no page or type to pick; the pages a tap away, where he reads his world (editing them by hand stays possible, never needed)
- [ ] 2 New pages from what he says: each person, place or thing he talks about gets a page, in his words, its type and fields taken from what he said; a line under the reply shows what changed, with Undo
- [ ] 3 Changes that stick: a correction replaces the sentence it contradicts, even one he typed (Kevin: "a"), marked, with Undo; renames everywhere; "those two are the same" merges pages
- [ ] 4 Structure that reshapes itself: types and fields appear, rename and merge as the world grows
- [ ] Welcoming, not intimidating, everywhere (Kevin, 2026-11-27: "the pages and any area should look welcoming"; what's wrong is "cold and plain", "maybe it's all the black", no theme wanted): dark mode in iOS's softer grey (Kevin: "Better but color or warmth might be better"), then warm colours after gruvbox (Kevin: "Yes, I used to be partial to gruvbox myself but I don't want to deviate outside what iOS allows"), reverted ("The gruvbox looks half assed": the page a coloured panel inside iOS's grey bars and side column). Dark only (Kevin: "Let's stop offering a light mode I'll never use it"). The pages list as a book's contents (installed). Colour from each world's art: on hold, as it would meet the same edges
- The risk: the phone's model is small, and "smart enough to adapt" rests on it; tried on his own world from step 2

## Try on purpose: a 10-minute walkthrough of the companion
- [ ] 1 Open a page you've written on and ask what it thinks of something on it: it answers without searching first (it's given the open page)
- [ ] 2 Tell it something new about that page ("she trained at the Iron Abbey"): after the reply, your sentence is in the page, highlighted, after your paragraph about the same thing, with Undo under the reply
- [ ] 3 Ask how this page connects to another one: it searches your pages ("Searched your pages" in its thinking)
- [ ] 4 Ask a real-world question ("how did old lighthouses keep the flame lit?"): it looks it up on Wikipedia ("Searched Wikipedia for …" under the reply)
- [ ] 5 + beside the message field → Scan Documents, Choose File or a photo (pictures first ask for a one-time 990 MB download), then ask about it. How well it sees pictures is yours to judge: NVIDIA trained it on words only
- [ ] 6 Say "from now on, keep your replies short": "Added to Instructions: …" shows under the reply

## Tell Claude if anything looks or feels wrong
- [ ] On the phone, nothing to check on purpose (Kevin, 2026-11-27: "Yes" to folding the list); each line's
      details are in git history: faster first words (warm-up), Swift 6, the lifted limits, more memory
      (5.8 GB), Nemotron's replies, fonts (San Francisco for names, New York for values), empty fields
      hidden, margins after the app switcher, the companion's button after unfolding, and the stock-first
      audit's batches 1, 3–8, 10 and 12 (docs/stock-deviations.md)

## Stock-first audit (plan approved 2026-11-24): work left
- [ ] 9 Stock swaps: the menu's title done; left: a stack in the sidebar for conversations and filters, UIPageControl for Focus dots
- [ ] 11 Clean-up: download cancel/expiry and ordered progress done; TRIAL logging stays until the speed and Live Activity tests are read; thinking plumbing kept for search

## A companion for 8 GB+ phones, not just the Duo (Kevin, 2026-11-24; plan approved)
- One model, for every iPhone from the 15 Pro on (≈6 GB app budget, whatever the RAM) and Android phones with 12 GB+; 8 GB Androids get no companion (Kevin, 2026-11-24). Budget: ≤4–4.5 GB of the app's own memory, ≤5–5.5 GB resident with the weights
- [ ] Search again for a faster, stronger model than Nemotron (Kevin, 2026-11-25, after dropping the 26B again): the search found nothing faster AND stronger; Ling-3.0-tiny was tried stock (2026-11-25) and not taken (docs/models.md). The bar (Kevin): faster AND stronger; slower or smaller isn't a win; models run stock, community builds are fine
- [ ] 2 The model: Nemotron 3.5 Bolt E4B chosen (Kevin, 2026-11-25), thinking capped at NVIDIA's 128 tokens, with search_pages. Built in (llama.cpp), bartowski's Q4_K_M file; filing without thinking, which is faster
- [ ] 3 Benchmark mode on the Duo, held to an 8 GB phone's memory
- [ ] 4 iOS: the one model, offered where the phone's memory allows it
- [ ] DFlash, NVIDIA's helper for faster writing (researched 2026-11-26, docs/models.md): waiting for Kevin, after he's tried the warm-up. A trial on the Duo would be about a day's work and 737 MB more to download; kept only if it writes at least 1.5 times faster there
- [ ] Speed floor (Kevin, 2026-11-24): about reading speed once it starts writing, ~6 tokens/s, on the weakest phone (the iPhone 15 Pro); no saved cache ("I'm not taking more space"), so reading the prompt has to be fast too. Nemotron on the Duo, first reply (2026-11-25): writes 23 tokens/s, reads 1,400 tokens/s, first words 7.4 s with the load (3.3 s); memory 3.1 GB left to the app. The 15 Pro is still to measure
- [ ] Android app: later, its own native project

## Companion
- [ ] His ChatGPT conversations into his world (proposed 2026-11-27; the export arrived that day, kept in git-ignored private/; next after the correction): file his own side of them (never ChatGPT's words) into pages as the companion files a message, each with Undo, so he starts with the world he has already talked out
- [ ] As useful as ChatGPT is for Kevin (Kevin, 2026-11-26). His ChatGPT export is here (git-ignored private/); after the correction: about 20 things he actually asked ChatGPT, asked of the phone's companion too, side by side on one page, so he sees where it holds up (2026-11-27); his ChatGPT instructions and memories carried into Instructions. Done since: faster first words, pictures, the open page
- [ ] Choose a test suite for the companion from an open standard, built around how the app is used (Kevin, 2026-11-25: he judges by using it)
  - [ ] Blind taste test for Kevin (Kevin, 2026-11-25: "I'm also ok with blind taste test for me"): pairs of anonymous replies to his own messages, fresh from each candidate; he picks or ties; ranked as Chatbot Arena does (Bradley–Terry); he is the only judge
- [ ] Search: built on Nemotron (search_pages, thinking capped); check it finds things on the phone
- [ ] Filing through tools (make page, set field, rename, set page text), each with Undo
- [ ] Live Activity: does tapping it reach the app? If never, our own Live Activity

## Later
- [ ] Image generation on the phone (Kevin, 2026-11-25): one model that does tools and images, or a separate image model to download; research running
- [ ] Remove the old full prompt (CompanionPrompt's instructions, examples, background) once the stock one has settled; unused by the app until then
- [ ] Spotlight finds every world's pages
- [ ] Replies keep running in the background (Kevin, 2026-11-26: "absolutely yes"): built (`BackgroundReply`). The Duo offers the GPU to a background task, but Apple gives the Background GPU Access capability only to paid Apple Developer Program teams: it refused the free team ("does not have a program membership that is eligible for this feature"). Waiting on Kevin: join the program ($99 a year; signing then also lasts a year instead of 7 days), or leave it
- [ ] Download keeps its speed when the app isn't in front
- [ ] The whole web, beyond Wikipedia, needs a search provider and key
- [ ] VoiceOver pass over the page title and fields
- [ ] Paragraph IDs drifting when paragraphs are edited (`reconcile`)
- [ ] World calendar date picker
- [ ] Reproducible replies ("same reply" pin)
- [ ] Does the companion speak first on pages too?

## Waiting on Kevin
- [ ] The AI charter and CLAUDE.md name protections from code the app never runs (fact extractor,
      knowledge base, model catalogue's checksum rule, creative-request and illustration guards):
      remove that code and reword the charter to what actually guards it, or keep it?
- [ ] Done in Focus mode: keep, or let Exit Focus also close the keyboard?
