import { randomUUID } from "node:crypto";
import type { ChannelPlugin } from "openclaw/plugin-sdk";
import { DesktopBridge } from "./desktop-bridge.js";
import type { ClaudeDesktopConfig } from "./config.js";

type ResolvedAccount = {
  accountId: string;
  enabled: boolean;
  config: ClaudeDesktopConfig;
};

let bridge: DesktopBridge | null = null;

export function getDesktopBridge(scriptsDir?: string): DesktopBridge {
  if (!bridge) {
    if (!scriptsDir) {
      throw new Error(
        "DesktopBridge not initialized — call getDesktopBridge(scriptsDir) first",
      );
    }
    bridge = new DesktopBridge({ scriptsDir });
  }
  return bridge;
}

export const claudeDesktopPlugin: ChannelPlugin<ResolvedAccount> = {
  id: "claude-desktop",
  meta: {
    id: "claude-desktop",
    label: "Claude Desktop",
    selectionLabel: "Claude Desktop (UIA Bridge)",
    docsPath: "/channels/claude-desktop",
    blurb: "Bridge to Claude Desktop via Windows UI Automation.",
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
          responseTimeoutMs: pluginCfg?.responseTimeoutMs ?? 120000,
          messagePrefix: pluginCfg?.messagePrefix ?? true,
        },
      };
    },
  },
  outbound: {
    deliveryMode: "direct",
    sendText: async ({ text }) => {
      const b = getDesktopBridge();
      await b.injectMessage(text);
      return { channel: "claude-desktop", messageId: randomUUID() };
    },
  },
  gateway: {
    startAccount: async (ctx) => {
      ctx.log?.info("[claude-desktop] connecting UIA bridge");
      const b = getDesktopBridge();
      await b.connect();
      ctx.log?.info("[claude-desktop] UIA bridge connected");
    },
    stopAccount: async (ctx) => {
      ctx.log?.info("[claude-desktop] disconnecting UIA bridge");
      getDesktopBridge().disconnect();
    },
  },
};
