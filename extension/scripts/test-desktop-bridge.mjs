/**
 * Quick E2E test of the DesktopBridge (extension bridge).
 * Tests the same PowerShell-based approach but through the extension's bridge class.
 */
import { execFile } from "node:child_process";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const SCRIPTS_DIR = path.resolve(__dirname, "..", "..", "..", "packages", "clawbridge-mcp", "scripts", "bridge");

// Inline a minimal DesktopBridge since we can't import TS directly
function runPS(scriptName, args = [], timeoutMs = 30000) {
  const scriptPath = path.join(SCRIPTS_DIR, scriptName);
  return new Promise((resolve, reject) => {
    execFile(
      "powershell",
      ["-ExecutionPolicy", "Bypass", "-File", scriptPath, ...args],
      { timeout: timeoutMs, windowsHide: true },
      (err, stdout, stderr) => {
        if (err) return reject(new Error(`PS error (${scriptName}): ${err.message}\n${stderr}`));
        resolve(stdout.trim());
      },
    );
  });
}

console.log("=== DesktopBridge E2E Test ===\n");
console.log(`Scripts dir: ${SCRIPTS_DIR}\n`);

// 1. connect (ensure-accessibility)
console.log("1. connect() — ensure accessibility...");
const accessResult = await runPS("ensure-accessibility.ps1", [], 20000);
console.log(`   Result: ${accessResult}\n`);

// 2. injectMessage
console.log("2. injectMessage() — sending test message...");
const sendResult = await runPS("send-message.ps1", ["-Message", "Say exactly: DESKTOP_BRIDGE_E2E_OK"]);
console.log(`   Result: ${sendResult}\n`);

// 3. Wait and check is-responding
console.log("3. Waiting 3s, then checking isResponding...");
await new Promise((r) => setTimeout(r, 3000));
const respondResult = await runPS("is-responding.ps1", [], 10000);
console.log(`   Result: ${respondResult}\n`);

// 4. Poll for response
console.log("4. Polling for response...");
let response = null;
for (let i = 0; i < 15; i++) {
  await new Promise((r) => setTimeout(r, 1500));
  const isResp = await runPS("is-responding.ps1", [], 10000);
  if (isResp.trim() === "IDLE") {
    const readResult = await runPS("read-response.ps1", [], 15000);
    if (readResult.startsWith("RESPONSE:")) {
      const text = readResult.substring("RESPONSE:".length);
      if (text && text !== "CLAWBRIDGE_FULL_PIPELINE_OK") {
        response = text;
        break;
      }
    }
  }
  process.stderr.write(`   poll ${i + 1}: ${isResp.trim()}\n`);
}

if (response) {
  console.log(`   Response: "${response}"\n`);
  const pass = response === "DESKTOP_BRIDGE_E2E_OK";
  console.log(`   ${pass ? "PASS" : "FAIL"}: expected "DESKTOP_BRIDGE_E2E_OK"\n`);
} else {
  console.log("   FAIL: no new response detected\n");
}

// 5. observeResponses simulation
console.log("5. observeResponses() simulation — send and poll...");
const baseline = response || "";
await runPS("send-message.ps1", ["-Message", "Say exactly: OBSERVER_TEST_OK"]);
let observed = null;
for (let i = 0; i < 15; i++) {
  await new Promise((r) => setTimeout(r, 1500));
  const isResp = await runPS("is-responding.ps1", [], 10000);
  if (isResp.trim() !== "IDLE") continue;
  const readResult = await runPS("read-response.ps1", [], 15000);
  if (readResult.startsWith("RESPONSE:")) {
    const text = readResult.substring("RESPONSE:".length);
    if (text && text !== baseline) {
      observed = text;
      break;
    }
  }
}
if (observed) {
  const pass = observed === "OBSERVER_TEST_OK";
  console.log(`   Observed: "${observed}" — ${pass ? "PASS" : "FAIL"}\n`);
} else {
  console.log("   FAIL: observer did not detect new response\n");
}

console.log("=== Test Complete ===");
