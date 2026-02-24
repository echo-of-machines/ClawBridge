/**
 * uia-bridge.ts — Windows UI Automation bridge for Claude Desktop
 *
 * Sends messages to and reads responses from Claude Desktop using
 * Windows UIA + Win32 APIs via PowerShell subprocess calls.
 *
 * PowerShell scripts are stored in scripts/bridge/ and invoked via execFile.
 * Requires: Windows 10/11, Claude Desktop running.
 */

import { execFile } from "node:child_process";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

export interface UIABridgeOptions {
  /** Max time (ms) to wait for Claude to finish responding. Default 120 000. */
  responseTimeoutMs?: number;
  /** Polling interval (ms) when waiting for a response. Default 1 500. */
  pollIntervalMs?: number;
  /** Enable debug logging to stderr. Default false. */
  debug?: boolean;
}

export interface SendResult {
  ok: boolean;
  error?: string;
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);
// Scripts are at <package>/scripts/bridge/ relative to dist/
const SCRIPTS_DIR = join(__dirname, "..", "scripts", "bridge");

function log(msg: string, debug: boolean): void {
  if (debug) process.stderr.write(`[uia-bridge] ${msg}\n`);
}

/** Run a PowerShell script file with optional arguments. */
function runPS(
  scriptName: string,
  args: string[] = [],
  timeoutMs = 30_000,
): Promise<string> {
  const scriptPath = join(SCRIPTS_DIR, scriptName);
  return new Promise((resolve, reject) => {
    execFile(
      "powershell",
      ["-ExecutionPolicy", "Bypass", "-File", scriptPath, ...args],
      { timeout: timeoutMs, windowsHide: true },
      (err, stdout, stderr) => {
        if (err) {
          return reject(
            new Error(`PowerShell error (${scriptName}): ${err.message}\n${stderr}`),
          );
        }
        resolve(stdout.trim());
      },
    );
  });
}

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

// ---------------------------------------------------------------------------
// Bridge class
// ---------------------------------------------------------------------------

export class UIABridge {
  private opts: Required<UIABridgeOptions>;
  private ready = false;

  constructor(opts: UIABridgeOptions = {}) {
    this.opts = {
      responseTimeoutMs: opts.responseTimeoutMs ?? 120_000,
      pollIntervalMs: opts.pollIntervalMs ?? 1_500,
      debug: opts.debug ?? false,
    };
  }

  /** Ensure Claude Desktop is visible and accessibility tree is active. */
  async ensureAccessibility(): Promise<void> {
    log("Ensuring accessibility...", this.opts.debug);
    const result = await runPS("ensure-accessibility.ps1", [], 15_000);

    if (result === "OK") {
      this.ready = true;
      log("Accessibility OK", this.opts.debug);
      return;
    }

    if (result.includes("NO_MAIN_CONTENT")) {
      log("main-content not found, trying silent Narrator...", this.opts.debug);
      await runPS("silent-narrator-trigger.ps1", [], 15_000);

      const recheck = await runPS("ensure-accessibility.ps1", [], 15_000);
      if (recheck === "OK") {
        this.ready = true;
        log("Accessibility OK (after Narrator)", this.opts.debug);
        return;
      }
      throw new Error(`Accessibility setup failed after Narrator: ${recheck}`);
    }

    throw new Error(`Accessibility setup failed: ${result}`);
  }

  /** Send a message to Claude Desktop. Does NOT wait for response. */
  async sendMessage(text: string): Promise<SendResult> {
    if (!this.ready) await this.ensureAccessibility();
    log(`Sending: "${text.substring(0, 60)}..."`, this.opts.debug);

    const result = await runPS("send-message.ps1", ["-Message", text], 30_000);

    if (result === "OK") {
      return { ok: true };
    }
    return { ok: false, error: result };
  }

  /** Read the latest assistant response from the conversation. */
  async readLastResponse(): Promise<string | null> {
    const result = await runPS("read-response.ps1", [], 15_000);

    if (result.startsWith("RESPONSE:")) {
      return result.substring("RESPONSE:".length);
    }
    if (result.includes("NO_RESPONSE") || result.includes("EMPTY_RESPONSE")) {
      return null;
    }
    log(`Read error: ${result}`, this.opts.debug);
    return null;
  }

  /** Check if Claude is currently generating a response. */
  async isResponding(): Promise<boolean> {
    const result = await runPS("is-responding.ps1", [], 10_000);
    return result.trim() === "RESPONDING";
  }

  /**
   * Send a message and wait for the complete response.
   * Polls until Claude stops responding and a new response appears.
   */
  async sendAndWaitForResponse(
    text: string,
    timeoutMs?: number,
  ): Promise<string> {
    const timeout = timeoutMs ?? this.opts.responseTimeoutMs;
    const poll = this.opts.pollIntervalMs;

    // Read current response before sending (to detect new one)
    const beforeResponse = await this.readLastResponse();

    // Send
    const sendResult = await this.sendMessage(text);
    if (!sendResult.ok) {
      throw new Error(`Send failed: ${sendResult.error}`);
    }

    // Wait for response
    log("Waiting for response...", this.opts.debug);
    const startTime = Date.now();
    await sleep(1000); // give Claude a moment to start

    while (Date.now() - startTime < timeout) {
      const responding = await this.isResponding();

      if (!responding) {
        const currentResponse = await this.readLastResponse();
        if (currentResponse && currentResponse !== beforeResponse) {
          log(`Got response: "${currentResponse.substring(0, 60)}..."`, this.opts.debug);
          return currentResponse;
        }
      }

      await sleep(poll);
    }

    throw new Error(`Timed out waiting for response after ${timeout}ms`);
  }
}
