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
    "Call any OpenClaw gateway RPC method directly. Available methods include: cron.list/add/update/run (scheduling), sessions.list/reset (conversations), config.get/patch (settings), skills.list/update, tools.list, channels.list/send, health, doctor, models.list, exec.approval.request/resolve, node.list/describe/wake, browser.proxy, and more. Use openclaw_status for a quick overview instead of calling multiple methods.",
    { method: z.string().describe("Gateway RPC method name (e.g. 'cron.list', 'config.get', 'health')"), params: z.record(z.unknown()).optional() },
    async ({ method, params }) => {
      const result = await gw.request(method, params);
      return { content: [{ type: "text", text: JSON.stringify(result, null, 2) }] };
    },
  );

  // 2. openclaw_send — send a message to a channel target
  server.tool(
    "openclaw_send",
    "Send a message to a user on a messaging channel (WhatsApp, Telegram, Signal, Discord, Slack, iMessage, etc.). Use this to reply directly to someone or deliver a notification. The 'to' field is the channel-specific identifier (phone number, @username, channel ID, etc.).",
    {
      to: z.string().describe("Recipient identifier (phone number, @username, channel ID, etc.)"),
      message: z.string().describe("Message text to send"),
      channel: z.string().optional().describe("Channel name (e.g. telegram, whatsapp, slack, discord, signal). Omit to use default."),
    },
    async ({ to, message, channel }) => {
      const params: Record<string, unknown> = { to, text: message };
      if (channel) params.channel = channel;
      const result = await gw.request("send", params);
      return { content: [{ type: "text", text: JSON.stringify(result, null, 2) }] };
    },
  );

  // 3. openclaw_agent — delegate to the OpenClaw agent
  server.tool(
    "openclaw_agent",
    "Delegate a task to the OpenClaw agent. The agent has 75+ tools including shell execution, browser automation, file operations, image generation, TTS, web search, and memory. It understands OpenClaw's full ecosystem — sessions, channels, plugins, skills, cron jobs, and multi-device nodes. Use this for complex tasks, multi-step workflows, or anything requiring deep OpenClaw knowledge. The agent runs asynchronously — you'll get an immediate acknowledgment, then the result arrives via gateway events.",
    {
      message: z.string().describe("Task or message for the OpenClaw agent"),
      sessionKey: z.string().optional().describe("Session key to target (routes to a specific conversation)"),
      agentId: z.string().optional().describe("Agent ID to use (for multi-agent setups)"),
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
    "Get a snapshot of the OpenClaw environment: connected messaging channels (WhatsApp, Telegram, etc.), active sessions, configured agents, and scheduled cron jobs. Use this first to understand what's available before taking action.",
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
    "Query recent OpenClaw events — incoming messages, agent responses, channel activity, cron triggers, node status changes. Use to monitor what's happening or check results of async operations like openclaw_agent calls.",
    {
      eventType: z.string().optional().describe("Filter by event type (e.g. 'chat', 'snapshot', 'channel', 'cron')"),
      since: z.number().optional().describe("Only events after this Unix timestamp (ms)"),
      limit: z.number().optional().describe("Max number of events to return (default: all buffered)"),
    },
    async ({ eventType, since, limit }) => {
      const results = events.query({ eventType, since, limit });
      return { content: [{ type: "text", text: JSON.stringify(results, null, 2) }] };
    },
  );

  // 6. openclaw_node_invoke — multi-device control
  server.tool(
    "openclaw_node_invoke",
    "Execute a command on a connected device (macOS, iOS, Android, Linux). Nodes expose capabilities like browser automation, shell execution, camera, location, screen recording, and SMS. Use openclaw_rpc with 'node.list' to discover available nodes first.",
    {
      nodeId: z.string().describe("Target node ID (use openclaw_rpc 'node.list' to discover)"),
      method: z.string().describe("Method to invoke (e.g. 'system.run', 'browser.proxy', 'screenshot')"),
      params: z.record(z.unknown()).optional().describe("Parameters for the method"),
    },
    async ({ nodeId, method, params }) => {
      const result = await gw.request("node.invoke", { nodeId, method, params });
      return { content: [{ type: "text", text: JSON.stringify(result, null, 2) }] };
    },
  );
}
