# The companion: how it's prompted, and why

The companion is a language model running on the phone (NVIDIA's Nemotron 3.5
Bolt E4B since 2026-11-25, Gemma 4 26B-A4B before; `docs/models.md`). What it says is decided by three things: which
model it is, the text it's given before the conversation (its prompt), and how
its output is sampled. This page records what those are and the reasons.
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

**Since 2026-11-25: the model stock, with its tools.** Kevin, after trying
Plain Model on the phone: "I want you to only run models stock from now on and
only put stock models on my phone, with tools of course." Offered one
instruction on content of its own, he chose none ("fully stock"). The system
turn is one line saying which page is open (its title), or which world, about
the whole world; then the conversation, with `list_pages`, `search_pages` and
`look_up` declared in the model's own chat format (`CompanionPrompt.plain`,
built in `Companion.ask`). No instructions, no examples. Sampling and the
thinking cap are the model maker's (`docs/models.md`).

**Since 2026-11-26: the open page itself.** Kevin: "obviously the companion
should get the open page's text". The page as it is at that moment (title,
type, filled fields, writing) goes with the writer's latest message, as an
attached document does (`CompanionPrompt.shown`); a page past 12,000 characters
goes as its opening and its latest part. It goes with the latest message, not
in the system turn, so the earlier turns stay as the model last read them: a
page edited between messages costs re-reading the page and the last exchange,
not the whole conversation. The other pages it still finds with its tools.

**Instructions grow from the author** (Kevin, 2026-11-25: "keep the prompting
but keep it blank and the user can fill in instructions over time and the model
can write its own instructions based on what the user tells it to do"). The
author's standing instructions (`Instructions`) are blank at first. They edit
them in Instructions… in the companion's menu, and the companion adds one with
a fourth tool, `add_instruction` (at most two a reply), when they tell it how
to reply from now on. Shown in the prompt under "The writer's instructions for
you:", after the line on what's open; "Added to Instructions: …" under the
reply opens them. One set for every world, kept on the phone. After a change
to them, old conversations keep the old manner: a model copies the manner of its
own earlier replies, which are in front of it. Start a new conversation to see
the change.

**No limits of the app's own** (Kevin, 2026-11-25: "you WILL lift the limits"):
the whole conversation goes in, read from a later point only when it outgrows
the model's context (16K tokens); every tool call is answered, with no budget
per reply (only a runaway loop, 10 calls, is asked to answer without tools); a
search of their pages returns up to 6,000 characters and a look-up up to 12,000,
every article found read; replies run until the model ends them. The thinking cap
(128 tokens) is NVIDIA's setting.

**Until then** it had the full prompt below, which stays in WriterKit, unused by
the app, until it's removed. Built by `CompanionPrompt` (WriterKit). One system
turn, in this order, then the conversation:

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
   it named her. Then: the opening of the writer's other pages (those sharing words
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
when the author begins instead (a reply is seconds of the GPU's work).

Sampling is NVIDIA's (and Google's for Gemma 4): temperature 1.0, top-p 0.95,
top-k 64, no repetition penalty. It thinks before each reply, briefly, and
there's no switch for it (Kevin, 2026-11-24: "remove the thinking switch"):
NVIDIA runs the model thinking. Its thought is capped at 128 tokens, NVIDIA's
setting, as llama.cpp's server caps it with `--reasoning-budget 128`
(`ThinkingBudget`). On the 26B, Gemma's thinking had drafted each reply four
or five times at the phone's 7 tokens a second, so replies there didn't think.
It looks things up in the writer's pages with `search_pages` (the prompt's
tools mode: the open page, the pages most like it, the rest by name), and what
it searched for shows in its collapsed thinking. Earlier thinking is never
sent back to it. The app renders the model file's own chat template itself
(`GemmaChat`, tested against llama.cpp's rendering) and reads its thought
channel, so the thinking shows, collapsed, as it comes. Anything in the
writer's text that Gemma would read as one of its control tokens is defused
first (`Reasoned.gemmaPlain`).

It looks up the real world on Wikipedia when it isn't sure (`look_up`; Kevin,
2026-11-25), with one more reply case in its instructions
(`CompanionPrompt.lookUpInstruction`): what it looked up shows under the reply with
the articles it read. Look Things Up in its menu turns it off; a look-up never sends a name of theirs.

Kevin can replace the instructions and the examples himself (Kevin, 2026-11-25:
"a settings panel for me to modify instructions myself"; "only available in
debug mode of course"): Instructions… in the companion's menu of a debug build,
iOS's own form, kept on the phone (`CompanionPrompt.Texts`); a release build has
neither the panel nor his text, and always reads the app's own.
His text is used as he wrote it, from the next reply; empty examples are left
out; Restore Defaults puts back the app's own, which the rest of this page
describes. Search and the pages work the same whatever
the instructions say, and nothing in them can make it write into his pages.

## Why it's shaped this way

Each choice below comes from what was tried or from the model's maker; the
sources are named so they can be checked.

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
improve. What takes its place is the prompt itself.

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

Plain Model (a TRIAL in the menu from 2026-11-24, the companion itself from 2026-11-25,
above; Kevin, 2026-11-24: "remove all your rules
and context and prompts so I can see how this actually works as a model"):
the model gets only the conversation, no instructions, examples or pages
(`CompanionPrompt.plain`), and, since 2026-11-25, the tools, described as their
declarations describe them (Kevin: "Can the plain model at least have access to
the tools and how those work? Otherwise it's kind of useless"), and one line
saying which page is open (its title), or which world, about the whole world:
it can search the pages and look up the real world, but is told nothing else
(since 2026-11-26 it's also given the open page, above).
Since it isn't shown their pages, it also has `list_pages` (their pages by name,
type and opening, or one type's), without which "what can you tell me about my
world?" gave its search nothing to look for (Kevin: "I don't think the tools are
working fully with the base model").

Changes (beside the menu in the folded sheet; in the menu unfolded;
`ChangesView`) lists everything filed from the conversation: a stock grouped
list, newest message first, headed by the author's message and when they sent
it; each change a row with an icon for its kind, the page, what it says, and
a small bordered Undo (or "Changed since", as Undo goes newest first). A field
changed more than once opens its timeline (Kevin, 2026-11-24): every value it
was given here, newest first, each with its message and time, the current one
marked, and Undo on the newest (`Conversation.history`).

## The world's own conversation

**Since 2026-11-27 it's where the author starts** (Kevin: "I want to write it
conversationally or in any messy way and be able to refine it back and forth and
that populates my pages"). The app opens in the world's conversation, no page
open, and it's in front whenever no page is: the last one open, else the newest,
else a new one (`RootView`). The pages list is where the author reads their
world; its Conversation row at the top (a place in the list, as Mail lists
mailboxes, so the only chat button is a page's own companion; Kevin, 2026-11-24:
"which assistant is which?") goes back to the conversation. The conversation's
menu starts a new one, and Conversations… lists the others in a sheet, newest
first, each titled by the author's first words (`WorldConversationList`,
`CompanionPanel(worldConversation:)`). Before that (2026-11-24), the row opened
the list of conversations in the pages list's place, with the one chosen beside it.
Each conversation is stored under its own id, marked `aboutWorld`; one exists once
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

- **When:** once the conversation pauses: the companion closed, another page
  or conversation opened, or two minutes after a reply with no message (Kevin,
  2026-11-24). Filing reads its own prompt on the model's one cache, so filing
  after every reply made the next reply read the whole conversation again
  (20–30 s on the 26B). A message sent, or Try Again, while it files stops
  it; it picks up at the next pause. A reply prepared on opening a page waits
  for it.
- **How:** a second, short request on the same model, without thinking and
  greedy (its most likely reading): `FilingPrompt` (instructions with one
  worked example; the open page, the world's types and fields, the other
  pages' titles, what the companion said, and the message). The model writes
  JSON as the example shows, and `Filings.parse` reads each list on its own.
  Not constrained decoding: AnyLanguageModel's took a minute on the phone and
  looped (Kevin's first try, 2026-11-24); plain JSON took 2 to 3 seconds there
  on E4B. Not yet measured on the phone with Nemotron.
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

Kevin's try on the phone (2026-11-24) filed the facts but left Myriddea blank:
the model rarely gave a new page its text, so the prompt now asks for it
("about") right after each new page's title, and on every new page in its
example. The code also drops text that is only part of the page's name ("Lady"
for Lady Corvina) or says what it isn't ("not Port Vell").

Corrections (Kevin on the phone, 2026-11-24: "Actually it's a bireme" after
Vessel: trireme, and nothing happened). The model gave the new value; the
code dropped it, as it filled only empty fields. Now a filled field takes the
new value, shown as "Vessel: bireme (was trireme)" with its own Undo, which
puts the old one back, but only in a message with a correcting word
("actually", "not", "sorry", "wait"…), so facts like "her brother is 40" or
"she was 16 when…" don't replace one.

New types come from what's said (Event, Ship, Object, Organization). A wrong
filing (a ship typed as a Place, a fact pinned on the wrong page) shows as its
own line in the conversation, undone in one tap.
Naming the open page's subject renames it (Kevin on the phone, 2026-11-24:
"Her name is Florica" on Casperica made a new page Florica and a Name field).
A fact on the open page whose field is Name, Full name or Called, in the
author's words and capitalised, becomes the page's title, with Undo; links to
it follow (`Library.commit`), and the title on screen updates. Facts by the new
name land on the same page; an untitled page gets its name this way. Other
names stay fields ("Her mother's name is Ilinca").

Not yet: a change over time that isn't worded as a correction ("she moved
to Calloway") leaves the old value, and the
page's own writing isn't read.

## Changing it

Kevin's method (2026-11-25): "Once we know how models react to our content
stock we can use that as a baseline to see whether our instructions improve or
harm it, tailored to each model." He judges the companion by using it
(2026-11-25); a test suite from an open standard, built around how the app is
used, is still to be chosen (`docs/todo.md`).
