/**
 * Quick E2E smoke test for the UIA bridge.
 * Usage: node scripts/bridge/test-e2e.mjs
 *
 * This sends a short test message to Claude Desktop and waits for a response.
 */

import { UIABridge } from "../../dist/uia-bridge.js";

const bridge = new UIABridge({ debug: true, responseTimeoutMs: 60_000 });

console.log("=== ClawBridge UIA E2E Test ===\n");

try {
  console.log("1. Ensuring accessibility...");
  await bridge.ensureAccessibility();
  console.log("   OK\n");

  console.log("2. Checking is-responding...");
  const responding = await bridge.isResponding();
  console.log(`   ${responding ? "RESPONDING" : "IDLE"}\n`);

  console.log("3. Reading current last response...");
  const before = await bridge.readLastResponse();
  console.log(`   ${before ? before.substring(0, 100) + "..." : "(none)"}\n`);

  console.log("4. Sending test message...");
  const result = await bridge.sendMessage("Hi! Please reply with exactly: CLAWBRIDGE_TEST_OK");
  console.log(`   Send result: ${JSON.stringify(result)}\n`);

  if (!result.ok) {
    console.error("Send failed, aborting.");
    process.exit(1);
  }

  console.log("5. Waiting for response (up to 60s)...");
  const startTime = Date.now();

  // Poll for response
  let response = null;
  while (Date.now() - startTime < 60_000) {
    const isResp = await bridge.isResponding();
    if (!isResp) {
      const current = await bridge.readLastResponse();
      if (current && current !== before) {
        response = current;
        break;
      }
    }
    console.log(`   ... still waiting (${Math.round((Date.now() - startTime) / 1000)}s, responding=${isResp})`);
    await new Promise((r) => setTimeout(r, 2000));
  }

  if (response) {
    console.log(`\n6. Got response (${response.length} chars):`);
    console.log(`   "${response.substring(0, 200)}"`);
    console.log("\n=== E2E TEST PASSED ===");
  } else {
    console.log("\n   Timed out waiting for response.");
    console.log("\n=== E2E TEST INCOMPLETE (timeout) ===");
  }
} catch (err) {
  console.error("Error:", err.message);
  process.exit(1);
}
