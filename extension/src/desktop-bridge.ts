/**
 * desktop-bridge.ts — Windows UI Automation bridge for Claude Desktop
 *
 * Replaces the CDP (Chrome DevTools Protocol) bridge with a UIA-based
 * approach that works without --remote-debugging-port. Uses PowerShell
 * scripts from clawbridge-mcp to interact with Claude Desktop via the
 * Windows accessibility tree.
 *
 * Requires: Windows 10/11, Claude Desktop running.
 */

import { execFile } from "node:child_process";
import path from "node:path";

export interface DesktopBridgeOptions {
  /** Path to the directory containing PowerShell bridge scripts. */
  scriptsDir: string;
  /** Max time (ms) to wait for Claude to finish responding. Default 120_000. */
  responseTimeoutMs?: number;
  /** Polling interval (ms) when observing responses. Default 1_500. */
  pollIntervalMs?: number;
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
  private responseTimeoutMs: number;
  private pollIntervalMs: number;
  private connected = false;
  private observerTimer: ReturnType<typeof setInterval> | null = null;
  private lastObservedText = "";

  constructor(opts: DesktopBridgeOptions) {
    this.scriptsDir = opts.scriptsDir;
    this.responseTimeoutMs = opts.responseTimeoutMs ?? 120_000;
    this.pollIntervalMs = opts.pollIntervalMs ?? 1_500;
  }

  isConnected(): boolean {
    return this.connected;
  }

  /**
   * Ensure Claude Desktop is visible and the accessibility tree is active.
   * Replaces the CDP connect(host, port) — no network params needed for UIA.
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
    if (this.observerTimer) {
      clearInterval(this.observerTimer);
      this.observerTimer = null;
    }
  }

  /**
   * Inject a message into Claude Desktop's TipTap input and submit it.
   * Replaces the CDP Runtime.evaluate + Input.dispatchKeyEvent approach.
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

  /**
   * Read the last assistant response from Claude Desktop.
   * Replaces the CDP Runtime.evaluate DOM query approach.
   */
  async readLastResponse(): Promise<string> {
    const result = await runPS(
      this.scriptsDir,
      "read-response.ps1",
      [],
      15_000,
    );

    if (result.startsWith("RESPONSE:")) {
      return result.substring("RESPONSE:".length);
    }
    return "";
  }

  /**
   * Start observing Claude Desktop for new responses via polling.
   * Replaces the CDP MutationObserver + Runtime.addBinding approach.
   *
   * Polls read-response.ps1 at pollIntervalMs and calls the callback
   * whenever a new response is detected.
   */
  async observeResponses(
    callback: (data: { type: string; text: string }) => void,
  ): Promise<void> {
    // Stop any existing observer
    if (this.observerTimer) {
      clearInterval(this.observerTimer);
    }

    // Snapshot current response as baseline
    try {
      this.lastObservedText = await this.readLastResponse();
    } catch {
      this.lastObservedText = "";
    }

    this.observerTimer = setInterval(async () => {
      if (!this.connected) return;

      try {
        // Only emit when Claude has stopped responding
        const responding = await this.isResponding();
        if (responding) return;

        const text = await this.readLastResponse();
        if (text && text !== this.lastObservedText) {
          this.lastObservedText = text;
          callback({ type: "response", text });
        }
      } catch {
        // Swallow polling errors — will retry next interval
      }
    }, this.pollIntervalMs);

    // Don't keep the process alive just for polling
    if (this.observerTimer.unref) {
      this.observerTimer.unref();
    }
  }

  /** Check if Claude is currently generating a response. */
  private async isResponding(): Promise<boolean> {
    const result = await runPS(
      this.scriptsDir,
      "is-responding.ps1",
      [],
      10_000,
    );
    return result.trim() === "RESPONDING";
  }
}
