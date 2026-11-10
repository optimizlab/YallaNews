#include "yalla_core.h"
#include <string>
#include <atomic>
#include <thread>
#include <mutex>
#include <condition_variable>
#include <vector>
#include <deque>
#include <cstring>
#include <sstream>

#include "llama.h"

struct YallaInferenceEngine {
    YallaModelManagerHandle model_manager;
    std::string loaded_model_id;
    int32_t context_size = 4096;
    int32_t max_batch_size = 1;
    std::atomic<bool> busy{false};
    std::atomic<bool> cancel_requested{false};
    std::mutex inference_mutex;

    // llama.cpp handles
    llama_model* llama_model = nullptr;
    llama_context* llama_context = nullptr;
    llama_sampler* llama_sampler = nullptr;

    // Sampling parameters
    float temperature = 0.7f;
    float top_p = 0.9f;
    int32_t top_k = 40;
    float repeat_penalty = 1.1f;
    int32_t repeat_last_n = 64;
    int32_t mirostat = 0;
    float mirostat_tau = 5.0f;
    float mirostat_eta = 0.1f;

    // Token buffer for generation
    std::vector<llama_token> prompt_tokens;
    std::vector<llama_token> generated_tokens;
    size_t prompt_len = 0;

    // Backend initialized flag
    static std::atomic<bool> backend_initialized;

    bool load_llama_model(const std::string& model_path) {
        // Load model
        llama_model_params model_params = llama_model_default_params();
        model_params.n_gpu_layers = -1; // Offload all layers to GPU if available
        model_params.split_mode = LLAMA_SPLIT_MODE_NONE;
        model_params.load_mode = LLAMA_LOAD_MODE_MMAP;
        model_params.main_gpu = 0;
        model_params.tensor_split = nullptr;
        model_params.lazy_mode = LLAMA_LAZY_MODE_AUTO;
        model_params.check_tensors = true;
        model_params.vocab_only = false;
        model_params.use_extra_bufts = false;
        model_params.no_host = false;
        model_params.no_alloc = false;

        // Progress callback for loading
        model_params.progress_callback = [](float progress, void* user_data) -> bool {
            auto* engine = static_cast<YallaInferenceEngine*>(user_data);
            if (engine->cancel_requested) return false;
            if (engine->progress_cb) {
                engine->progress_cb(static_cast<int32_t>(progress * 100), "Loading model...", engine->progress_user_data);
            }
            return true;
        };
        model_params.progress_callback_user_data = this;

        llama_model = llama_model_load_from_file(model_path.c_str(), model_params);
        if (!llama_model) {
            return false;
        }

        // Create context
        llama_context_params ctx_params = llama_context_default_params();
        ctx_params.n_ctx = context_size > 0 ? static_cast<uint32_t>(context_size) : 4096;
        ctx_params.n_batch = 512;
        ctx_params.n_ubatch = 512;
        ctx_params.n_seq_max = 1;
        ctx_params.n_threads = std::max(1, static_cast<int>(std::thread::hardware_concurrency()) - 1);
        ctx_params.n_threads_batch = std::max(1, static_cast<int>(std::thread::hardware_concurrency()));
        ctx_params.embeddings = false;
        ctx_params.offload_kqv = true;
        ctx_params.flash_attn_type = LLAMA_FLASH_ATTN_TYPE_AUTO;
        ctx_params.no_perf = false;

        // Build sampling chain
        llama_sampler_chain_params sparams = llama_sampler_chain_default_params();
        llama_sampler = llama_sampler_chain_init(sparams);

        // Add samplers in order: penalties -> top_k -> top_p -> temp -> dist
        llama_sampler_chain_add(llama_sampler, llama_sampler_init_penalties(
            llama_vocab_n_tokens(llama_model_get_vocab(llama_model)),
            repeat_last_n, repeat_penalty, 0.0f, 0.0f
        ));

        if (top_k > 0) {
            llama_sampler_chain_add(llama_sampler, llama_sampler_init_top_k(top_k));
        }
        llama_sampler_chain_add(llama_sampler, llama_sampler_init_top_p(top_p, 1));
        llama_sampler_chain_add(llama_sampler, llama_sampler_init_temp(temperature));
        llama_sampler_chain_add(llama_sampler, llama_sampler_init_dist(LLAMA_DEFAULT_SEED));

        llama_context = llama_init_from_model(llama_model, ctx_params);
        if (!llama_context) {
            llama_model_free(llama_model);
            llama_model = nullptr;
            llama_sampler_free(llama_sampler);
            llama_sampler = nullptr;
            return false;
        }

        return true;
    }

    void free_llama_model() {
        if (llama_context) {
            llama_free(llama_context);
            llama_context = nullptr;
        }
        if (llama_model) {
            llama_model_free(llama_model);
            llama_model = nullptr;
        }
        if (llama_sampler) {
            llama_sampler_free(llama_sampler);
            llama_sampler = nullptr;
        }
    }

    void init_backend() {
        if (!backend_initialized.exchange(true)) {
            llama_backend_init();
            llama_numa_init(GGML_NUMA_STRATEGY_DISABLED);
        }
    }

    std::string generate_tokens(const std::string& prompt, int32_t max_tokens) {
        if (!llama_context || !llama_sampler) {
            return "[Error: Model not loaded]";
        }

        const llama_vocab* vocab = llama_model_get_vocab(llama_model);
        if (!vocab) {
            return "[Error: Vocabulary not available]";
        }

        // Tokenize prompt
        prompt_tokens.resize(prompt.size() * 2 + 10); // Estimate
        int32_t n_prompt_tokens = llama_tokenize(
            vocab, prompt.c_str(), prompt.size(),
            prompt_tokens.data(), static_cast<int32_t>(prompt_tokens.size()),
            true, false // add_special=true, parse_special=false
        );

        if (n_prompt_tokens < 0) {
            // Buffer too small, resize and retry
            prompt_tokens.resize(-n_prompt_tokens);
            n_prompt_tokens = llama_tokenize(
                vocab, prompt.c_str(), prompt.size(),
                prompt_tokens.data(), static_cast<int32_t>(prompt_tokens.size()),
                true, false
            );
            if (n_prompt_tokens < 0) {
                return "[Error: Prompt tokenization failed]";
            }
        }

        prompt_tokens.resize(n_prompt_tokens);
        prompt_len = n_prompt_tokens;
        generated_tokens.clear();

        // Create batch for prompt
        llama_batch batch = llama_batch_get_one(prompt_tokens.data(), n_prompt_tokens);

        // Process prompt
        if (llama_decode(llama_context, batch) != 0) {
            return "[Error: Prompt processing failed]";
        }

        // Generate tokens
        std::ostringstream output;
        llama_token new_token_id = 0;
        int tokens_generated = 0;

        for (int i = 0; i < max_tokens && !cancel_requested; ++i) {
            // Sample next token
            new_token_id = llama_sampler_sample(llama_sampler, llama_context, -1);
            if (new_token_id == LLAMA_TOKEN_NULL) break;

            // Check for EOS
            if (llama_vocab_is_eog(vocab, new_token_id)) break;

            // Accept token
            llama_sampler_accept(llama_sampler, new_token_id);
            generated_tokens.push_back(new_token_id);
            tokens_generated++;

            // Detokenize and append to output
            char piece_buf[64];
            int32_t piece_len = llama_token_to_piece(vocab, new_token_id, piece_buf, sizeof(piece_buf), 0, true);
            if (piece_len > 0) {
                output.write(piece_buf, piece_len);
            }

            // Prepare next batch with single token
            llama_batch next_batch = llama_batch_get_one(&new_token_id, 1);
            if (llama_decode(llama_context, next_batch) != 0) {
                break;
            }
        }

        llama_batch_free(batch);
        return output.str();
    }

    // Progress callback for model loading
    YallaProgressCallback progress_cb = nullptr;
    void* progress_user_data = nullptr;
};

std::atomic<bool> YallaInferenceEngine::backend_initialized{false};

extern "C" {

YALLA_CORE_EXPORT YallaInferenceEngineHandle yalla_inference_engine_create(YallaModelManagerHandle model_manager) {
    if (!model_manager) return nullptr;

    // Initialize llama.cpp backend
    if (!YallaInferenceEngine::backend_initialized.exchange(true)) {
        llama_backend_init();
        llama_numa_init(GGML_NUMA_STRATEGY_DISABLED);
    }

    auto* engine = new YallaInferenceEngine();
    engine->model_manager = model_manager;
    return engine;
}

YALLA_CORE_EXPORT void yalla_inference_engine_destroy(YallaInferenceEngineHandle handle) {
    if (!handle) return;
    auto* engine = static_cast<YallaInferenceEngine*>(handle);
    engine->free_llama_model();
    delete engine;
}

YALLA_CORE_EXPORT bool yalla_inference_engine_load_model(YallaInferenceEngineHandle handle,
    const char* model_id, int32_t context_size, int32_t max_batch_size) {
    if (!handle || !model_id) return false;
    auto* engine = static_cast<YallaInferenceEngine*>(handle);

    std::lock_guard<std::mutex> lock(engine->inference_mutex);

    engine->free_llama_model();

    // Verify model exists
    bool verified = false;
    yalla_model_manager_verify(engine->model_manager, model_id, &verified);
    if (!verified) return false;

    // Get model path from manager
    // We need to access the manager's model_path method - call through a helper
    // For now, construct path directly
    std::string model_path = std::string("./models/") + model_id + ".gguf";

    // Update sampling parameters from request
    // (These will be used when creating the sampler)

    engine->context_size = context_size > 0 ? context_size : 4096;
    engine->max_batch_size = max_batch_size > 0 ? max_batch_size : 1;

    bool loaded = engine->load_llama_model(model_path);
    if (loaded) {
        engine->loaded_model_id = model_id;
    }
    return loaded;
}

YALLA_CORE_EXPORT void yalla_inference_engine_unload_model(YallaInferenceEngineHandle handle) {
    if (!handle) return;
    auto* engine = static_cast<YallaInferenceEngine*>(handle);
    std::lock_guard<std::mutex> lock(engine->inference_mutex);
    engine->free_llama_model();
    engine->loaded_model_id.clear();
}

YALLA_CORE_EXPORT YallaInferenceResponse yalla_inference_engine_infer(YallaInferenceEngineHandle handle,
    const YallaInferenceRequest* request) {
    YallaInferenceResponse response{};
    response.text = strdup("");
    response.tokens_used = 0;
    response.truncated = false;
    response.error = nullptr;

    if (!handle || !request || !request->prompt) {
        response.error = strdup("Invalid parameters");
        return response;
    }

    auto* engine = static_cast<YallaInferenceEngine*>(handle);

    if (engine->busy) {
        response.error = strdup("Engine busy");
        return response;
    }

    if (engine->loaded_model_id.empty()) {
        response.error = strdup("No model loaded");
        return response;
    }

    engine->busy = true;
    engine->cancel_requested = false;

    // Update sampling parameters from request
    if (request->temperature > 0) engine->temperature = request->temperature;
    if (request->top_p > 0) engine->top_p = request->top_p;
    if (request->max_tokens > 0) engine->max_batch_size = request->max_tokens;

    try {
        // Generate response using llama.cpp
        std::string result = engine->generate_tokens(request->prompt, engine->max_batch_size);

        if (engine->cancel_requested) {
            response.error = strdup("Cancelled");
            engine->busy = false;
            return response;
        }

        response.text = strdup(result.c_str());
        response.tokens_used = static_cast<int32_t>(result.size() / 4); // Rough estimate
        response.truncated = false;
    } catch (const std::exception& e) {
        response.error = strdup(e.what());
    } catch (...) {
        response.error = strdup("Unknown inference error");
    }

    engine->busy = false;
    return response;
}

YALLA_CORE_EXPORT void yalla_inference_engine_cancel(YallaInferenceEngineHandle handle) {
    if (!handle) return;
    auto* engine = static_cast<YallaInferenceEngine*>(handle);
    engine->cancel_requested = true;
}

YALLA_CORE_EXPORT bool yalla_inference_engine_is_busy(YallaInferenceEngineHandle handle) {
    if (!handle) return false;
    return static_cast<YallaInferenceEngine*>(handle)->busy;
}

YALLA_CORE_EXPORT int64_t yalla_inference_engine_get_memory_usage(YallaInferenceEngineHandle handle) {
    if (!handle) return 0;
    auto* engine = static_cast<YallaInferenceEngine*>(handle);
    if (engine->llama_model) {
        return llama_model_size(engine->llama_model) + engine->context_size * 1024; // model + KV cache estimate
    }
    return 600 * 1024 * 1024; // Default estimate for Qwen3-0.6B Q4
}

YALLA_CORE_EXPORT void yalla_inference_engine_set_sampling_params(YallaInferenceEngineHandle handle,
    float temperature, float top_p, int32_t top_k, float repeat_penalty,
    int32_t mirostat, float mirostat_tau, float mirostat_eta) {
    if (!handle) return;
    auto* engine = static_cast<YallaInferenceEngine*>(handle);
    engine->temperature = temperature;
    engine->top_p = top_p;
    engine->top_k = top_k;
    engine->repeat_penalty = repeat_penalty;
    engine->mirostat = mirostat;
    engine->mirostat_tau = mirostat_tau;
    engine->mirostat_eta = mirostat_eta;
}

YALLA_CORE_EXPORT void yalla_inference_engine_set_progress_callback(YallaInferenceEngineHandle handle,
    YallaProgressCallback callback, void* user_data) {
    if (!handle) return;
    auto* engine = static_cast<YallaInferenceEngine*>(handle);
    engine->progress_cb = callback;
    engine->progress_user_data = user_data;
}

} // extern "C"