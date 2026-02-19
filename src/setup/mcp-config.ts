import fs from "node:fs";
import path from "node:path";
import type { DetectResult } from "./detect.js";

const MCP_KEY = "openclaw";

type McpServerEntry = {
  command: string;
  args: string[];
  env?: Record<string, string>;
};

type ClaudeDesktopConfig = {
  mcpServers?: Record<string, McpServerEntry>;
  [key: string]: unknown;
};

function resolveIndexJsPath(): string {
  // Resolve absolute path to the built index.js
  return path.resolve(
    path.dirname(new URL(import.meta.url).pathname),
    "..",
    "index.js",
  );
}

function readConfig(configPath: string): ClaudeDesktopConfig {
  if (!fs.existsSync(configPath)) {
    return {};
  }
  try {
    const raw = fs.readFileSync(configPath, "utf8");
    return JSON.parse(raw) as ClaudeDesktopConfig;
  } catch {
    return {};
  }
}

function writeConfig(configPath: string, config: ClaudeDesktopConfig): void {
  const dir = path.dirname(configPath);
  if (!fs.existsSync(dir)) {
    fs.mkdirSync(dir, { recursive: true });
  }
  fs.writeFileSync(configPath, JSON.stringify(config, null, 2) + "\n", "utf8");
}

export function installMcpConfig(env: DetectResult): { configPath: string } {
  const configPath = env.claudeDesktop.configPath!;
  const config = readConfig(configPath);

  if (!config.mcpServers) {
    config.mcpServers = {};
  }

  const mcpEnv: Record<string, string> = {};
  if (env.openclaw.gatewayUrl !== "ws://127.0.0.1:18789") {
    mcpEnv.OPENCLAW_GATEWAY_URL = env.openclaw.gatewayUrl;
  }
  if (env.openclaw.authToken) {
    mcpEnv.OPENCLAW_AUTH_TOKEN = env.openclaw.authToken;
  }

  const entry: McpServerEntry = {
    command: "node",
    args: [resolveIndexJsPath()],
  };
  if (Object.keys(mcpEnv).length > 0) {
    entry.env = mcpEnv;
  }

  config.mcpServers[MCP_KEY] = entry;

  writeConfig(configPath, config);
  return { configPath };
}

export function removeMcpConfig(env: DetectResult): { removed: boolean } {
  const configPath = env.claudeDesktop.configPath!;
  if (!fs.existsSync(configPath)) {
    return { removed: false };
  }

  const config = readConfig(configPath);
  if (!config.mcpServers?.[MCP_KEY]) {
    return { removed: false };
  }

  delete config.mcpServers[MCP_KEY];

  // Clean up empty mcpServers object
  if (Object.keys(config.mcpServers).length === 0) {
    delete config.mcpServers;
  }

  writeConfig(configPath, config);
  return { removed: true };
}
