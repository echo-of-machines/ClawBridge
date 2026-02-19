import type { ReplyPayload } from "openclaw/plugin-sdk";
import { getCdpBridge } from "./channel.js";

const POLL_INTERVAL_MS = 500;
const STABLE_POLLS = 3;

type MessageContext = {
  BodyForCommands?: string;
  RawBody?: string;
  Body?: string;
};

type ResolverConfig = {
  plugins?: {
    entries?: Record<string, { config?: Record<string, unknown> }>;
  };
};

/**
 * Drop-in replacement for `getReplyFromConfig` that routes the inbound
 * message through Claude Desktop via CDP and returns the response as a
 * `ReplyPayload`. This lets OpenClaw's outbound pipeline deliver the
 * reply back to the originating channel naturally.
 */
export async function getClaudeDesktopResolver(
  ctx: MessageContext,
  _opts?: unknown,
  configOverride?: ResolverConfig,
): Promise<ReplyPayload | ReplyPayload[] | undefined> {
  const bridge = getCdpBridge();
  if (!bridge.isConnected()) return undefined;

  const content =
    typeof ctx.BodyForCommands === "string"
      ? ctx.BodyForCommands
      : typeof ctx.RawBody === "string"
        ? ctx.RawBody
        : typeof ctx.Body === "string"
          ? ctx.Body
          : "";
  if (!content.trim()) return undefined;

  const timeoutMs =
    (configOverride?.plugins?.entries?.["claude-desktop"]?.config
      ?.responseTimeoutMs as number | undefined) ?? 120_000;

  // Snapshot the current response so we can detect when a new one appears.
  const baseline = await bridge.readLastResponse();

  await bridge.injectMessage(content);

  // Poll until the response stabilises (unchanged for STABLE_POLLS intervals).
  const deadline = Date.now() + timeoutMs;
  let lastSeen = baseline;
  let stableCount = 0;

  while (Date.now() < deadline) {
    await new Promise((r) => setTimeout(r, POLL_INTERVAL_MS));
    const current = await bridge.readLastResponse();
    if (current && current !== baseline) {
      if (current === lastSeen) {
        stableCount++;
        if (stableCount >= STABLE_POLLS) {
          return { text: current };
        }
      } else {
        lastSeen = current;
        stableCount = 0;
      }
    }
  }

  // Timed out — return whatever we last saw, if anything new appeared.
  if (lastSeen && lastSeen !== baseline) {
    return { text: lastSeen };
  }
  return undefined;
}
