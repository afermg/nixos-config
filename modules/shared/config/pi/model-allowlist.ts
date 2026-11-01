import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

const baseUrl = "https://chatgpt.com/backend-api";
const api = "openai-codex-responses" as const;

export default function (pi: ExtensionAPI) {
  // Providing models replaces Pi's built-in list for this provider. The API-key
  // placeholder satisfies provider registration; normal openai-codex OAuth
  // credentials still take precedence when requests are made.
  pi.registerProvider("openai-codex", {
    baseUrl,
    api,
    apiKey: "$OPENAI_CODEX_API_KEY",
    models: [
      {
        id: "gpt-6-astra",
        name: "GPT-6 Astra",
        reasoning: true,
        thinkingLevelMap: {
          off: null,
          minimal: "low",
          low: "low",
          medium: "medium",
          high: "high",
          xhigh: "xhigh",
          max: "max",
        },
        input: ["text", "image"],
        cost: {
          input: 10,
          output: 50,
          cacheRead: 1,
          cacheWrite: 12.5,
          tiers: [
            {
              inputTokensAbove: 272000,
              input: 20,
              output: 75,
              cacheRead: 2,
              cacheWrite: 25,
            },
          ],
        },
        contextWindow: 272000,
        maxTokens: 128000,
        compat: {
          supportsOpenAIGrammarTools: true,
          supportsAdditionalTools: true,
          supportsToolSearch: true,
        },
      },
      {
        id: "gpt-6.1-sol",
        name: "GPT-6.1 Sol (500k)",
        reasoning: true,
        thinkingLevelMap: {
          minimal: "low",
          xhigh: "xhigh",
          max: "max",
        },
        input: ["text", "image"],
        // Published API-equivalent pricing, not a subscription billing estimate.
        // https://developers.openai.com/api/docs/models/gpt-6.1-sol
        cost: {
          input: 2,
          output: 10,
          cacheRead: 0.1,
          cacheWrite: 2.5,
          tiers: [
            {
              inputTokensAbove: 272000,
              input: 4,
              output: 15,
              cacheRead: 0.2,
              cacheWrite: 5,
            },
          ],
        },
        // Documented Codex context is 500k (not the API's 1.05M limit).
        // Explicit gpt-6.1-sol request succeeded with this account; see README.md.
        contextWindow: 500000,
        maxTokens: 128000,
        compat: {
          supportsOpenAIGrammarTools: true,
          supportsAdditionalTools: true,
          supportsToolSearch: true,
          supportsMidConvoSystemMessages: true,
        },
      },
    ],
  });
}
