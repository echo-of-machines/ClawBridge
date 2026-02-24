/**
 * Quick E2E test of the UIABridge TypeScript class.
 * Run: node --experimental-specifier-resolution=node scripts/test-uia-bridge.mjs
 */
import { UIABridge } from "../dist/uia-bridge.js";

const bridge = new UIABridge({ debug: true });

console.log("=== UIABridge E2E Test ===\n");

// 1. Ensure accessibility
console.log("1. Ensuring accessibility...");
await bridge.ensureAccessibility();
console.log("   OK\n");

// 2. Read baseline response
console.log("2. Reading baseline response...");
const baseline = await bridge.readLastResponse();
console.log(`   Baseline: "${baseline?.substring(0, 60) ?? "(null)"}"\n`);

// 3. Check is-responding
console.log("3. Checking is-responding...");
const responding = await bridge.isResponding();
console.log(`   Responding: ${responding}\n`);

// 4. Send message
console.log("4. Sending test message...");
const sendResult = await bridge.sendMessage("Say exactly: CLAWBRIDGE_TS_BRIDGE_OK");
console.log(`   Send result: ${JSON.stringify(sendResult)}\n`);

// 5. Wait for response
console.log("5. Waiting for response (polling)...");
const startTime = Date.now();
let response = null;
for (let i = 0; i < 20; i++) {
  await new Promise((r) => setTimeout(r, 1500));
  const isResp = await bridge.isResponding();
  if (!isResp) {
    const current = await bridge.readLastResponse();
    if (current && current !== baseline) {
      response = current;
      break;
    }
  }
  process.stderr.write(`   poll ${i + 1}: ${isResp ? "RESPONDING" : "IDLE"}\n`);
}
const elapsed = Date.now() - startTime;

if (response) {
  console.log(`   Got response in ${elapsed}ms: "${response.substring(0, 100)}"\n`);
} else {
  console.log(`   No new response after ${elapsed}ms\n`);
}

// 6. Test sendAndWaitForResponse
console.log("6. Testing sendAndWaitForResponse...");
try {
  const fullResponse = await bridge.sendAndWaitForResponse(
    "Say exactly: CLAWBRIDGE_FULL_PIPELINE_OK",
    30000,
  );
  console.log(`   Full pipeline response: "${fullResponse.substring(0, 100)}"\n`);
} catch (err) {
  console.log(`   Error: ${err.message}\n`);
}

console.log("=== Test Complete ===");
