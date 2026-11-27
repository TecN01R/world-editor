# To do

The working list for World Editor. Kevin and Claude both edit it. Delete a line once
it's on the phone and checked, or answered; git history keeps what's done.

**No new companion features until Kevin has caught up** (Kevin, 2026-11-27: "all the features are
outgrowing the pace at which I can understand their development"): only fixes to what he reports.
Testing is using it: when a reply is bad or something feels off, he says so, and Claude pulls the
conversation and the phone's log to find out why.

## Try on purpose: a 10-minute walkthrough of the companion
- [ ] 1 Open a page you've written on and ask what it thinks of something on it: it answers without searching first (it's given the open page)
- [ ] 2 Tell it something new about that page ("she trained at the Iron Abbey"): after the reply, your sentence is in the page, highlighted, after your paragraph about the same thing, with Undo under the reply
- [ ] 3 Ask how this page connects to another one: it searches your pages ("Searched your pages" in its thinking)
- [ ] 4 Ask a real-world question ("how did old lighthouses keep the flame lit?"): it looks it up on Wikipedia ("Searched Wikipedia for …" under the reply)
- [ ] 5 Paperclip → Scan Documents, Choose File or a photo (pictures first ask for a one-time 990 MB download), then ask about it. How well it sees pictures is yours to judge: NVIDIA trained it on words only
- [ ] 6 Say "from now on, keep your replies short": "Added to Instructions: …" shows under the reply

## Tell Claude if anything looks or feels wrong
- [ ] On the phone, nothing to check on purpose (Kevin, 2026-11-27: "Yes" to folding the list); each line's
      details are in git history: faster first words (warm-up), Swift 6, the lifted limits, more memory
      (5.8 GB), Nemotron's replies, fonts (San Francisco for names, New York for values), empty fields
      hidden, margins after the app switcher, the companion's button after unfolding, and the stock-first
      audit's batches 1, 3–8, 10 and 12 (docs/stock-deviations.md)

## Stock-first audit (plan approved 2026-11-24): work left
- [ ] 9 Stock swaps: bubbles and the menu's title done; left: a stack in the sidebar for conversations and filters, UIPageControl for Focus dots
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
- [ ] As useful as ChatGPT is for Kevin (Kevin, 2026-11-26). Waiting for his ChatGPT export (kept in git-ignored private/): about 20 things he actually asked ChatGPT, asked of the phone's companion too, side by side on one page, so he sees where it holds up (2026-11-27); his ChatGPT instructions and memories carried into Instructions. Done since: faster first words, pictures, the open page
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
