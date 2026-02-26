/**
 * desktop-bridge.ts — Windows UI Automation bridge for Claude Desktop
 *
 * Uses PowerShell scripts from clawbridge-mcp to inject messages into
 * Claude Desktop via the Windows accessibility tree. Response path is
 * handled by Claude Desktop calling MCP tools directly.
 *
 * Requires: Windows 10/11, Claude Desktop running.
 */

import { execFile } from "node:child_process";
import path from "node:path";

export interface DesktopBridgeOptions {
  /** Path to the directory containing PowerShell bridge scripts. */
  scriptsDir: string;
}

/** Run a PowerShell script file with optional arguments. */
function runPS(
  scriptsDir: string,
  scriptName: string,
  args: string[] = [],
  timeoutMs = 30_000,
): Promise<string> {
  const scriptPath = path.join(scriptsDir, scriptName);
  return new Promise((resolve, reject) => {
    execFile(
      "powershell",
      ["-ExecutionPolicy", "Bypass", "-File", scriptPath, ...args],
      { timeout: timeoutMs, windowsHide: true },
      (err, stdout, stderr) => {
        if (err) {
          return reject(
            new Error(
              `PowerShell error (${scriptName}): ${err.message}\n${stderr}`,
            ),
          );
        }
        resolve(stdout.trim());
      },
    );
  });
}

export class DesktopBridge {
  private scriptsDir: string;
  private connected = false;

  constructor(opts: DesktopBridgeOptions) {
    this.scriptsDir = opts.scriptsDir;
  }

  isConnected(): boolean {
    return this.connected;
  }

  /**
   * Ensure Claude Desktop is visible and the accessibility tree is active.
   */
  async connect(): Promise<void> {
    const result = await runPS(
      this.scriptsDir,
      "ensure-accessibility.ps1",
      [],
      20_000,
    );

    if (result === "OK" || result.includes("OK")) {
      this.connected = true;
      return;
    }

    throw new Error(`UIA accessibility setup failed: ${result}`);
  }

  disconnect(): void {
    this.connected = false;
  }

  /**
   * Inject a message into Claude Desktop's TipTap input and submit it.
   */
  async injectMessage(text: string): Promise<void> {
    if (!this.connected) await this.connect();

    const result = await runPS(
      this.scriptsDir,
      "send-message.ps1",
      ["-Message", text],
      30_000,
    );

    if (result !== "OK") {
      throw new Error(`UIA send failed: ${result}`);
    }
  }
}
