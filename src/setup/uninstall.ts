import type { DetectResult } from "./detect.js";
import { removeExtension } from "./extension.js";
import { removeLauncher } from "./launcher.js";
import { removeMcpConfig } from "./mcp-config.js";

export type UninstallResult = {
  mcpConfig: boolean;
  extension: boolean;
  launcher: boolean;
};

export function uninstall(env: DetectResult): UninstallResult {
  const launcher = removeLauncher(env);
  const extension = removeExtension(env);
  const mcpConfig = removeMcpConfig(env);

  return {
    mcpConfig: mcpConfig.removed,
    extension: extension.removed,
    launcher: launcher.removed,
  };
}

export function printUninstallSummary(result: UninstallResult): void {
  const log = (label: string, removed: boolean) => {
    const status = removed ? "removed" : "not found (skipped)";
    console.log(`  ${label}: ${status}`);
  };

  console.log("\nClawBridge uninstall summary:");
  log("MCP server config", result.mcpConfig);
  log("OpenClaw extension", result.extension);
  log("Launcher script", result.launcher);
  console.log("");
}
