import type { OpenClawPluginApi } from "openclaw/plugin-sdk";
import { claudeDesktopPlugin, getCdpBridge } from "./src/channel.js";
import type { ClaudeDesktopConfig } from "./src/config.js";
import { ResponseRouter } from "./src/response-router.js";

const plugin = {
  id: "claude-desktop",
  name: "Claude Desktop",
  description: "Claude Desktop CDP bridge channel plugin",
  configSchema: {},
  register(api: OpenClawPluginApi) {
    const pluginCfg = api.pluginConfig as
      | Partial<ClaudeDesktopConfig>
      | undefined;
    if (!pluginCfg?.enabled) return;

    const bridge = getCdpBridge();
    const router = new ResponseRouter();
    const cdpHost = pluginCfg.cdpHost ?? "127.0.0.1";
    const cdpPort = pluginCfg.cdpPort ?? 19222;
    const messagePrefix = pluginCfg.messagePrefix ?? true;

    // Wire response routing: when Claude Desktop responds, log and forward
    router.onResponse((channelId, from, text) => {
      api.logger.info(
        `[claude-desktop] routing response to ${channelId}:${from} (${text.length} chars)`,
      );
      // The outbound delivery is handled by OpenClaw's pipeline when the
      // agent intercept (task 4) returns the response as a ReplyPayload.
      // For direct observation mode, responses are logged for debugging.
    });

    // 1. Register the channel plugin
    api.registerChannel({ plugin: claudeDesktopPlugin });

    // 2. Register CDP lifecycle service
    api.registerService({
      id: "claude-desktop-cdp",
      async start() {
        api.logger.info(
          `[claude-desktop] connecting CDP bridge to ${cdpHost}:${cdpPort}`,
        );
        await bridge.connect(cdpHost, cdpPort);
        router.startObserving(bridge);
        api.logger.info("[claude-desktop] CDP bridge connected");
      },
      stop() {
        bridge.disconnect();
        api.logger.info("[claude-desktop] CDP bridge disconnected");
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
        cdpHost,
        cdpPort,
      });
    });
  },
};

export default plugin;
