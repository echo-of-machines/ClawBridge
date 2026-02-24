import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import json5 from "json5";
import type { DetectResult } from "./detect.js";

export type CheckResult = {
  name: string;
  pass: boolean;
  message: string;
  /** "error" blocks setup success; "warning" is informational only */
  severity: "error" | "warning";
};

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
        severity: "error",
        message: has
          ? "Claude Desktop config has mcpServers.openclaw"
          : "Missing mcpServers.openclaw in Claude Desktop config — run setup again",
      });
    } catch {
      results.push({ name: "mcp-config", pass: false, severity: "error", message: "Failed to parse Claude Desktop config" });
    }
  } else {
    results.push({ name: "mcp-config", pass: false, severity: "error", message: "Claude Desktop config file not found" });
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
        severity: "error",
        message: enabled
          ? "OpenClaw claude-desktop plugin is enabled"
          : "Plugin claude-desktop not enabled in OpenClaw config — run setup again",
      });
    } catch {
      results.push({ name: "openclaw-plugin", pass: false, severity: "error", message: "Failed to parse OpenClaw config" });
    }
  } else {
    results.push({ name: "openclaw-plugin", pass: false, severity: "error", message: "OpenClaw config file not found" });
  }

  // 3. Extension files exist
  const extDir = path.join(os.homedir(), ".openclaw", "extensions", "claude-desktop");
  const extExists = fs.existsSync(extDir);
  results.push({
    name: "extension-files",
    pass: extExists,
    severity: "error",
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
    severity: "error",
    message: launcherExists
      ? `Launcher script present at ${launcherFile}`
      : `Launcher script missing — run setup again`,
  });

  // 5. Gateway reachable (warning only — gateway may not be running during setup)
  results.push({
    name: "gateway",
    pass: env.openclaw.gatewayReachable,
    severity: "warning",
    message: env.openclaw.gatewayReachable
      ? `Gateway reachable at ${env.openclaw.gatewayUrl}`
      : `Gateway not reachable at ${env.openclaw.gatewayUrl} — start OpenClaw before using the bridge`,
  });

  // 6. Platform check (UIA bridge requires Windows)
  const isWindows = process.platform === "win32";
  results.push({
    name: "platform",
    pass: isWindows,
    severity: "error",
    message: isWindows
      ? "Platform is Windows — UIA bridge supported"
      : "UIA bridge requires Windows — Claude Desktop bridge will not work on this platform",
  });

  // 7. Bridge scripts exist alongside extension
  const scriptsDir = path.join(extDir, "scripts", "bridge");
  const scriptsExist = fs.existsSync(scriptsDir);
  results.push({
    name: "bridge-scripts",
    pass: scriptsExist,
    severity: "error",
    message: scriptsExist
      ? `Bridge scripts present at ${scriptsDir}`
      : `Bridge scripts missing at ${scriptsDir} — run setup again`,
  });

  return results;
}
