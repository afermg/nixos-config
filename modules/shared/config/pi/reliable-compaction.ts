import { compact, type ExtensionAPI } from "@earendil-works/pi-coding-agent";

/**
 * Pi 0.87.1's default compactor inherits xhigh reasoning and omits transport
 * from summary requests. Codex can then stall on WebSocket summaries until
 * each five-minute idle timeout, including every automatic retry.
 *
 * Keep Pi's own summary prompts, split-turn handling, retained boundary, usage
 * accounting and file tracking. Only summary requests use SSE/medium reasoning;
 * ordinary work keeps the user's chosen model, reasoning and transport.
 */
export default function (pi: ExtensionAPI) {
  pi.on("session_before_compact", async (event, ctx) => {
    if (ctx.model?.provider !== "openai-codex") return;

    const { preparation, signal } = event;
    // Extension-produced compactions are deliberately not carried forward by
    // Pi's built-in file tracker. Carry our own known details across checkpoints.
    const fileOps = {
      read: new Set(preparation.fileOps.read),
      written: new Set(preparation.fileOps.written),
      edited: new Set(preparation.fileOps.edited),
    };
    const previous = [...event.branchEntries].reverse().find((e) => e.type === "compaction");
    if (previous?.type === "compaction" && previous.fromHook) {
      const details = previous.details as { reliableCompaction?: number; readFiles?: string[]; modifiedFiles?: string[] } | undefined;
      if (details?.reliableCompaction === 1) {
        for (const path of details.readFiles ?? []) fileOps.read.add(path);
        for (const path of details.modifiedFiles ?? []) fileOps.edited.add(path);
      }
    }

    const deadline = new AbortController();
    const timer = setTimeout(() => deadline.abort(), 600_000);
    const summarySignal = AbortSignal.any([signal, deadline.signal]);
    ctx.ui.notify("Compacting with the current model via SSE (medium reasoning, bounded to 10 minutes)", "info");
    try {
      const result = await compact(
        { ...preparation, fileOps },
        ctx.model,
        undefined,
        undefined,
        event.customInstructions,
        summarySignal,
        "medium",
        async (model, context, options) => {
          const stream = await ctx.modelRegistry.streamSimple(model, context, {
            ...options,
            transport: "sse",
            timeoutMs: 300_000,
            maxRetries: 0,
          });
          const getResult = stream.result.bind(stream);
          stream.result = async () => {
            const response = await getResult();
            if (response.stopReason === "stop" && !response.content.some((block) => block.type === "text" && block.text.trim())) {
              throw new Error("Summary was empty");
            }
            return response;
          };
          return stream;
        },
        undefined,
        { enabled: false, maxRetries: 0, baseDelayMs: 2000 },
      );
      // Do not persist partial output or fall back to the broken default path.
      if (summarySignal.aborted) throw new Error("Summary cancelled or exceeded its 10-minute deadline");
      if (!result.summary.trim()) throw new Error("Summary was empty");
      return {
        compaction: {
          ...result,
          details: { ...result.details, reliableCompaction: 1 },
        },
      };
    } catch (error) {
      if (!signal.aborted) {
        ctx.ui.notify(`Compaction stopped; transcript unchanged: ${error instanceof Error ? error.message : String(error)}`, "error");
      }
      // A provider safety rejection is not a transport failure: never switch
      // providers/models or retry through an alternate route after a rejection.
      return { cancel: true };
    } finally {
      clearTimeout(timer);
    }
  });
}
