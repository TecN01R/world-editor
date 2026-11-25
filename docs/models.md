# Model selection and licence validation

Validated 2026-11-20. Your initial picks were treated as suggestions; each
function uses the best-fitting openly licensed model that runs on an iPhone.

| Function | Recommended | Licence | Runtime | Size | Was suggested |
|---|---|---|---|---|---|
| Search by meaning | **Qwen3-Embedding-0.6B** (Q8_0 GGUF) | Apache-2.0 | llama.cpp (MIT) | ~640 MB | EmbeddingGemma 300M |
| Re-ranking (optional) | Qwen3-Reranker-0.6B | Apache-2.0 | llama.cpp | ~640 MB | — |
| Writing companion | **Nemotron 3.5 Bolt E4B** (bartowski's Q4_K_M GGUF) | OpenMDW-1.1 (post-trained from Gemma 4 E4B, Apache-2.0) | llama.cpp (MIT) | 5.2 GB in storage, ~3.5-4 GB in memory | Gemma 4 |
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

**Gemma 4 E2B for the companion** (chosen 2026-11-23, replacing Qwen3.5-4B).
On the Duo, E2B writes about 50 tokens a second after a ~12 s first load. It ran
through Hugging Face's AnyLanguageModel (Foundation Models' session API over
llama.cpp), with Gemma's recommended sampling (temperature 1, top-p 0.95, top-k
64, no repetition penalty).

**Gemma 4 E4B was the companion's model** (a trial from 2026-11-23; standard on
2026-11-24, Kevin: "E4B shouldn't be trial now"), the 4.2 GB build
(`unsloth/gemma-4-E4B-it-qat-GGUF`, UD-Q4_K_XL). The Duo holds it in memory,
replying in a few seconds.

**Gemma 4 26B-A4B was the companion's model** (2026-11-24 to 2026-11-25). It
doesn't fit in the phone's memory whole, but only ~4B of its parameters work per
token: TurboFieldfare (Swift + Metal, Apache 2.0) kept ~2 GB in memory and
streamed the experts each token needs from storage. On the Duo it wrote about 7
tokens a second and read its prompt slowly (30 s for 1,650 tokens), and an iPhone
15 Pro would be slower still.

**The 26B, tried again on the higher memory limit** (2026-11-25, debug builds,
removed the same day). With the patched xtool the app has about 6.4 GB on the
Duo, and the 26B kept 32 experts a layer in memory instead of 16. Its first
reply still hadn't finished after more than three minutes, and Kevin dropped
it: "too slow ... go back to the previous model and then continue our search
for an even faster more powerful model". Its download, TurboFieldfare's
installer, had also refused it at first: that installer counted only empty
space, not what iOS clears for a download (6.8 GB of 70).

**Ling-3.0-tiny** (inclusionAI) was tried stock on 2026-11-25 as a faster
alternative and not taken: the bar is faster *and* stronger (Kevin).

**Nemotron 3.5 Bolt E4B is the companion's model** (Kevin, 2026-11-25: "Yes",
after the shortlist for 8 GB+ iPhones). NVIDIA post-trained it from Gemma 4
E4B for multi-turn tool use and instruction following. It runs stock (Kevin:
"only run models stock from now on"), with NVIDIA's thinking cap of 128 tokens.
It reads a prompt in seconds and writes well above reading speed, so it needs
no saved cache, and it fits the 15 Pro's memory.

How it runs (`LlamaModel`): llama.cpp's prebuilt Apple framework, release
b12633 (`scripts/fetch-llama.sh`, checksum checked), on the GPU through Metal.
The model is bartowski's 4-bit file
(`bartowski/NVIDIA-Nemotron-3.5-Bolt-E4B-GGUF`,
`NVIDIA-Nemotron-3.5-Bolt-E4B-Q4_K_M.gguf`, 5.2 GB) at one pinned revision with
its SHA-256, rather than NVIDIA's own 4-bit file (6.2 GB, its embeddings at 8 bits).
Its per-layer embeddings (1.9 GB) stay in storage and are read a row at a time
(llama.cpp's lazy reading), so about 2.3 GB of weights are in memory, plus
about 0.3 GB for the conversation (8,192 tokens; its sliding-window layers keep
only their window, and room is made for one token's output at a time), about
2.6 GB in all: the Duo gives the app about 3.4 GB. A follow-up reads only from
where its prompt differs from the last, unless that's further back than the
window still covers, when it reads from the start (as llama.cpp's server does).

The prompt is the model file's own chat template, rendered by the app
(`GemmaChat`, tested against what llama.cpp's server renders from that
template). The model thinks before each reply; once its thought has run
128 tokens, the end of its thought is forced, as llama.cpp's server does with
`--reasoning-budget 128` (`ThinkingBudget`), and each thought after a search
gets its own 128. It looks things up with `search_pages` (two searches a
reply, then "that's the last search"; three calls at most, after which, or if
it says nothing, it is asked once more without the tool). What it searched
for shows in its collapsed thinking. Sampling is NVIDIA's (temperature 1,
top-p 0.95, top-k 64 as the file says, a new seed each reply); filing is
greedy without thinking, which is faster.

The download goes over Wi-Fi only, in one file with HTTP range requests, so
it resumes from where it stopped, even after the app is closed; on cellular,
a hotspot or Low Data Mode it waits and says why. A connection that keeps
failing pauses it (Download Paused). Before it starts it checks there's room
(the rest of the file and half a gigabyte). Once it's all here the whole file
is checked against its SHA-256; a damaged one is removed and the download
offered again. Once the model has loaded, the app deletes the 26B's files
(14.3 GB) and any older models'. iOS gives a background app no GPU, so leaving
the app stops a reply or filing before its next piece of GPU work; once the
author is back, a reply goes on from what it had written and filing starts
over. The screen stays on while the model works.

First measured on the Duo (2026-11-25, `candidates.log`): it loads in 3.3 s;
the memory iOS counts against the app went from 3.46 GB free to 3.15 GB (the
weights read from storage aren't counted), 3.10 GB after a reply; it read a
1,795-token prompt in 1.3 s and wrote 23 tokens a second; the first words came
7.4 s after asking, the load included; filing took 1.1 s. Still to measure: a
long conversation, heat over time, and how it does held to the 15 Pro's memory.

**Updates to the companion's model.** It comes from one pinned revision and
checksum, so the menu offers no updates: a new one arrives with the app.

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

- **OpenMDW-1.1** (Nemotron 3.5 Bolt E4B): use, change and share freely,
  outputs unrestricted; whoever distributes the model keeps the licence and
  NVIDIA's notices with it. The app downloads it from NVIDIA's repository
  rather than shipping it; Acknowledgements should still carry the licence.
  Its base, Gemma 4 E4B, is Apache-2.0.
- **Apache-2.0** (Qwen and Gemma models) and **MIT** (llama.cpp): include
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
