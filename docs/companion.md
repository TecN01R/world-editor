# The companion: how it's prompted, and why

The companion is a language model running on the phone (Gemma 4 26B-A4B since
2026-11-24; `docs/models.md`). What it says is decided by three things: which
model it is, the text it's given before the conversation (its prompt), and how
its output is sampled. This page records what those are, the reasons, and the
measurements behind them, so the next change starts from evidence.
`docs/companion-roadmap.md` covers what isn't built yet (web search, images,
documents).

## What it's for

Kevin's words, which the rest is judged against:

- "Someone to talk to and bounce ideas off of but who doesn't think they're the
  smartest person in the room, and won't write their own content."
- "A thinking companion who will poke and prod without thinking for me and
  without removing authorship."
- "Act like ChatGPT does, being able to hold a back and forth conversation
  without ever authoring anything."
- Three rules (2026-11-23): it won't invent things, won't write for me
  unprompted, won't reply with a stupid repeated question.
- No filtering of replies after the fact: "any behavior we don't want should
  be in the system prompt up front" (2026-11-23).

His example of a good reply, to a page that says only a name and "A maritime
adventurer": it asks whether she is a character for his world or an existing
historical figure, and remarks that the name has a nautical, Age of
Exploration sound. Short, specific, and it knows his world.

## What the model is given

system turn, in this order, then the conversation:

1. **Who it is** (`CompanionPrompt.instructions`, about 240 words). A friend
   the writer talks to about what they're writing, which may be an invented
   world, a story, notes or real life (it takes the page for what it is, a
   correction of Kevin's: the first wording said "fictional world"); what
   belongs in it comes only from the writer; it brings interest, honesty and
   what it knows of the real world. Then how to reply to
   their last message, as a few plain cases: a real-world question (answer,
   say when unsure, and don't defend an answer they doubt), a request for its
   opinion or for something written (do it, briefly), a correction, anything
   else. Then when a question is welcome (to understand what they've already
   said, never to make them produce more), and a line on manner.
2. **Examples** (`CompanionPrompt.examples`): ten short exchanges from a
   different writer's world (a woman who runs a cinema), each a different kind
   of reply: a clarifying opener, taking a correction, a hedged real-world
   answer, a two-word reaction to a joke, a gathering-up when the writer is
   stuck, an honest opinion, a goodbye that doesn't push another question.
3. **Background**, labelled as what the app shows it, not something the writer
   just said. The open page is introduced by name, saying outright that its
   title is the name of who or what it is about: told only "a Character page
   titled Casperica", E4B said the page gave no name and asked whether
   Casperica was a place (Kevin's conversation, 2026-11-23); said outright,
   it named her 7 times in 8 where it had 2 in 8, and never asked again. Then: the opening of the writer's other pages (those sharing words
   with this page first), what the writer told it on other pages that bears on
   this one, and the open page (a long page as its opening and its latest
   part).
4. **What to do first**, only when the page has just been opened, and fitted
   to the page in code: on a blank page, make it easy to begin; on a thin one,
   say what it makes of it and ask which of two readings is meant; on a page
   with a lot on it, pick the one thing most worth talking about instead of
   summing it up.

The conversation follows as real turns. It begins with the writer's
"(I've just opened this page.)", because the companion speaks first and a chat
model's conversation has to begin with the other side. It does so only while
the companion is open, and not while the phone is hot or in Low Power Mode,
when the author begins instead (on the 26B a reply is minutes of the GPU's work).

Sampling is Google's for Gemma 4: temperature 1.0, top-p 0.95, top-k 64, no
repetition penalty. It doesn't think before replying, and there's no switch for
it (Kevin, 2026-11-24: "remove the thinking switch, trigger as necessary"): on
the 26B, Gemma's thinking (`<|think|>`) drafted each reply four or five times at
the phone's 7 tokens a second, minutes before the first word (on E2B it had
been 4 to 8 seconds). A reply that needs thinking turns it on (`Companion.thinks`):
without it. Earlier thinking is never sent back to it. The app renders Gemma's
chat format itself (`TurboModel.chat`) and reads its thought channel, so when
it thinks, the thinking shows, collapsed, as it comes. Anything in the writer's
text that Gemma would read as one of its control tokens is defused first
(`Reasoned.gemmaPlain`).

## Why it's shaped this way

Each choice below was either measured here or comes from the model's maker;
the sources are named so they can be checked.

**Few rules.** Small models follow one instruction well and five badly: in one
study a 2B model satisfied every instruction 80% of the time with one, 36%
with three, 8% with five (ManyIFEval). Google's own instruction-following
score for Gemma 4 E2B is about half that of its larger models. So the prompt
has a handful of cases, not a rulebook, and anything that depends on the
situation (a blank page, a first reply, a world with no other pages) is
decided in code and said only when it applies. Apple gives the same advice
for its on-device model.

**Say what to do, with the reason.** Naming a forbidden thing primes it: the
earlier prompt said "no themes, no symbolism, no what-if" and got more of
each. The current one says where the world comes from and why ("they know
their world; you know only what is on their pages").

**Every word is taken to its extreme.** Read from the model's own reasoning:
"friend" and "bounce ideas" produced "Hey! I love that vibe"; "plain and
direct" produced one clipped line; "listen more than you ask" produced pure
repetition; "sounding board" produced a critic. Each phrase in the prompt is
there because the alternative was tried and went wrong.

**Examples do more than rules.** A manner is shown better than described, and
this is the strongest lever found. It cuts both ways: when every example ended
in a question, every reply did; an example's wording is copied when the
situation matches. So the examples are short, from another domain (nothing in
them can be taken for the writer's world), varied in shape, and labelled as
not to be reused.

**The background is labelled and kept out of the writer's mouth.** When the
page arrived as the writer's first message, the model took the page's name for
the writer's ("That's a solid start, Ilsa"). As labelled reference in the
system turn, with the names called "their characters and places", that
stopped.

**Stable text first.** The instructions and examples never change, the
background changes when the page does, the conversation grows. In that order,
a model that keeps what it has read re-reads only what's new.

**The maker's settings.** Google specifies the sampling above "across all use
cases" and no repetition penalty. The library's default penalty of 1.1 had
been on by accident; turning it off was part of this change.

**No reply filter.** Kevin's ruling. The filter that used to screen replies
also made the companion fall silent and stiff, and it could only reject, not
improve. What takes its place is measurement before a change ships.

### What Claude's and ChatGPT's prompts do

Kevin asked whether these are public and how they work. Anthropic publishes
Claude's system prompt; ChatGPT's is known only from extraction. Both are long
(Claude's is about 5,000 words before any tools, far more with them), because
those models can hold that much. Claude's is written in the third person, in
prose, giving reasons instead of commands. ChatGPT's is second-person and
imperative, and more than half of it defines tools; memories and the user's
own instructions go in as labelled blocks. Both are given the date, and both
attach short "search for this / don't search for that" pairs to their tools.

What transfers to a model a thousandth the size is the manner, not the length:
reasons over commands, labelled blocks, behaviour stated positively. Lines
that shaped ours: Claude's "never starts its response by saying a question or
idea was good, great, fascinating" (ours: no praise), and its rule that it
"can reflect what the person has actually said and ask what connections they
see, but offering a causal story they haven't made themselves is speculation
presented as insight", which is Kevin's rule about guessing at motives.
ChatGPT's "Listener" personality has "mirror, don't prescribe ... stop before
solving for the user". What doesn't transfer: their length, and their
reliance on the model weighing many competing instructions.

The closest published work to "help someone think without doing the thinking"
is outside AI: Clean Language (questions built only from the person's own
words), motivational interviewing (reflect more than you ask) and the
dramaturg's neutral questions. Their shared finding is that pure questioning
fails: people stop talking to a tutor that only asks. Each turn has to give
something that is the listener's but not content: what it understood, or its
honest reaction. That is why the instructions ask for "a real reaction to
what they just said" before any question.

## What was measured

full, blank and long pages, corrections, pushback, one-word answers,
real-world questions, requests to write, being stuck, contradictions between
pages. About half are set in a small invented world and half in Kevin's own
(kept out of this repository). Each setup writes one reply to each moment.
against Kevin's three rules (a reply that breaks one scores 3 at most), then
on how good a companion it was. The judges are strict: 8 or more means a
reply a good friend might have given.

Round one, 106 moments, 2026-11-23 (score, with its 95% interval):

| Setup | Score | Breaks a rule | Invents | Pointless question | Gushes |
|---|---|---|---|---|---|
| The phone before this change (Gemma 4 E2B, three bare rules) | 2.6 (2.3–2.8) | 74% | 59% | 44% | 67% |
| This prompt on the same model | 4.5 (4.2–4.8) | 24% | 17% | 8% | 8% |
| This prompt on Gemma 4 E4B | 5.2 (4.9–5.6) | 9% | 6% | 5% | 1% |

- **The prompt** is worth about 1.9 points on the same model: better on 88 of
  the 106 moments, worse on 9.
- **The model** is worth another 0.7 (0.3 to 1.1). E4B is the 4.2 GB build
  (`unsloth/gemma-4-E4B-it-qat-GGUF`, UD-Q4_K_XL). Whether the Duo runs it
  fast enough, and in memory, is not measured yet. Its 3.2 GB "mobile" 2-bit
  build is not a shortcut: it scored like E2B on the automatic checks and
  thought three times as long. E2B's QAT build was no better than the file
  the phone has.
- **Thinking first** made no measurable difference to the score on either
  model (+0.1, interval −0.3 to +0.5, on E4B), though replies written after
  thinking broke a rule a little less often (9% against 15% on E4B). It costs
  about 250 tokens before each reply: seconds on the phone.
- **Handing a request to invent back** instead of doing it cost nothing
  measurable (−0.25, interval −0.6 to +0.1, on E4B; +0.1 on E2B).
- **It wasn't tuned to the test.** On the 68 moments never looked at while the
  prompt was written, E4B scored 5.0 (5.5 on the 38 that were), the old
  prompt 2.7.

Round two, the same day, compared three versions of the wording on E4B over
all 113 moments there were by then: as shipped 5.2; asked for fuller replies
4.9; handing requests to invent back 4.7, which is 0.5 below the shipped
wording (interval 0.1 to 0.8).

Whole conversations came next: someone playing a writer (short, impatient,
phone-typed messages) talked with it for eight or nine turns at a time, on a
thin page, with real-world questions, asking it to write, and across pages of
a bigger world.

- **E4B**, six conversations: "maybe I'd keep using it" each time. It never
  took over the writer's world and took corrections without fuss. Against it:
  it mostly said the writer's words back in tidier ones, it asked almost
  nothing after its opening, it missed the writer contradicting one of their
  own pages, it mixed up two characters once, and it defended wrong facts
  when doubted. The instructions now tell it not to defend them; in the two
  conversations after that it owned up to guessing, though it then agreed
  with whatever the writer suspected.
- **E2B**, three conversations with the final wording: "maybe", "maybe,
  leaning no" and "no". It over-reads ("so her core conflict is about
  visibility"), misses
  plain corrections ("i said from lol"), and what it writes on request
  contradicts the writer's pages. In single moments the two models are 0.7
  apart; over a conversation the gap feels wider.

Tried and dropped, so it needn't be tried again without a new idea:

- Handing a request to invent back ("that part is yours"). It scored lower,
  and in conversation it held for a request or two and then gave in, which
  the writer found arbitrary. The app follows Kevin's "won't write for me
  unprompted": asked outright, it does it, briefly (his decision, 2026-11-23;
- Telling it that it's a small offline model, unreliable on names and numbers.
  It got vaguer, not more accurate, and still said the rowers were slaves.
- Asking for fuller replies. The extra words were the page said back.
- Inviting more questions about what the writer just said. A stock question
  came back with them ("what kind of adventures does she go on?").
- A line added by the app when its last two replies asked nothing, reminding
  it that it may ask. In three conversations it changed nothing.
- The rules restated beside the writer's last message; the rules after the
  background; examples after the rules (it stopped thinking); a line on
  ordinary turns saying the page hasn't changed.

## What it still gets wrong

A strict judge gives the best setup 5 out of 10, and one reply in eight an 8
or better. What is left, from the judges' notes:

- **Real-world facts.** It answers confidently and is often wrong on the
  specifics: on 6 of 13 real-world questions E4B stated something false (that
  trireme rowers were slaves, that triremes were ocean-going, a diameter off
  by half). No wording fixed this; it has to be able to look things up
  (`docs/companion-roadmap.md`, step 1).
- **It echoes, and it stops asking.** With inventing ruled out and stock
  questions discouraged, its easiest move is to say the writer's words back.
  In a real conversation it asks in its opening and then hardly again: a
  model copies the manner of its own earlier replies, so two statements in a
  row become eight. Every tester named this first. After a correction or a
  one-word answer it often says little more than "Got it."
- **After a change to the prompt, old conversations keep the old manner**, for
  the same reason: the earlier replies are in front of it. Start a new
  conversation on the page to see the change.
- **It doesn't read as closely as it should.** Past a few hundred words it
  starts to misread who did what, and it can miss the writer contradicting
  one of their own pages in conversation.
- **It still invents now and then** (6% of replies on E4B, 17% on E2B): mostly
  a pair of made-up options inside a question, or a guess offered when the
  writer says "not sure yet".
- **It assumes he or she** for a character about half the time when the page
  doesn't say. One line telling it to use the name cut that to a third in a
  small test; it isn't in the prompt yet.
- **E2B more than E4B** falls back on a stock question ("what kind of
  adventure is she on?") and on a critic's voice ("suggests a profound sense
  of duty").

## Trying it again, and the plain model

Try Again (hold the latest reply) keeps every try: swipe between them, or
use "‹ 2 of 3 ›" under the reply; hold it to delete a version
(`Conversation.Turn.versions`). The one showing when the author answers is the
one the conversation goes on from, and it stays that once answered (Kevin,
2026-11-24): the switcher goes with the answer. Try Again also reads the
author's message again for filing if nothing came of it the first time and
nothing was undone (`Turn.needsFiling`; his "I think it was actually a
bireme" was first read by E2B, which saw "trireme").
Each reply draws a new seed, so Try Again differs (under AnyLanguageModel,
before the 26B, one seed drawn when the model loaded gave the same words each
time, though temperature was already Gemma's 1.0).

Plain Model (TRIAL, in the menu; Kevin, 2026-11-24: "remove all your rules
and context and prompts so I can see how this actually works as a model"):
the model gets only the conversation, no instructions, examples or pages
(`CompanionPrompt.plain`). It knows nothing of the page but what's been said.
prompt without its example conversations 4.7 (a draw: better openings, worse
corrections and "stuck"), Plain Model 1.6 (98% poor: it took his world for
Star Wars or Hollow Knight, invented names, wrote 100-word help-desk replies).
None of the 366 replies borrowed the examples' names; the "Dolores and the
Regent" Kevin saw came from E2B, which the phone had fallen back to.
Changes (beside the menu in the folded sheet; in the menu unfolded;
`ChangesView`) lists everything filed from the conversation: a stock grouped
list, newest message first, headed by the author's message and when they sent
it; each change a row with an icon for its kind, the page, what it says, and
a small bordered Undo (or "Changed since", as Undo goes newest first). A field
changed more than once opens its timeline (Kevin, 2026-11-24): every value it
was given here, newest first, each with its message and time, the current one
marked, and Undo on the newest (`Conversation.history`).

## The world's own conversation

The World Conversations button at the bottom of the pages list, above search,
opens the world's conversations about the whole world, not one page (Kevin,
2026-11-24: "converse with it and not operate solely within a single page";
then "a list of conversations unless you were already in one, and start fresh
ones"): a stock list in the pages list's place (Pages goes back), newest
first, each titled by the author's first words, with New Conversation; it goes
back into the one the author was in, and with none yet straight into a new
one. As in Messages, the conversation sits beside the list unfolded and over
it folded (Kevin, 2026-11-24: "the conversation list next to the conversation
itself"; `WorldConversationList`, `CompanionPanel(worldConversation:)`).
Each is stored under its own id, marked `aboutWorld`; one exists once
something's been said in it. The model
gets every page as background, the ones bearing on what's being said first,
and no open page (`CompanionPrompt(world:)`). It doesn't speak first: it
waits for the author to write (Kevin, 2026-11-24: "no need for it to think
before prompted"); a conversation can begin with the author's words
(`Conversation.answer` on an empty one). What's said is filed into the pages it names
(`FilingPrompt(world:)`): "she" has no page to mean, so it isn't filed, and
nothing is renamed. Page conversations remember it, as they remember each
other.

## Filing: structure from the conversation

Kevin, 2026-11-23: "Take a free flowing conversation and give it extreme
structure and form without me having to." Tell the companion on Casperica's
page "she's from a thalassocratic nation called Myriddea", and Casperica
becomes a Character with Origin → Myriddea, and a new Place page Myriddea
reads "A thalassocratic nation" (its Mentions show Casperica, through the
link). His rulings: it happens on its own, with **Undo**; only what's said to
the companion is filed, never the page's writing.

- **When:** after each reply to the author's message, so replies never wait
  for it; the next reply waits for it instead (one model, one job at a time).
- **How:** a second, short request on the same model, without thinking and
  greedy (its most likely reading): `FilingPrompt` (instructions with one
  worked example; the open page, the world's types and fields, the other
  pages' titles, what the companion said, and the message). The model writes
  JSON as the example shows, and `Filings.parse` reads each list on its own.
  Not constrained decoding: AnyLanguageModel's took a minute on the phone and
  looped (Kevin's first try, 2026-11-24); plain JSON took 2 to 3 seconds there
  on E4B. Not yet measured on the 26B, which reads the whole filing prompt
  afresh each time, and after it the companion's prompt too (`docs/models.md`).
- **What code guarantees** (`Filer`, tested in WriterKit): every value, new
  page title and new page text is found in the message, in a sentence that
  isn't a question or hedged ("maybe", "might", "what if", "either"); a
  message that states nothing files nothing; a new page needs a capitalised
  name ("Myriddea", not "grandmother"); existing pages, types and fields are
  reused by name ("The Guild of Lamps" is "Guild of Lamps"); a filled field
  changes only in a message that corrects something ("actually", "not"), and
  only untyped pages are typed; a value naming a page links to it;
  a value that only repeats its field ("Grandmother: grandmother") is dropped;
  a value written as a name mid-sentence ("a sword called Mercy") gets a page
  of its own if it has none (the model often files the name without listing
  the page).
- **What shows:** under the companion's reply to the author's message, left-aligned (Kevin, 2026-11-24: filing comes after the reply), *Added to Your Pages*: each
  page made, type given and field filled on its own line with its own Undo
  (Kevin: "each discrete action has its own undo"). Undo takes back what the
  author hasn't changed since; a new type or field nothing uses any more goes
  with it; a page written on since (by the author, or filed into from another
  conversation) goes to Recently Deleted (`FilingRecord.undo`). Undo goes
  newest first for each field and page (Kevin, 2026-11-24, the simpler of two
  ways offered): a line a later message changed (a corrected value, a page
  later facts went on or link to, a type later fields were filled under) is
  greyed, "changed since", until that one is undone
  (`Conversation.changedLater`). Without it, undoing "Vessel: trireme" and
  then "bireme (was trireme)" brought the trireme back. What one message did
  to a page it made goes with that page.

scenarios, then 67 with events, dates and items; the generic ones in git
plus 11 from Kevin's world):

| Prompt | Sampling | Facts filed | New pages made | Filed from questions, hedges, chat |
|---|---|---|---|---|
| First (no example, pages listed first) | chat (temp 1), ×2 | 75/98 (77%) | 15/32 | 2/36 |
| One worked example, facts first | chat, ×2 | 86/96 (90%) | 25/32 | 0/36 |
| + "only when it means just that", "a ship is not a Place" | chat, ×2 | 90/96 (94%) | 29/32 | 0/36 |
| same, with events, dates, items | chat, ×2 | 106/120 (88%) | 36/44 | 0/36 |
| same | greedy | 55/60 (92%) | 17/22 | 0/18 |
| + an event and a date in the example | greedy | 57/60 (95%) | 19/22 | 0/18 |
| same, plain JSON (no constrained decoding) | greedy | 56/60 (93%) | 16/22 | 0/18 |
| + "about" left out when empty, names in values get pages, lists read apart | greedy | 57/60 (95%) | 20/22 | 0/18 |

Kevin's try on the phone (2026-11-24) filed the facts but left Myriddea blank:
against the words the message used for it (two scenarios added, one his own
message; ×2 samples, 65 + 12 scenarios):

| Prompt | Sampling | Facts filed | New pages made | Their description as its text | Filed from questions, hedges, chat |
|---|---|---|---|---|---|
| as above | greedy, ×2 | 120/130 (92%) | 45/50 | 4/18 | 0/36 |
| + an "about" rule with "the fishing village of Holm", two more in the example | greedy, ×2 | 116/130 (89%) | 42/50 | 2/18 | 0/36 |
| "about" right after the title, and on every new page in the example (shipped) | greedy, ×2 | 118/130 (91%) | 44/50 | 14/18 | 0/36 |

The code also drops text that is only part of the page's name ("Lady" for
Lady Corvina) or says what it isn't ("not Port Vell").

Corrections (Kevin on the phone, 2026-11-24: "Actually it's a bireme" after
Vessel: trireme, and nothing happened). The model gave the new value; the
code dropped it, as it filled only empty fields. Now a filled field takes the
new value, shown as "Vessel: bireme (was trireme)" with its own Undo, which
puts the old one back. Seven scenarios added: three corrections and four
facts that mustn't replace one ("her brother is 40", "she was 16 when…"):

| Change | Facts filed | Corrections made | Filled values kept | Filed from questions, hedges, chat |
|---|---|---|---|---|
| filled fields replaced, nothing else | 124/136 (91%) | 6/6 | 12/14 | 0/36 |
| + in the prompt's facts rule: correct only when told; "her age when something happened is not her age" | 100/136 (74%) | 6/6 | 14/14 | 0/36 |
| the same sentence moved to the closing rules | 122/136 (90%) | 6/6 | 14/14, but "when she was nineteen" still replaced her age | 0/36 |
| + the code replaces only in a message with a correcting word ("actually", "not", "sorry", "wait"…) (shipped) | 122/136 (90%) | 6/6 | all | 0/36 |

In the 74% row the model stopped listing the open page with its type, so
facts had no fields to go in; where a rule sits in the prompt matters.

About 2.7 s a message on the computer's GPU. New types come from what's said
(Event, Ship, Object, Organization appeared on their own). Read by hand, about
1 in 30 filings in the shipped run were still wrong (a ship typed as a Place,
"Gull Rock" for "Treaty of Gull Rock", a fact pinned on the wrong page): each
shows as its own line in the conversation, undone in one tap.
Naming the open page's subject renames it (Kevin on the phone, 2026-11-24:
"Her name is Florica" on Casperica made a new page Florica and a Name field).
A fact on the open page whose field is Name, Full name or Called, in the
author's words and capitalised, becomes the page's title, with Undo; links to
it follow (`Library.commit`), and the title on screen updates. Facts by the new
name land on the same page; an untitled page gets its name this way. Other
×2: all renamed or not as they should; overall facts 91%, nothing filed from
questions or guesses.

Not yet: a change over time that isn't worded as a correction ("she moved
to Calloway") leaves the old value, and the
page's own writing isn't read.

## Changing it

   `variants.py` that swaps it in for the app's.
   (`make_scenarios.py`; Kevin's own world adds more from the git-ignored
   `private/`). `python3 checks.py NAME` gives a first number in seconds:
   automatic pass/fail checks for the failures seen most. They don't measure
   how good a reply is.
4. Only then move the text into `CompanionPrompt.swift`. Its tests pin the
   builds, so what was measured is what ships.

`phone` rendering (AnyLanguageModel's, as the app sent E4B its prompt) or the
model file's own template. Since the 26B the app renders the prompt itself
(`TurboModel.chat`: no tools, and with thinking off its thought channel comes
(`gemma_format.render_turbo`); measurements of the 26B use that.
