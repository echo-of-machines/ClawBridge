#!/usr/bin/env node
import { parseArgs } from "node:util";
import { detect } from "./setup/detect.js";
import { installExtension } from "./setup/extension.js";
import { createLauncher } from "./setup/launcher.js";
import { installMcpConfig } from "./setup/mcp-config.js";
import { uninstall, printUninstallSummary } from "./setup/uninstall.js";
import { validate } from "./setup/validate.js";

const GREEN = "\x1b[32m";
const RED = "\x1b[31m";
const CYAN = "\x1b[36m";
const RESET = "\x1b[0m";

const ok = (msg: string) => console.log(`${GREEN}  ✓${RESET} ${msg}`);
const fail = (msg: string) => console.log(`${RED}  ✗${RESET} ${msg}`);
const step = (n: number, msg: string) => console.log(`\n${CYAN}[${n}/6]${RESET} ${msg}`);

const { values } = parseArgs({
  options: {
    status: { type: "boolean", default: false },
    uninstall: { type: "boolean", default: false },
    reinstall: { type: "boolean", default: false },
  },
  strict: false,
});

async function main(): Promise<void> {
  console.log(`\n${CYAN}ClawBridge Setup${RESET} — Claude Desktop + OpenClaw Bridge\n`);

  const env = await detect();

  // --- Status mode ---
  if (values.status) {
    const checks = await validate(env);
    for (const c of checks) {
      (c.pass ? ok : fail)(c.message);
    }
    const allPass = checks.every((c) => c.pass);
    process.exitCode = allPass ? 0 : 1;
    return;
  }

  // --- Uninstall mode ---
  if (values.uninstall) {
    const result = uninstall(env);
    printUninstallSummary(result);
    return;
  }

  // --- Reinstall: uninstall first, then continue to setup ---
  if (values.reinstall) {
    console.log("Removing existing installation...");
    const result = uninstall(env);
    printUninstallSummary(result);
    // Re-detect after uninstall
    const freshEnv = await detect();
    await runSetup(freshEnv);
    return;
  }

  // --- Default: setup wizard ---
  await runSetup(env);
}

async function runSetup(env: Awaited<ReturnType<typeof detect>>): Promise<void> {
  // Step 1: Detect Claude Desktop
  step(1, "Detecting Claude Desktop...");
  if (env.claudeDesktop.found) {
    ok(`Found at ${env.claudeDesktop.execPath}`);
  } else {
    fail("Claude Desktop not found — install it from https://claude.ai/download");
  }

  // Step 2: Detect OpenClaw
  step(2, "Detecting OpenClaw...");
  if (env.openclaw.gatewayReachable) {
    ok(`Gateway reachable at ${env.openclaw.gatewayUrl}`);
  } else {
    fail(`Gateway not reachable at ${env.openclaw.gatewayUrl} — start OpenClaw first`);
  }
  if (env.openclaw.configExists) {
    ok(`Config found at ${env.openclaw.configPath}`);
  }

  // Step 3: Install MCP config
  step(3, "Installing MCP server config...");
  const mcp = installMcpConfig(env);
  ok(`Written to ${mcp.configPath}`);

  // Step 4: Install OpenClaw extension
  step(4, "Installing OpenClaw extension...");
  const ext = installExtension(env);
  ok(`Installed to ${ext.extensionDir}`);

  // Step 5: Create launcher
  step(5, "Creating launcher script...");
  const launcher = createLauncher(env);
  ok(`Created at ${launcher.launcherFile}`);

  // Step 6: Validate
  step(6, "Validating installation...");
  const checks = await validate(env);
  for (const c of checks) {
    (c.pass ? ok : fail)(c.message);
  }

  const allPass = checks.filter((c) => c.name !== "cdp-port").every((c) => c.pass);
  if (allPass) {
    console.log(`\n${GREEN}Setup complete!${RESET}`);
    console.log(`\nNext steps:`);
    console.log(`  1. Restart Claude Desktop using the launcher script: ${launcher.launcherFile}`);
    console.log(`  2. Restart OpenClaw to load the new extension`);
    console.log(`  3. Send a message to OpenClaw — it will be routed through Claude Desktop\n`);
  } else {
    console.log(`\n${RED}Setup completed with warnings.${RESET} Review the checks above.\n`);
    process.exitCode = 1;
  }
}

main().catch((err) => {
  console.error(`\n${RED}Setup failed:${RESET} ${err instanceof Error ? err.message : String(err)}\n`);
  process.exitCode = 1;
});
