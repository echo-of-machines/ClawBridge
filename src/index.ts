import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { EventBuffer } from "./event-buffer.js";
import { GatewayClient } from "./gateway-client.js";
import { registerTools } from "./tools.js";

const GATEWAY_URL = process.env.OPENCLAW_GATEWAY_URL ?? "ws://127.0.0.1:18789";
const AUTH_TOKEN = process.env.OPENCLAW_AUTH_TOKEN;

// --- Gateway client ---

const events = new EventBuffer();

const gw = new GatewayClient({
  url: GATEWAY_URL,
  token: AUTH_TOKEN,
  onEvent: (evt) => events.push(evt),
  onHelloOk: (hello) => {
    process.stderr.write(
      `[clawbridge] connected to gateway v${hello.server.version} (conn ${hello.server.connId})\n`,
    );
  },
  onClose: (code, reason) => {
    process.stderr.write(
      `[clawbridge] gateway closed (${code}): ${reason}\n`,
    );
  },
  onConnectError: (err) => {
    process.stderr.write(
      `[clawbridge] gateway connect error: ${err.message}\n`,
    );
  },
});

gw.start();

// --- MCP server ---

const mcp = new McpServer(
  { name: "clawbridge", version: "0.1.0" },
  { capabilities: { tools: {} } },
);

registerTools(mcp, gw, events);

const transport = new StdioServerTransport();
await mcp.connect(transport);

process.stderr.write("[clawbridge] MCP server listening on stdio\n");

// --- Graceful shutdown ---

const shutdown = () => {
  gw.stop();
  mcp.close().catch(() => {});
  process.exit(0);
};

process.on("SIGTERM", shutdown);
process.on("SIGINT", shutdown);
