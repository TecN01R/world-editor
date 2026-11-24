# To do

The working list for World Editor. Kevin and Claude both edit it. Delete a line once
it's on the phone and checked, or answered; git history keeps what's done.

## Bugs on the Duo
- [ ] Sometimes the pages list won't reopen after it closes (now a drawer; check it always reopens)
- [ ] Janky animations (folding, rotating, opening the companion, typing, replies)
- [ ] Rotation crash: check it's gone

## Stock-first audit (plan approved 2026-11-24): batches
- [ ] 1 Data safety and filing accuracy (pushed 5931105; waiting for the phone)
- [ ] 2 The two bugs and the rotation crash (pushed 484d2ab; waiting for the phone)
- [ ] 3 Open page in sync; editing crash risks (pushed 606a88a; waiting for the phone)
- [ ] 4 Smooth typing (pushed; waiting for the phone. Not done: the open page observed on its own, Focus caching its measurements; only if typing still lags)
- [ ] 5 Smooth replies (pushed 7c046d4; waiting for the phone)
- [ ] 6 Faster replies (pushed: background kept per conversation, earlier replies as cached, filing on a pause; Kevin to try 4–5 messages, then read the CACHE/SPEED lines)
- [ ] 7 One companion (needs Kevin's look on the phone; next after he's checked the current build)
- [ ] 8 Format bar through stock (Bold/Italic are iOS's own, lists undoable, Open in the link's menu; iOS has no public way to show its "Aa" panel from a button)
- [ ] 9 Stock swaps: bubbles and the menu's title done; left: a stack in the sidebar for conversations and filters, UIPageControl for Focus dots
- [ ] 10 Focus with iOS's zoom (needs Kevin's look on the phone)
- [ ] 11 Clean-up: download cancel/expiry and ordered progress done; TRIAL logging stays until the speed and Live Activity tests are read; thinking plumbing kept for search
- [ ] 12 docs/stock-deviations.md (written; check it reads right)

## Your words into your pages (design: claude.ai/artifact/4GgWK8rCVJUdjwsTrVW9QT)
- [ ] Placement with authorship marks and per-placement Undo, once the design is approved
- [ ] Amend CLAUDE.md and docs/ai-charter.md to the new rule when it ships

## Companion
- [ ] Rewrite the instructions to Kevin's taste (his ChatGPT style notes); remove the sample
      conversations; current page fields win over older conversations
- [ ] Search on the 26B, with thinking turned on for the replies that search
- [ ] Filing through tools (make page, set field, rename, set page text), each with Undo
- [ ] Live Activity: does tapping it reach the app? If never, our own Live Activity
- [ ] Remove the Plain Model switch from the menu

## Later
- [ ] Spotlight finds every world's pages
- [ ] Swift 6 language mode
- [ ] Replies keep running in the background (continued processing with the GPU)
- [ ] Download keeps its speed when the app isn't in front
- [ ] Look-ups online (Wikipedia first) and uploads (images)
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
- [ ] Instructions: your preferences as an editable menu item, or a private file?
- [ ] Folded companion sheet resting as a strip at the bottom, as in Maps?
- [ ] Names from your world in tracked files: scrub from now on, rewrite history, or make the
      repo private?
- [ ] Check on the phone: Changes timeline (test world "Test: Changes Timeline"), Mentions
      sheet layout
