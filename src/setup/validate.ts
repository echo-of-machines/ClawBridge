import fs from "node:fs";
import net from "node:net";
import os from "node:os";
import path from "node:path";
import json5 from "json5";
import type { DetectResult } from "./detect.js";

export type CheckResult = {
  name: string;
  pass: boolean;
  message: string;
};

function tcpAvailable(port: number, timeoutMs = 1000): Promise<boolean> {
  return new Promise((resolve) => {
    const socket = new net.Socket();
    const timer = setTimeout(() => {
      socket.destroy();
      resolve(true); // timeout = nobody listening = port available
    }, timeoutMs);
    socket.connect(port, "127.0.0.1", () => {
      clearTimeout(timer);
      socket.destroy();
      resolve(false); // connected = port in use
    });
    socket.on("error", () => {
      clearTimeout(timer);
      resolve(true); // error = port available
    });
  });
}

export async function validate(env: DetectResult): Promise<CheckResult[]> {
  const results: CheckResult[] = [];

  // 1. Claude Desktop config has mcpServers.openclaw
  if (env.claudeDesktop.configPath && fs.existsSync(env.claudeDesktop.configPath)) {
    try {
      const raw = fs.readFileSync(env.claudeDesktop.configPath, "utf8");
      const cfg = JSON.parse(raw) as { mcpServers?: Record<string, unknown> };
      const has = Boolean(cfg.mcpServers?.openclaw);
      results.push({
        name: "mcp-config",
        pass: has,
        message: has
          ? "Claude Desktop config has mcpServers.openclaw"
          : "Missing mcpServers.openclaw in Claude Desktop config — run setup again",
      });
    } catch {
      results.push({ name: "mcp-config", pass: false, message: "Failed to parse Claude Desktop config" });
    }
  } else {
    results.push({ name: "mcp-config", pass: false, message: "Claude Desktop config file not found" });
  }

  // 2. OpenClaw config has plugin enabled
  if (env.openclaw.configPath && fs.existsSync(env.openclaw.configPath)) {
    try {
      const raw = fs.readFileSync(env.openclaw.configPath, "utf8");
      const cfg = json5.parse(raw) as {
        plugins?: { entries?: Record<string, { enabled?: boolean }> };
      };
      const enabled = cfg.plugins?.entries?.["claude-desktop"]?.enabled === true;
      results.push({
        name: "openclaw-plugin",
        pass: enabled,
        message: enabled
          ? "OpenClaw claude-desktop plugin is enabled"
          : "Plugin claude-desktop not enabled in OpenClaw config — run setup again",
      });
    } catch {
      results.push({ name: "openclaw-plugin", pass: false, message: "Failed to parse OpenClaw config" });
    }
  } else {
    results.push({ name: "openclaw-plugin", pass: false, message: "OpenClaw config file not found" });
  }

  // 3. Extension files exist
  const extDir = path.join(os.homedir(), ".openclaw", "extensions", "claude-desktop");
  const extExists = fs.existsSync(extDir);
  results.push({
    name: "extension-files",
    pass: extExists,
    message: extExists
      ? `Extension files present at ${extDir}`
      : `Extension files missing at ${extDir} — run setup again`,
  });

  // 4. Launcher script exists
  const launcherExt = process.platform === "win32" ? "cmd" : "sh";
  const launcherFile = path.join(os.homedir(), ".openclaw", `claude-desktop-launcher.${launcherExt}`);
  const launcherExists = fs.existsSync(launcherFile);
  results.push({
    name: "launcher",
    pass: launcherExists,
    message: launcherExists
      ? `Launcher script present at ${launcherFile}`
      : `Launcher script missing — run setup again`,
  });

  // 5. Gateway reachable
  results.push({
    name: "gateway",
    pass: env.openclaw.gatewayReachable,
    message: env.openclaw.gatewayReachable
      ? `Gateway reachable at ${env.openclaw.gatewayUrl}`
      : `Gateway not reachable at ${env.openclaw.gatewayUrl} — start OpenClaw first`,
  });

  // 6. CDP port availability (only relevant when Claude Desktop is not running)
  const cdpAvailable = await tcpAvailable(19222);
  results.push({
    name: "cdp-port",
    pass: true, // informational
    message: cdpAvailable
      ? "CDP port 19222 is available — launch Claude Desktop with the launcher script"
      : "CDP port 19222 is in use — Claude Desktop may already be running with CDP enabled",
  });

  return results;
}
