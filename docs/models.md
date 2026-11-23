# Model selection and licence validation

Validated 2026-11-20. Your initial picks were treated as suggestions; each
function uses the best-fitting openly licensed model that runs on an iPhone.

| Function | Recommended | Licence | Runtime | Size | Was suggested |
|---|---|---|---|---|---|
| Search by meaning | **Qwen3-Embedding-0.6B** (Q8_0 GGUF) | Apache-2.0 | llama.cpp (MIT) | ~640 MB | EmbeddingGemma 300M |
| Re-ranking (optional) | Qwen3-Reranker-0.6B | Apache-2.0 | llama.cpp | ~640 MB | — |
| Writing companion | **Gemma 4 E2B** (Q4_K_M), through AnyLanguageModel | Apache-2.0 | llama.cpp | ~3.1 GB (+1 GB vision) | "Qwen3-1.7B Socratic" |
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
unasked, no pointless questions). Of the models that fit the phone with vision,
Gemma 4 E2B scored best (4.6/10; 5.2 with thinking on, a significant gain);
Qwen3.5-4B scored 3.5 and invented something in half its replies. Gemma 4 26B
(MoE, ~14 GB) scored best overall (6.5) but doesn't fit in the phone's memory.
On the Duo, E2B replies start in ~0.2 s after a ~12 s first load. It runs
through Hugging Face's AnyLanguageModel (Foundation Models' session API over
llama.cpp), with Gemma's recommended sampling (temperature 1, top-p 0.95,
top-k 64).

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

- **Apache-2.0** (Qwen models, llama.cpp is MIT): include notices in
  Acknowledgements.
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
