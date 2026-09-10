#!/usr/bin/env bats
# Behavioral contract for the generated omp model routing and provider settings (#538, #548).

setup() {
    TEST_TMP="$(mktemp -d)"
    export GENERATED_CONFIG="$TEST_TMP/config.yml"
    export GENERATED_ENV="$TEST_TMP/.env"
    export GENERATED_MACHINE_SKILL="$TEST_TMP/inspect-machine-SKILL.md"
    awk "/<<'OMP_CONFIG_CONF'/{f=1;next} /^OMP_CONFIG_CONF$/{f=0} f" \
        "$BATS_TEST_DIRNAME/../scripts/setup-dev-tools-mac.sh" > "$GENERATED_CONFIG"
    awk "/<<'OMP_ENV_CONF'/{f=1;next} /^OMP_ENV_CONF$/{f=0} f" \
        "$BATS_TEST_DIRNAME/../scripts/setup-dev-tools-mac.sh" > "$GENERATED_ENV"
    awk "/<<'SKILL_INSPECT_MACHINE'/{f=1;next} /^SKILL_INSPECT_MACHINE$/{f=0} f" \
        "$BATS_TEST_DIRNAME/../scripts/setup-dev-tools-mac.sh" > "$GENERATED_MACHINE_SKILL"
}

teardown() {
    rm -rf "$TEST_TMP"
}

@test "omp routing reserves Anthropic for slow and plan, with Vulkan Qwen fallback (#538, #548)" {
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
        abort "a chain lost the local final fallback" unless chains.values.all? { |chain| chain.last == "llama.cpp/qwen2.5-coder:14b" }
        abort "Codex does not fall back to Gemini first" unless chains.fetch("openai-codex/gpt-5.6-sol").first == "google/gemini-3.8-flash:medium"

        abort "ordinary turns do not use automatic reasoning" unless config.fetch("defaultThinkingLevel") == "auto"
        abort "MiniMax Code is not disabled" unless config.fetch("disabledProviders") == ["minimax-code"]
        abort "provider cache retention changed" unless config.fetch("providers").fetch("cacheRetention") == "auto"

        retry_config = config.fetch("retry")
        expected_retry_policy = {
          "fallbackRevertPolicy" => "cooldown-expiry",
          "usageAwareFallback" => true,
          "usageReservePct" => 10,
          "usageReservePolicy" => "auto"
        }
        expected_retry_policy.each do |key, value|
          abort "#{key} changed" unless retry_config.fetch(key) == value
        end
    ' "$GENERATED_CONFIG"

    [ "$status" -eq 0 ]
}

@test "omp credential seed exposes blank Anthropic and Gemini entries (#548)" {
    run bash -eu -o pipefail -c '
        source "$1"
        [[ "${ANTHROPIC_API_KEY+x}" == x && -z "$ANTHROPIC_API_KEY" ]]
        [[ "${GEMINI_API_KEY+x}" == x && -z "$GEMINI_API_KEY" ]]
    ' bash "$GENERATED_ENV"

    [ "$status" -eq 0 ]
}

@test "omp machine skill exposes machine records and live availability checks (#583)" {
    run ruby -ryaml -e '
        skill = File.read(ARGV.fetch(0))
        frontmatter = skill.split(/^---\s*$/, 3).fetch(1)
        metadata = YAML.safe_load(frontmatter)
        abort "wrong skill name" unless metadata.fetch("name") == "inspect-machine"
        abort "missing tool-selection trigger" unless metadata.fetch("description").include?("choosing a local tool")

        required = [
          "~/Desktop/TOOL_REFERENCE.md",
          "command -v -- <command>",
          "open -Ra",
          "Do not use human aliases"
        ]
        missing = required.reject { |text| skill.include?(text) }
        abort "missing machine inspection contracts: #{missing.join(", ")}" unless missing.empty?
    ' "$GENERATED_MACHINE_SKILL"

    [ "$status" -eq 0 ]
}
