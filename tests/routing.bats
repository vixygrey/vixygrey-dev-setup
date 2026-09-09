#!/usr/bin/env bats
# Behavioral contract for the generated omp model routing (#538).

setup() {
    TEST_TMP="$(mktemp -d)"
    export GENERATED_CONFIG="$TEST_TMP/config.yml"
    awk "/<<'OMP_CONFIG_CONF'/{f=1;next} /^OMP_CONFIG_CONF$/{f=0} f" \
        "$BATS_TEST_DIRNAME/../scripts/setup-dev-tools-mac.sh" > "$GENERATED_CONFIG"
}

teardown() {
    rm -rf "$TEST_TMP"
}

@test "omp routing reserves Anthropic for slow and plan, with local Qwen fallback (#538)" {
    run ruby -ryaml -e '
        config = YAML.safe_load(File.read(ARGV.fetch(0)))
        expected = {
          "default" => "openai-codex/gpt-5.6-sol",
          "task" => "openai-codex/gpt-5.6-sol",
          "vision" => "google/gemini-3.8-flash:medium",
          "slow" => "anthropic/claude-sonnet-5:high",
          "plan" => "anthropic/claude-sonnet-5:high",
          "advisor" => "google/gemini-3.1-pro-preview:low",
          "smol" => "google/gemini-3.1-flash-lite:minimal",
          "tiny" => "google/gemini-3.1-flash-lite:minimal",
          "commit" => "google/gemini-3.1-flash-lite:minimal"
        }
        abort "role assignment changed" unless config.fetch("modelRoles") == expected

        chains = config.fetch("retry").fetch("fallbackChains")
        fallbacks = chains.values.flatten
        abort "Anthropic entered a fallback chain" if fallbacks.any? { |model| model.start_with?("anthropic/") }
        abort "a chain lost the local final fallback" unless chains.values.all? { |chain| chain.last == "ollama/qwen2.5-coder:14b" }
        abort "Codex does not fall back to Gemini first" unless chains.fetch("openai-codex/gpt-5.6-sol").first == "google/gemini-3.8-flash:medium"
    ' "$GENERATED_CONFIG"

    [ "$status" -eq 0 ]
}
