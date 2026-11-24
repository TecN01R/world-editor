# Model selection and licence validation

Validated 2026-11-20. Your initial picks were treated as suggestions; each
function uses the best-fitting openly licensed model that runs on an iPhone.

| Function | Recommended | Licence | Runtime | Size | Was suggested |
|---|---|---|---|---|---|
| Search by meaning | **Qwen3-Embedding-0.6B** (Q8_0 GGUF) | Apache-2.0 | llama.cpp (MIT) | ~640 MB | EmbeddingGemma 300M |
| Re-ranking (optional) | Qwen3-Reranker-0.6B | Apache-2.0 | llama.cpp | ~640 MB | — |
| Writing companion | **Gemma 4 26B-A4B** (mlx-community 4-bit, repacked on the phone) | Apache-2.0 | TurboFieldfare (Apache-2.0) | 14.3 GB in storage, ~2-3.4 GB in memory | same |
| Facts & continuity | **Apple Foundation Models** (on-device) | System framework | iOS 26+ | 0 (built in) | same |
| Illustration | **Stable Diffusion 1.5** + **ControlNet 1.1** (Core ML) | CreativeML OpenRAIL-M | apple/ml-stable-diffusion | ~2.1 GB + ~0.7 GB | same |

## Why these

**Qwen3-Embedding-0.6B over EmbeddingGemma 300M.** Higher on text retrieval
(Google's own EmbeddingGemma 2 report lists MTEB Multilingual v2: 64.34 for
Qwen3-Embedding-0.6B vs 61.15 for EmbeddingGemma 300M), a 32K-token context so
whole notes embed without chunking, and Apache-2.0. EmbeddingGemma uses the
Gemma Terms of Use: redistribution needs the terms passed on plus a NOTICE,
and §3.2 lets Google "restrict (remotely or otherwise)" use. The cost is size
(~640 MB vs ~300 MB). EmbeddingGemma remains a drop-in alternative if space matters
more than quality.

**Gemma 4 E2B for the companion** (chosen 2026-11-23 by test, replacing
Qwen3.5-4B). A first test put 14 models through 91 moments of conversation,
pointless questions). Of the models that fit the phone with vision, Gemma 4
E2B scored best; Qwen3.5-4B invented something in half its replies. Gemma 4
26B (MoE, ~14 GB) scored best overall. It doesn't fit in the phone's memory
whole, but it needn't: only ~4B of its parameters work per token, and
TurboFieldfare (Swift + Metal, Apache 2.0) keeps ~2 GB in memory and streams
the experts each token needs from storage. Another app (Vehla) reports 6 to 10
tokens a second with it on an iPhone. It became the companion's model on
2026-11-24 (below). On the Duo, E2B writes about 50 tokens a second after a
~12 s first load. It ran through Hugging Face's AnyLanguageModel (Foundation
Models' session API over llama.cpp), with Gemma's recommended sampling
(temperature 1, top-p 0.95, top-k 64, no repetition penalty).

**Gemma 4 E4B was the companion's model** (a trial from 2026-11-23; standard on 2026-11-24, Kevin: "E4B shouldn't be trial now"). With the current prompt
(`docs/companion.md`) the 4.2 GB build (`unsloth/gemma-4-E4B-it-qat-GGUF`,
UD-Q4_K_XL) scores 5.2 out of 10 where E2B scores 4.5, and breaks one of
Kevin's rules in 9% of replies where E2B does in 24%. What wasn't known yet
was whether the Duo holds it in memory and how fast it runs there: it does,
replying in a few seconds. The 3.2 GB "mobile" 2-bit build of E4B and
is.

**Gemma 4 26B-A4B is the companion's model** (Kevin, 2026-11-24: one model on
the phone, presented as the only one, no switch; "when the work is ready
replace"). It replaced E4B with no trial and no fallback: once it has loaded,
the app deletes E4B's and E2B's files from the phone, and llama.cpp and
AnyLanguageModel are gone from the app. Why: it scored best of the 14 models
in the first blind test (6.5 out of 10, 93% of replies breaking none of
Kevin's rules, thinking off), where E4B scores 5.2 on today's prompt. That
test was on older instructions, and on inventing alone it was not the best (4%
of replies against 1% for the E4B build tested then), so it still needs a run

How it runs (`TurboModel`): TurboFieldfare 0.10.1, pinned to its commit
(`scripts/fetch-turbo-fieldfare.sh` adds one line to its manifest so the app
can use its installer, which upstream builds only into its own tools). The
first time, the phone downloads 14.6 GB from `mlx-community/gemma-4-26b-a4b-it-4bit`
at one checked revision (the installer refuses any other) and repacks it as it
arrives into 14.3 GB in Application Support, out of iCloud backups, shown
with Foundation's download wording and kept going in the background as before.
The download is a task of its own, so opening another page doesn't stop it.
It goes only over Wi-Fi: on cellular, a hotspot or Wi-Fi in Low Data Mode it
waits and says why, and goes on once back on Wi-Fi. Only a connection that
keeps failing pauses it (Download Paused: three tries a minute apart that get
no further, after the installer's own), and it resumes from where it got to,
once it has read back and checked what it has. Before it starts, it checks
there's room (the model, the installer's 1 GB reserve and the 64 MB part being
downloaded: about 15.4 GB, less what an earlier try got); if there isn't, the
offer says how much it needs. Every file is checked once after install; loading
then trusts that check for the experts (12.9 GB) and checks the 1.35 GB every
token uses each time. A model whose files fail their check when it loads is
removed, and the download is offered again. Loading runs on the model's own
thread, as replies do. Its shaders compile on the phone, from source, when it
loads (whether iOS keeps them between launches isn't known). Gemma's chat
format is rendered by the app (TurboFieldfare's own has no thinking), with
Google's sampling and a new seed each reply; filing is greedy
without thinking. iOS gives a background app no GPU, so leaving the app stops
a reply or filing mid-way; it begins again from the start once the author is
back, and one asked for while they're away waits for them. The screen stays on
while the model works, since locking it also takes the app to the background.
The companion prepares a page's first reply only while it's open (each is
minutes of the GPU's work on this model), and not while the phone is hot or in
Low Power Mode, when the author begins instead.

Not yet measured on the Duo (the app logs each to `candidates.log`: LOAD,
SPEED, FILING): its GPU family and largest buffer (the 1.35 GB is one Metal
buffer), how much memory iOS gives the app, how long loading takes, how fast
it reads a prompt and writes (Vehla: 6 to 10 tokens a second), heat, and
whether iOS closes the app for memory. The wait before the first word is the
expected cost: every reply reads its whole prompt (2,000 to 4,500 tokens),
since the background changes with each message and filing reads its own
prompt in between, and TurboFieldfare can keep what it has read only while a
prompt adds to the last one. On a Mac M2 it read 1,000 tokens in 37 seconds.
Debug builds (`scripts/run-on-phone.sh`) are slower than a release build
(`xtool dev build -c release`).

**Updates to the companion's model.** The 26B comes from one checked
revision (TurboFieldfare's pin: the repository's commit and the SHA-256 of its
index), so the menu offers no updates: a new revision arrives with a new
TurboFieldfare in the app, and is measured first, since it may not behave as
the one the instructions were measured on (`docs/companion.md`). The menu
shows which model is running, when it was downloaded, and the app's version.
`ModelCatalog` (the charter's pinned list) holds one URL and checksum per
model, which doesn't fit a download in ranges; it needs an entry shaped as
repository, revision and index checksum before the app goes to anyone else.

**Apple Foundation Models for extraction.** Built into iOS (no download),
guided generation returns typed structures, and it runs on the Neural Engine.
iOS 27 can also route the same API to server models (Private Cloud Compute,
third-party providers); the app only ever constructs `SystemLanguageModel.default`.

**SD 1.5 + ControlNet.** The most mature phone-sized diffusion stack with Core
ML conversions, ControlNet conditioning and inpainting masks: exactly the
controls needed to keep unknown areas unpainted. Larger, newer models
(SDXL, SD3.x, FLUX) don't fit an iPhone's memory comfortably and offer less
spatial control at this size. Apple Image Playground can't be constrained.

## Obligations

- **Apache-2.0** (Qwen and Gemma models; TurboFieldfare, swift-transformers,
  MIT; swift-crypto and swift-asn1 have NOTICE files to reproduce): include
  the licences and notices in Acknowledgements (the app has none yet).
- **CreativeML OpenRAIL-M** (SD 1.5, ControlNet conversions): show the use
  restrictions (Attachment A) before first download and include the licence.
  Users must agree to the restrictions.
- **Apple Foundation Models:** Apple's acceptable-use requirements for the
  framework apply.

## Not yet done (before any model is enabled)

- Pin the exact file URL and SHA-256 for each model in `ModelCatalog`
  (downloads stay disabled until then).
- Verify that each GGUF/Core ML build loads and runs within memory on the iPhone Duo.
- Confirm the licence of `apple/ml-stable-diffusion` and the exact ControlNet
  1.1 Core ML conversion used, and record it here.
