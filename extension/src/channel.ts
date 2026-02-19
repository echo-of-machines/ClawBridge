import { randomUUID } from "node:crypto";
import type { ChannelPlugin } from "openclaw/plugin-sdk";
import { CdpBridge } from "./cdp-bridge.js";
import type { ClaudeDesktopConfig } from "./config.js";

type ResolvedAccount = {
  accountId: string;
  enabled: boolean;
  config: ClaudeDesktopConfig;
};

let bridge: CdpBridge | null = null;

export function getCdpBridge(): CdpBridge {
  if (!bridge) {
    bridge = new CdpBridge();
  }
  return bridge;
}

export const claudeDesktopPlugin: ChannelPlugin<ResolvedAccount> = {
  id: "claude-desktop",
  meta: {
    id: "claude-desktop",
    label: "Claude Desktop",
    selectionLabel: "Claude Desktop (CDP Bridge)",
    docsPath: "/channels/claude-desktop",
    blurb: "Bridge to Claude Desktop via Chrome DevTools Protocol.",
    order: 99,
  },
  capabilities: {
    chatTypes: ["direct"],
  },
  config: {
    listAccountIds: () => ["default"],
    resolveAccount: (cfg) => {
      const pluginCfg = cfg.plugins?.entries?.["claude-desktop"]
        ?.config as Partial<ClaudeDesktopConfig> | undefined;
      return {
        accountId: "default",
        enabled: pluginCfg?.enabled ?? false,
        config: {
          enabled: pluginCfg?.enabled ?? false,
          cdpPort: pluginCfg?.cdpPort ?? 19222,
          cdpHost: pluginCfg?.cdpHost ?? "127.0.0.1",
          responseTimeoutMs: pluginCfg?.responseTimeoutMs ?? 120000,
          messagePrefix: pluginCfg?.messagePrefix ?? true,
        },
      };
    },
  },
  outbound: {
    deliveryMode: "direct",
    sendText: async ({ text }) => {
      const b = getCdpBridge();
      await b.injectMessage(text);
      return { channel: "claude-desktop", messageId: randomUUID() };
    },
  },
  gateway: {
    startAccount: async (ctx) => {
      const account = ctx.account;
      const { cdpHost, cdpPort } = account.config;
      ctx.log?.info(
        `[claude-desktop] connecting CDP bridge to ${cdpHost}:${cdpPort}`,
      );
      const b = getCdpBridge();
      await b.connect(cdpHost, cdpPort);
      ctx.log?.info("[claude-desktop] CDP bridge connected");
    },
    stopAccount: async (ctx) => {
      ctx.log?.info("[claude-desktop] disconnecting CDP bridge");
      getCdpBridge().disconnect();
    },
  },
};
