import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import type { OpenClawPluginApi } from "openclaw/plugin-sdk";
import { claudeDesktopPlugin, getDesktopBridge } from "./src/channel.js";
import type { ClaudeDesktopConfig } from "./src/config.js";
import { ResponseRouter } from "./src/response-router.js";

const __dirname = path.dirname(fileURLToPath(import.meta.url));

/**
 * Resolve the path to the PowerShell bridge scripts.
 * Checks deployed location first, then falls back to monorepo layout.
 */
function resolveScriptsDir(): string {
  // Deployed: scripts copied alongside the extension
  const deployed = path.join(__dirname, "scripts", "bridge");
  if (fs.existsSync(deployed)) return deployed;

  // Development: scripts in the clawbridge-mcp package
  const monorepo = path.resolve(
    __dirname,
    "..",
    "..",
    "packages",
    "clawbridge-mcp",
    "scripts",
    "bridge",
  );
  if (fs.existsSync(monorepo)) return monorepo;

  throw new Error(
    `Bridge scripts not found at ${deployed} or ${monorepo}. Run clawbridge setup.`,
  );
}

const plugin = {
  id: "claude-desktop",
  name: "Claude Desktop",
  description: "Claude Desktop UIA bridge channel plugin",
  configSchema: {},
  register(api: OpenClawPluginApi) {
    const pluginCfg = api.pluginConfig as
      | Partial<ClaudeDesktopConfig>
      | undefined;
    if (!pluginCfg?.enabled) return;

    if (process.platform !== "win32") {
      api.logger.warn(
        "[claude-desktop] UIA bridge only works on Windows — skipping",
      );
      return;
    }

    const scriptsDir = resolveScriptsDir();
    const bridge = getDesktopBridge(scriptsDir);
    const router = new ResponseRouter();
    const messagePrefix = pluginCfg.messagePrefix ?? true;

    // Wire response routing: when Claude Desktop responds, log and forward
    router.onResponse((channelId, from, text) => {
      api.logger.info(
        `[claude-desktop] routing response to ${channelId}:${from} (${text.length} chars)`,
      );
    });

    // 1. Register the channel plugin
    api.registerChannel({ plugin: claudeDesktopPlugin });

    // 2. Register UIA lifecycle service
    api.registerService({
      id: "claude-desktop-uia",
      async start() {
        api.logger.info("[claude-desktop] connecting UIA bridge");
        await bridge.connect();
        router.startObserving(bridge);
        api.logger.info("[claude-desktop] UIA bridge connected");
      },
      stop() {
        bridge.disconnect();
        api.logger.info("[claude-desktop] UIA bridge disconnected");
      },
    });

    // 3. Intercept messages from other channels → inject into Claude Desktop
    api.on("message_received", (event, ctx) => {
      if (ctx.channelId === "claude-desktop") return;
      if (!bridge.isConnected()) return;
      const prefix = messagePrefix
        ? `[${ctx.channelId}:${event.from}] `
        : "";
      router.trackInjection(ctx.channelId, event.from);
      bridge.injectMessage(`${prefix}${event.content}`).catch(() => {});
    });

    // 4. Wake Claude Desktop when agent tasks complete
    api.on("agent_end", () => {
      if (!bridge.isConnected()) return;
      bridge
        .injectMessage("[system] OpenClaw agent task completed.")
        .catch(() => {});
    });

    // 5. Health check gateway method
    api.registerGatewayMethod("claude_desktop.status", ({ respond }) => {
      respond(true, {
        connected: bridge.isConnected(),
        transport: "uia",
      });
    });
  },
};

export default plugin;
