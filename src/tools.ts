import { z } from "zod";
import type { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import type { GatewayClient } from "./gateway-client.js";
import type { EventBuffer } from "./event-buffer.js";

export function registerTools(
  server: McpServer,
  gw: GatewayClient,
  events: EventBuffer,
): void {
  // 1. openclaw_rpc — generic Gateway passthrough
  server.tool(
    "openclaw_rpc",
    "Send any Gateway RPC method and return the response. Use for advanced operations not covered by other tools.",
    { method: z.string(), params: z.record(z.unknown()).optional() },
    async ({ method, params }) => {
      const result = await gw.request(method, params);
      return { content: [{ type: "text", text: JSON.stringify(result, null, 2) }] };
    },
  );

  // 2. openclaw_send — send a message to a channel target
  server.tool(
    "openclaw_send",
    "Send a message to a specific recipient on a channel (e.g. Telegram, Slack, Discord). The 'to' field is the channel-specific target (phone number, channel ID, etc.).",
    {
      to: z.string().describe("Recipient identifier"),
      message: z.string().describe("Message text to send"),
      channel: z.string().optional().describe("Channel name (e.g. telegram, slack). Omit to use default."),
    },
    async ({ to, message, channel }) => {
      const params: Record<string, unknown> = { to, text: message };
      if (channel) params.channel = channel;
      const result = await gw.request("send", params);
      return { content: [{ type: "text", text: JSON.stringify(result, null, 2) }] };
    },
  );

  // 3. openclaw_agent — trigger the OpenClaw agent
  server.tool(
    "openclaw_agent",
    "Send a message to the OpenClaw agent for processing. The agent will use its configured AI model and tools to respond.",
    {
      message: z.string().describe("Message to send to the agent"),
      sessionKey: z.string().optional().describe("Session key to target"),
      agentId: z.string().optional().describe("Agent ID to use"),
    },
    async ({ message, sessionKey, agentId }) => {
      const params: Record<string, unknown> = { text: message };
      if (sessionKey) params.sessionKey = sessionKey;
      if (agentId) params.agentId = agentId;
      const result = await gw.request("chat.send", params);
      return { content: [{ type: "text", text: JSON.stringify(result, null, 2) }] };
    },
  );

  // 4. openclaw_status — aggregate status overview
  server.tool(
    "openclaw_status",
    "Get a comprehensive status overview of the OpenClaw instance including channels, sessions, agents, and cron jobs.",
    async () => {
      const [channels, sessions, agents, cron] = await Promise.allSettled([
        gw.request("channels.status", {}),
        gw.request("sessions.list", {}),
        gw.request("agents.list", {}),
        gw.request("cron.status", {}),
      ]);
      const extract = (r: PromiseSettledResult<unknown>) =>
        r.status === "fulfilled" ? r.value : { error: (r.reason as Error)?.message ?? "failed" };
      const status = {
        channels: extract(channels),
        sessions: extract(sessions),
        agents: extract(agents),
        cron: extract(cron),
      };
      return { content: [{ type: "text", text: JSON.stringify(status, null, 2) }] };
    },
  );

  // 5. openclaw_events — query the event ring buffer
  server.tool(
    "openclaw_events",
    "Query recent Gateway events from the local buffer. Use to inspect what's happening in real time.",
    {
      eventType: z.string().optional().describe("Filter by event type (e.g. 'snapshot', 'chat')"),
      since: z.number().optional().describe("Only events after this Unix timestamp (ms)"),
      limit: z.number().optional().describe("Max number of events to return"),
    },
    async ({ eventType, since, limit }) => {
      const results = events.query({ eventType, since, limit });
      return { content: [{ type: "text", text: JSON.stringify(results, null, 2) }] };
    },
  );

  // 6. openclaw_node_invoke — node-to-node RPC
  server.tool(
    "openclaw_node_invoke",
    "Invoke a method on a remote OpenClaw node. Used for multi-node orchestration.",
    {
      nodeId: z.string().describe("Target node ID"),
      method: z.string().describe("Method to invoke on the node"),
      params: z.record(z.unknown()).optional().describe("Parameters for the method"),
    },
    async ({ nodeId, method, params }) => {
      const result = await gw.request("node.invoke", { nodeId, method, params });
      return { content: [{ type: "text", text: JSON.stringify(result, null, 2) }] };
    },
  );
}
