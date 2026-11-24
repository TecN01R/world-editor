# The companion: how it's prompted, and why

The companion is a small language model running on the phone. What it says is
decided by three things: which model it is, the text it's given before the
conversation (its prompt), and how its output is sampled. This page records
what those are, the reasons, and the measurements behind them, so the next
change starts from evidence. `docs/companion-roadmap.md` covers what isn't
built yet (web search, images, documents).

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
model's conversation has to begin with the other side.

Sampling is Google's for Gemma 4: temperature 1.0, top-p 0.95, top-k 64, no
repetition penalty. It thinks before it replies (Gemma's `<|think|>`) unless
the author switches that off in the companion's menu, and its earlier thinking
is never sent back to it. On the phone the thinking is the
wait before a reply (4 to 8 seconds on E2B, measured), and it can't be shown:
AnyLanguageModel removes Gemma's thought channel from what it hands the app. Anything in the writer's text that
Gemma would read as one of its control tokens is defused first
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

## Changing it

   `variants.py` that swaps it in for the app's.
   (`make_scenarios.py`; Kevin's own world adds more from the git-ignored
   `private/`). `python3 checks.py NAME` gives a first number in seconds:
   automatic pass/fail checks for the failures seen most. They don't measure
   how good a reply is.
4. Only then move the text into `CompanionPrompt.swift`. Its tests pin the
   builds, so what was measured is what ships.
