// llama.cpp ships for devices only (no simulator slice): the simulator, as in
// CI's screenshots, builds without it and the companion uses Apple's model.
#if canImport(llama)
import Foundation
import llama
import os

/// A Qwen3.5 model through llama.cpp, on the device. Loads on first use and
/// stays loaded (memory-mapped, so it costs little until used); one reply at
/// a time. Knows nothing about conversation: `Companion` decides what to ask it.
actor LlamaModel {
    nonisolated let fileName: String
    init(fileName: String) { self.fileName = fileName }

    enum Failure: Error { case missing, load, context, decode }

    /// Where the model lives once downloaded (Application Support, not backed
    /// up). TEMPORARY: also the Documents copy pushed for the Phase 0 spike,
    /// until the in-app download exists.
    nonisolated var url: URL? {
        let stored = URL.applicationSupportDirectory.appendingPathComponent("Models/\(fileName)")
        let pushed = URL.documentsDirectory.appendingPathComponent(fileName)
        return [stored, pushed].first { FileManager.default.fileExists(atPath: $0.path) }
    }

    private var model: OpaquePointer?

    deinit { if let model { llama_model_free(model) } }

    private func loaded() throws -> OpaquePointer {
        if let model { return model }
        guard let url else { throw Failure.missing }
        llama_backend_init()
        var params = llama_model_default_params()
        params.n_gpu_layers = 99   // all on the GPU
        let before = os_proc_available_memory(), clock = ContinuousClock.now
        guard let m = llama_model_load_from_file(url.path, params) else { throw Failure.load }
        trialLog("LOADED \(fileName) in \(ContinuousClock.now - clock); memory left \(gigabytes(before)) before, \(gigabytes(os_proc_available_memory())) after")   // TRIAL
        model = m
        return m
    }

    /// Generates a reply to `prompt` (already in the model's chat format),
    /// handing `partial` the reply so far as it grows. Stops early if the
    /// calling task is cancelled.
    func reply(to prompt: String, maxTokens: Int = 400, temperature: Float = 0.7,
               partial: (@Sendable (String) -> Void)? = nil) throws -> String {
        let model = try loaded()
        var params = llama_context_default_params()
        params.n_ctx = 8192
        params.n_batch = 512
        guard let ctx = llama_init_from_model(model, params) else { throw Failure.context }
        defer { llama_free(ctx) }
        let vocab = llama_model_get_vocab(model)

        var tokens = Self.tokenize(vocab, prompt)
        let room = Int(params.n_ctx) - maxTokens
        if tokens.count > room { tokens = Array(tokens.suffix(room)) }   // the prompt builder keeps it shorter
        let began = ContinuousClock.now   // TRIAL: speed
        var start = 0
        while start < tokens.count {
            let n = min(Int(params.n_batch), tokens.count - start)
            let status = tokens.withUnsafeMutableBufferPointer { buf in
                llama_decode(ctx, llama_batch_get_one(buf.baseAddress! + start, Int32(n)))
            }
            guard status == 0 else { throw Failure.decode }
            start += n
        }

        let sampler = llama_sampler_chain_init(llama_sampler_chain_default_params())!
        defer { llama_sampler_free(sampler) }
        llama_sampler_chain_add(sampler, llama_sampler_init_temp(temperature))
        llama_sampler_chain_add(sampler, llama_sampler_init_top_p(0.9, 1))
        llama_sampler_chain_add(sampler, llama_sampler_init_dist(UInt32.random(in: 0...UInt32.max)))
        let read = ContinuousClock.now
        var bytes: [UInt8] = [], generated = 0
        defer {   // TRIAL: speed and memory, per reply
            trialLog("SPEED \(fileName): read \(tokens.count) tokens in \(read - began), wrote \(generated) in \(ContinuousClock.now - read); memory left \(gigabytes(os_proc_available_memory()))")
        }
        for _ in 0..<maxTokens where !Task.isCancelled {
            generated += 1
            var token = llama_sampler_sample(sampler, ctx, -1)
            if llama_vocab_is_eog(vocab, token) { break }
            var piece = [CChar](repeating: 0, count: 64)
            let n = llama_token_to_piece(vocab, token, &piece, 64, 0, false)
            if n > 0 {
                bytes += piece[0..<Int(n)].map { UInt8(bitPattern: $0) }
                // Only whole characters: a token can end partway through one.
                if let partial, let text = String(bytes: bytes, encoding: .utf8) { partial(text) }
            }
            guard llama_decode(ctx, llama_batch_get_one(&token, 1)) == 0 else { break }
        }
        return String(decoding: bytes, as: UTF8.self)
    }

    /// Frees the model (memory pressure, or the companion closed for good).
    func unload() {
        if let model { llama_model_free(model) }
        model = nil
    }

    private static func tokenize(_ vocab: OpaquePointer?, _ text: String) -> [llama_token] {
        let count = Int32(text.utf8.count)
        var tokens = [llama_token](repeating: 0, count: Int(count) + 8)
        let n = llama_tokenize(vocab, text, count, &tokens, Int32(tokens.count), true, true)
        return Array(tokens.prefix(Int(max(0, n))))
    }
}

private func gigabytes(_ bytes: Int) -> String { String(format: "%.2f GB", Double(bytes) / 1e9) }
#endif
