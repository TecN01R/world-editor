# To do

The working list for World Editor. Kevin and Claude both edit it. Delete a line once
it's on the phone and checked, or answered; git history keeps what's done.

## Bugs on the Duo
- [ ] Sometimes the pages list won't reopen after it closes (now a drawer; check it always reopens)
- [ ] Janky animations (folding, rotating, opening the companion, typing, replies)
- [ ] Rotation crash: check it's gone

## Check on the phone
- [ ] The companion is the model stock now, with its tools and no instructions (Kevin, 2026-11-25); Instructions… (debug) adds your own, none by default
- [ ] More memory for the app (Kevin, 2026-11-25: "Yes" to the patched xtool): installed from d7a1eed on; the companion's next LOAD line should show about 5.8 GB left instead of 3.4
- [ ] Wikipedia look-ups: ask a real-world question it might not know; "Searched Wikipedia for …" under the reply opens the articles; Look Things Up in the menu turns it off (Kevin, 2026-11-25)
- [ ] The new companion model, Nemotron 3.5 Bolt (Kevin, 2026-11-25: "Yes"): downloaded, loads and replies, 26B freed (seen in the log). Left: how the replies feel, a search shown in its thinking
- [ ] Type and field names in San Francisco everywhere; values stay New York (Kevin, 2026-11-24)
- [ ] Empty fields hidden; Add Field's menu lists them, and one picked shows ready to fill in (Kevin, 2026-11-24)
- [ ] Back from the app switcher with the companion open unfolded: the page keeps its normal margins
- [ ] The companion's button after unfolding (asked for again once the fold settles)

## Stock-first audit (plan approved 2026-11-24): batches
- [ ] 1 Data safety and filing accuracy (pushed 5931105; waiting for the phone)
- [ ] 2 The two bugs and the rotation crash (pushed 484d2ab; waiting for the phone)
- [ ] 3 Open page in sync; editing crash risks (pushed 606a88a; waiting for the phone)
- [ ] 4 Smooth typing (pushed; waiting for the phone. Not done: the open page observed on its own, Focus caching its measurements; only if typing still lags)
- [ ] 5 Smooth replies (pushed 7c046d4; waiting for the phone)
- [ ] 6 Faster replies (pushed: background kept per conversation, earlier replies as cached, filing on a pause; Kevin to try 4–5 messages, then read the CACHE/SPEED lines)
- [ ] 7 One companion (needs Kevin's look on the phone; next after he's checked the current build)
- [ ] 8 Format bar: kept as it was (Bold, Italic, lists; iOS's own Bold/Italic, undoable lists). iOS's Format panel, text styles and the keyboard toolbar were tried and dropped (Kevin, 2026-11-24)
- [ ] 9 Stock swaps: bubbles and the menu's title done; left: a stack in the sidebar for conversations and filters, UIPageControl for Focus dots
- [ ] 10 Focus with iOS's zoom (needs Kevin's look on the phone)
- [ ] 11 Clean-up: download cancel/expiry and ordered progress done; TRIAL logging stays until the speed and Live Activity tests are read; thinking plumbing kept for search
- [ ] 12 docs/stock-deviations.md (written; check it reads right)

## A companion for 8 GB+ phones, not just the Duo (Kevin, 2026-11-24; plan approved)
- One model, for every iPhone from the 15 Pro on (≈6 GB app budget, whatever the RAM) and Android phones with 12 GB+; 8 GB Androids get no companion (Kevin, 2026-11-24). Budget: ≤4–4.5 GB of the app's own memory, ≤5–5.5 GB resident with the weights
- [ ] 3 Benchmark mode on the Duo, held to an 8 GB phone's memory
- [ ] 4 iOS: the one model, offered where the phone's memory allows it
- [ ] Speed floor (Kevin, 2026-11-24): about reading speed once it starts writing, ~6 tokens/s, on the weakest phone (the iPhone 15 Pro); no saved cache ("I'm not taking more space"), so reading the prompt has to be fast too. Nemotron on the Duo, first reply (2026-11-25): writes 23 tokens/s, reads 1,400 tokens/s, first words 7.4 s with the load (3.3 s); memory 3.1 GB left to the app. The 15 Pro is still to measure
- [ ] Android app: later, its own native project

## Your words into your pages (design: claude.ai/artifact/4GgWK8rCVJUdjwsTrVW9QT)
- [ ] Placement with authorship marks and per-placement Undo, once the design is approved
- [ ] Amend CLAUDE.md and docs/ai-charter.md to the new rule when it ships

## Companion
- [ ] Search: built on Nemotron (search_pages, thinking capped); check it finds things on the phone
- [ ] Filing through tools (make page, set field, rename, set page text), each with Undo
- [ ] Live Activity: does tapping it reach the app? If never, our own Live Activity

## Later
- [ ] Spotlight finds every world's pages
- [ ] Swift 6 language mode
- [ ] Replies keep running in the background (continued processing with the GPU)
- [ ] Download keeps its speed when the app isn't in front
- [ ] Documents (PDF, text) and images in the companion (after Wikipedia look-ups; Kevin, 2026-11-25: "go for it with the web stuff"); the whole web needs a search provider and key
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
- [ ] The one-time wobble of the pages list: folded or unfolded, once per launch or per install? A screen recording would settle it
- [ ] Approve the his-words design, and three answers: fix spelling? turn "she" into the
      page's name? place words that contradict the page?
- [ ] Folded companion sheet resting as a strip at the bottom, as in Maps?
- [ ] Names from your world in tracked files: scrub from now on, rewrite history, or make the
      repo private?
- [ ] Check on the phone: Changes timeline (test world "Test: Changes Timeline"), Mentions
      sheet layout
