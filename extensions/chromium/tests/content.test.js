// Real DOM-level verification of src/content.js's Inspect Mode logic
// (locator-candidate building, evidence collection, hover/click wiring)
// using jsdom — a virtual but real DOM/CSSOM implementation, not just a
// syntax check (`node --check`, which was all that existed before this).
// This is still not an actual Chrome extension environment (there is no
// interactive browser session available in this environment — see
// docs/IMPLEMENTATION_STATUS.md's Environment notes for the same
// category of limitation on the macOS app's AppKit UI), but it exercises
// the exact DOM APIs content.js calls against real element/event
// behavior rather than assuming they work.

const { JSDOM } = require("jsdom");
const vm = require("vm");
const fs = require("fs");
const path = require("path");

let failureCount = 0;
function check(name, condition) {
  if (condition) {
    console.log(`PASS  ${name}`);
  } else {
    console.log(`FAIL  ${name}`);
    failureCount++;
  }
}

function makeSandbox(html, scrollOpts) {
  const dom = new JSDOM(html, { url: "https://example.com/pricing", runScripts: "outside-only", pretendToBeVisual: true });
  const window = dom.window;

  const sentMessages = [];
  let inspectMessageListener = null;
  let tileCounter = 0;

  window.chrome = {
    runtime: {
      sendMessage: (message, callback) => {
        sentMessages.push(message);
        if (typeof callback === "function") {
          // Simulate the background worker's async response — a real
          // request/response round trip via chrome.runtime.sendMessage's
          // callback form, same shape content.js actually uses.
          setTimeout(() => {
            if (message && message.kind === "capture.bridge.capture_tile") {
              callback({ imageDataBase64: `tile-${tileCounter++}` });
            } else {
              callback({ ok: true, payload: {} });
            }
          }, 0);
        }
      },
      onMessage: { addListener: (fn) => { inspectMessageListener = fn; } }
    }
  };
  // jsdom's window.crypto may not implement randomUUID depending on
  // version; content.js falls back to Date.now() if it's missing, so
  // this is optional, not a workaround for a real bug.
  if (!window.crypto || !window.crypto.randomUUID) {
    window.crypto = window.crypto || {};
    window.crypto.randomUUID = () => "test-uuid";
  }

  // jsdom doesn't implement real scrolling/layout; simulate it so the
  // full-page auto-scroll loop's *termination* logic (does it stop
  // exactly at the bottom, not one step early/late, not infinitely) is
  // exercised against real (if simplified) scroll-position bookkeeping
  // rather than a scrollY that never changes.
  if (scrollOpts) {
    let scrollY = 0;
    let scrollX = 0;
    const { viewportHeight, pageHeight, viewportWidth, pageWidth } = scrollOpts;
    if (viewportHeight != null) {
      Object.defineProperty(window, "innerHeight", { value: viewportHeight, configurable: true });
    }
    if (viewportWidth != null) {
      Object.defineProperty(window, "innerWidth", { value: viewportWidth, configurable: true });
    }
    Object.defineProperty(window, "scrollY", { get: () => scrollY, configurable: true });
    Object.defineProperty(window, "scrollX", { get: () => scrollX, configurable: true });
    window.scrollTo = (x, y) => {
      if (viewportWidth != null && pageWidth != null) {
        scrollX = Math.max(0, Math.min(x, Math.max(0, pageWidth - viewportWidth)));
      }
      if (viewportHeight != null && pageHeight != null) {
        scrollY = Math.max(0, Math.min(y, Math.max(0, pageHeight - viewportHeight)));
      }
    };
  }

  const source = fs.readFileSync(path.join(__dirname, "..", "src", "content.js"), "utf8");
  const vmContext = dom.getInternalVMContext();
  vm.createContext(vmContext);
  vm.runInContext(source, vmContext);

  return {
    window,
    sentMessages,
    toggleInspectMode: () => inspectMessageListener({ kind: "capture.inspect.toggle" }),
    triggerFullPageCapture: () => inspectMessageListener({ kind: "capture.fullpage.trigger" }),
    triggerFullPageCaptureHorizontal: () => inspectMessageListener({ kind: "capture.fullpage.trigger", axis: "horizontal" }),
    triggerFullPageCaptureReverse: () => inspectMessageListener({ kind: "capture.fullpage.trigger", reverse: true }),
    triggerFullPageCaptureHorizontalReverse: () => inspectMessageListener({ kind: "capture.fullpage.trigger", axis: "horizontal", reverse: true }),
    manualStart: () => inspectMessageListener({ kind: "capture.fullpage.manual.start" }),
    manualSnap: () => inspectMessageListener({ kind: "capture.fullpage.manual.snap" }),
    manualFinish: () => inspectMessageListener({ kind: "capture.fullpage.manual.finish" })
  };
}

// Always yields at least one real macrotask tick before the first check —
// some callers (manual capture) call this immediately after firing an
// action whose effects land in a setTimeout(0) callback, which a
// check-then-wait loop could otherwise race past without ever yielding.
async function waitUntil(conditionFn, timeoutMs = 2000) {
  const start = Date.now();
  do {
    await new Promise((resolve) => setTimeout(resolve, 5));
    if (conditionFn()) return;
  } while (Date.now() - start <= timeoutMs);
  throw new Error("timed out waiting for condition");
}

// --- Locator candidates: id, data-testid, classes, ancestry, DOM path ---
{
  const { window, sentMessages, toggleInspectMode } = makeSandbox(`
    <html><body>
      <main>
        <button id="cta-button" class="btn btn-primary" data-testid="cta">Buy now</button>
      </main>
    </body></html>
  `);

  toggleInspectMode();
  const button = window.document.getElementById("cta-button");
  const clickEvent = new window.MouseEvent("click", { bubbles: true, cancelable: true });
  button.dispatchEvent(clickEvent);

  check("Clicking an element while Inspect Mode is on sends exactly one message", sentMessages.length === 1);
  const message = sentMessages[0];
  check("Sent message has the exact shape MessageValidator expects", message.kind === "capture.bridge.request" && message.type === "inspect.element.result");

  const strategies = message.payload.locator.candidates.map((c) => c.strategy);
  check("Locator includes a dataTestID candidate", strategies.includes("dataTestID"));
  check("Locator includes a stableID candidate", strategies.includes("stableID"));
  check("Locator includes classAndStructure candidate", strategies.includes("classAndStructure"));
  check("Locator always includes the guaranteed absoluteDOMPath fallback", strategies.includes("absoluteDOMPath"));

  const stableID = message.payload.locator.candidates.find((c) => c.strategy === "stableID");
  check("stableID candidate value is a real CSS id selector", stableID.value === "#cta-button");

  check("Evidence carries the real page URL", message.payload.url === "https://example.com/pricing");
  check("Evidence includes a rect object with numeric fields", typeof message.payload.rect.width === "number");
  check("Evidence includes viewport info", typeof message.payload.viewport.width === "number");
  check("Evidence includes a real absolute XPath (spec §2.14's 'XPath optional')", message.payload.xpath === "/html/body/main/button");
  check(
    "accessibilityJSON is null when element-accessibility-inspector.js isn't loaded (this harness loads content.js alone)",
    message.payload.accessibilityJSON === null
  );
}

// --- absoluteXPath: 1-indexed among same-tag siblings, browser DevTools convention ---
{
  const { window, sentMessages, toggleInspectMode } = makeSandbox(`
    <html><body>
      <ul>
        <li>First</li>
        <li id="target">Second</li>
        <li>Third</li>
      </ul>
    </body></html>
  `);
  toggleInspectMode();
  const target = window.document.getElementById("target");
  target.dispatchEvent(new window.MouseEvent("click", { bubbles: true, cancelable: true }));
  check("absoluteXPath 1-indexes among same-tag siblings", sentMessages[0].payload.xpath === "/html/body/ul/li[2]");
}

// --- Typography/appearance/box-model evidence (spec §2.15/§2.16) ---
{
  const { window, sentMessages, toggleInspectMode } = makeSandbox(`
    <html><body>
      <button id="cta" style="
        font-family: Arial; font-size: 16px; font-weight: 700; font-style: italic;
        letter-spacing: 1px; text-transform: uppercase; text-decoration: underline;
        color: #ff0000; background-color: #00ff00; background-image: linear-gradient(45deg, red, blue);
        border-radius: 4px 8px 12px 16px; box-shadow: 2px 3px 4px rgba(0,0,0,0.5); filter: blur(2px); opacity: 0.9;
        border-top: 2px solid blue; padding: 10px; margin: 5px;
      ">Buy now</button>
    </body></html>
  `);
  toggleInspectMode();
  const button = window.document.getElementById("cta");
  button.dispatchEvent(new window.MouseEvent("click", { bubbles: true, cancelable: true }));

  const message = sentMessages[0];
  const typography = JSON.parse(message.payload.typographyJSON);
  const appearance = JSON.parse(message.payload.appearanceJSON);
  const boxModel = JSON.parse(message.payload.boxModelJSON);

  check("Typography evidence includes fontStyle", typography.fontStyle === "italic");
  check("Typography evidence includes letterSpacing", typography.letterSpacing === "1px");
  check("Typography evidence includes textTransform", typography.textTransform === "uppercase");
  check("Typography evidence includes textDecoration", typography.textDecoration === "underline");

  check("Appearance evidence includes the real background gradient as raw CSS", appearance.backgroundImage.includes("linear-gradient"));
  check("Appearance evidence includes the real box-shadow as raw CSS", appearance.boxShadow.includes("rgba(0, 0, 0, 0.5)") || appearance.boxShadow.includes("rgba(0,0,0,0.5)"));
  check("Appearance evidence includes the real filter as raw CSS", appearance.filter.includes("blur"));
  check("Appearance evidence includes opacity", appearance.opacity === "0.9");

  check("Box-model evidence includes the real per-side border-top width/style/color", boxModel.borderTopWidth === "2px" && boxModel.borderTopStyle === "solid");
}

// --- Clicking while Inspect Mode is OFF must not send anything ---
{
  const { window, sentMessages } = makeSandbox(`<html><body><button id="x">Click</button></body></html>`);
  const button = window.document.getElementById("x");
  button.dispatchEvent(new window.MouseEvent("click", { bubbles: true, cancelable: true }));
  check("No message is sent when Inspect Mode has never been toggled on", sentMessages.length === 0);
}

// --- Toggling Inspect Mode off again stops sending messages ---
{
  const { window, sentMessages, toggleInspectMode } = makeSandbox(`<html><body><button id="y">Click</button></body></html>`);
  toggleInspectMode(); // on
  toggleInspectMode(); // off again
  const button = window.document.getElementById("y");
  button.dispatchEvent(new window.MouseEvent("click", { bubbles: true, cancelable: true }));
  check("Toggling Inspect Mode off again stops sending messages", sentMessages.length === 0);
}

// --- An element with no id/data-testid/classes still gets a usable locator ---
{
  const { window, sentMessages, toggleInspectMode } = makeSandbox(`
    <html><body><main><section><p>Plain paragraph</p></section></main></body></html>
  `);
  toggleInspectMode();
  const paragraph = window.document.querySelector("p");
  paragraph.dispatchEvent(new window.MouseEvent("click", { bubbles: true, cancelable: true }));
  const candidates = sentMessages[0].payload.locator.candidates;
  check(
    "A plain element with no id/class/testid still produces at least an absoluteDOMPath candidate",
    candidates.some((c) => c.strategy === "absoluteDOMPath" && c.value.includes("p"))
  );
}

// --- Alt/Option-click sends a capture.element.result request instead of evidence ---
{
  const { window, sentMessages, toggleInspectMode } = makeSandbox(`
    <html><body><main><button id="cta">Buy</button></main></body></html>
  `);
  toggleInspectMode();
  const button = window.document.getElementById("cta");
  button.dispatchEvent(new window.MouseEvent("click", { bubbles: true, cancelable: true, altKey: true }));

  check("Alt-click sends exactly one message", sentMessages.length === 1);
  const message = sentMessages[0];
  check("Alt-click's message type is capture.element.result, not inspect.element.result", message.type === "capture.element.result");
  check("Capture request payload carries the locator", Array.isArray(message.payload.locator.candidates) && message.payload.locator.candidates.length > 0);
  check("Capture request payload carries the rect", typeof message.payload.rect.width === "number");
  check("Capture request payload carries devicePixelRatio (not the raw imageDataBase64 — that's added by background.js)", typeof message.payload.devicePixelRatio === "number");
}

// --- A plain click (no Alt) still sends the evidence-only request ---
{
  const { window, sentMessages, toggleInspectMode } = makeSandbox(`
    <html><body><main><button id="cta">Buy</button></main></body></html>
  `);
  toggleInspectMode();
  const button = window.document.getElementById("cta");
  button.dispatchEvent(new window.MouseEvent("click", { bubbles: true, cancelable: true, altKey: false }));
  check("A plain click (no Alt) sends inspect.element.result, not a capture request", sentMessages[0].type === "inspect.element.result");
}

// --- Full-page auto-scroll capture (spec Phase 4) ---
async function runFullPageCaptureTests() {
  // A page 3x the viewport height: with a 90%-of-viewport scroll step,
  // this should take a small number of steps and land exactly at the
  // bottom (maxScroll = pageHeight - viewportHeight), never overshooting
  // past it (the scrollTo stub itself clamps, matching real
  // window.scrollTo behavior) and never looping forever.
  {
    const { sentMessages, triggerFullPageCapture } = makeSandbox(
      `<html><body><div style="height:1500px">tall page</div></body></html>`,
      { viewportHeight: 500, pageHeight: 1500 }
    );
    triggerFullPageCapture();
    await waitUntil(() => sentMessages.some((m) => m.type === "capture.fullpage.result"));

    const result = sentMessages.find((m) => m.type === "capture.fullpage.result");
    check("Full-page capture sends exactly one capture.fullpage.result message", sentMessages.filter((m) => m.type === "capture.fullpage.result").length === 1);
    check("Full-page capture collects more than one tile for a page taller than the viewport", result.payload.tiles.length > 1);
    check("Full-page capture's first tile starts at scrollY 0", result.payload.tiles[0].scrollY === 0);
    check(
      "Full-page capture's last tile reaches the actual bottom of the page (pageHeight - viewportHeight)",
      result.payload.tiles[result.payload.tiles.length - 1].scrollY === 1000
    );
    check("Full-page capture reports the real devicePixelRatio", typeof result.payload.devicePixelRatio === "number");
    check(
      "Every tile carries real (non-empty) image data from the simulated background capture",
      result.payload.tiles.every((tile) => typeof tile.imageDataBase64 === "string" && tile.imageDataBase64.length > 0)
    );
  }

  // A page shorter than the viewport (nothing to scroll): should still
  // capture exactly one tile and terminate immediately, not loop.
  {
    const { sentMessages, triggerFullPageCapture } = makeSandbox(
      `<html><body><div style="height:100px">short page</div></body></html>`,
      { viewportHeight: 500, pageHeight: 100 }
    );
    triggerFullPageCapture();
    await waitUntil(() => sentMessages.some((m) => m.type === "capture.fullpage.result"));
    const result = sentMessages.find((m) => m.type === "capture.fullpage.result");
    check("A page shorter than the viewport still captures exactly one tile", result.payload.tiles.length === 1);
  }

  // Horizontal full-page capture (spec Phase 4's "horizontal" scrolling).
  {
    const { sentMessages, triggerFullPageCaptureHorizontal } = makeSandbox(
      `<html><body><div style="width:2400px">wide page</div></body></html>`,
      { viewportWidth: 800, pageWidth: 2400 }
    );
    triggerFullPageCaptureHorizontal();
    await waitUntil(() => sentMessages.some((m) => m.type === "capture.fullpage.result"));
    const result = sentMessages.find((m) => m.type === "capture.fullpage.result");
    check("Horizontal capture reports axis: 'horizontal'", result.payload.axis === "horizontal");
    check("Horizontal capture collects more than one tile for a page wider than the viewport", result.payload.tiles.length > 1);
    check("Horizontal capture's tiles carry scrollX, not scrollY", typeof result.payload.tiles[0].scrollX === "number" && result.payload.tiles[0].scrollY === undefined);
    check(
      "Horizontal capture's last tile reaches the actual right edge of the page (pageWidth - viewportWidth)",
      result.payload.tiles[result.payload.tiles.length - 1].scrollX === 1600
    );
  }
  // Reverse vertical capture: starts at the true bottom and steps
  // backward, ending exactly at scrollY 0 (not one step short/past it).
  {
    const { sentMessages, triggerFullPageCaptureReverse } = makeSandbox(
      `<html><body><div style="height:1500px">tall page</div></body></html>`,
      { viewportHeight: 500, pageHeight: 1500 }
    );
    triggerFullPageCaptureReverse();
    await waitUntil(() => sentMessages.some((m) => m.type === "capture.fullpage.result"));
    const result = sentMessages.find((m) => m.type === "capture.fullpage.result");
    check("Reverse capture collects more than one tile for a page taller than the viewport", result.payload.tiles.length > 1);
    check("Reverse capture's first tile starts at the true bottom (pageHeight - viewportHeight)", result.payload.tiles[0].scrollY === 1000);
    check("Reverse capture's last tile ends at the true top (scrollY 0)", result.payload.tiles[result.payload.tiles.length - 1].scrollY === 0);
  }

  // Reverse horizontal capture: starts at the true right edge and steps
  // backward, ending exactly at scrollX 0.
  {
    const { sentMessages, triggerFullPageCaptureHorizontalReverse } = makeSandbox(
      `<html><body><div style="width:2400px">wide page</div></body></html>`,
      { viewportWidth: 800, pageWidth: 2400 }
    );
    triggerFullPageCaptureHorizontalReverse();
    await waitUntil(() => sentMessages.some((m) => m.type === "capture.fullpage.result"));
    const result = sentMessages.find((m) => m.type === "capture.fullpage.result");
    check("Reverse horizontal capture's first tile starts at the true right edge (pageWidth - viewportWidth)", result.payload.tiles[0].scrollX === 1600);
    check("Reverse horizontal capture's last tile ends at the true left edge (scrollX 0)", result.payload.tiles[result.payload.tiles.length - 1].scrollX === 0);
  }

  // Manual (user-paced) vertical capture: the user scrolls themselves and
  // explicitly snaps each tile, rather than the fixed-step auto loop.
  {
    const { window, sentMessages, manualStart, manualSnap, manualFinish } = makeSandbox(
      `<html><body><div style="height:1500px">tall page</div></body></html>`,
      { viewportHeight: 500, pageHeight: 1500 }
    );
    manualStart();
    window.scrollTo(0, 0);
    manualSnap();
    await waitUntil(() => sentMessages.filter((m) => m.kind === "capture.bridge.capture_tile").length === 1);
    window.scrollTo(0, 700);
    manualSnap();
    await waitUntil(() => sentMessages.filter((m) => m.kind === "capture.bridge.capture_tile").length === 2);
    manualFinish();
    await waitUntil(() => sentMessages.some((m) => m.type === "capture.fullpage.result"));

    const result = sentMessages.find((m) => m.type === "capture.fullpage.result");
    check("Manual capture sends exactly one capture.fullpage.result message", sentMessages.filter((m) => m.type === "capture.fullpage.result").length === 1);
    check("Manual capture reports exactly the tiles the user snapped", result.payload.tiles.length === 2);
    check("Manual capture's tiles carry the exact scroll positions the user snapped at", result.payload.tiles[0].scrollY === 0 && result.payload.tiles[1].scrollY === 700);
    check("Manual capture infers axis: vertical from the scroll positions used", result.payload.axis === "vertical");
  }

  // Manual horizontal capture: axis is inferred from which coordinate
  // actually varied across the snapped tiles.
  {
    const { window, sentMessages, manualStart, manualSnap, manualFinish } = makeSandbox(
      `<html><body><div style="width:2400px">wide page</div></body></html>`,
      { viewportWidth: 800, pageWidth: 2400 }
    );
    manualStart();
    window.scrollTo(0, 0);
    manualSnap();
    await waitUntil(() => sentMessages.filter((m) => m.kind === "capture.bridge.capture_tile").length === 1);
    window.scrollTo(1200, 0);
    manualSnap();
    await waitUntil(() => sentMessages.filter((m) => m.kind === "capture.bridge.capture_tile").length === 2);
    manualFinish();
    await waitUntil(() => sentMessages.some((m) => m.type === "capture.fullpage.result"));

    const result = sentMessages.find((m) => m.type === "capture.fullpage.result");
    check("Manual horizontal capture infers axis: horizontal from the scroll positions used", result.payload.axis === "horizontal");
    check("Manual horizontal capture's tiles carry scrollX, not scrollY", typeof result.payload.tiles[1].scrollX === "number" && result.payload.tiles[1].scrollY === undefined);
  }

  // Finishing a manual capture with zero snapped tiles sends nothing.
  {
    const { sentMessages, manualStart, manualFinish } = makeSandbox(
      `<html><body><div style="height:1500px">tall page</div></body></html>`,
      { viewportHeight: 500, pageHeight: 1500 }
    );
    manualStart();
    manualFinish();
    check("Finishing a manual capture with no snapped tiles sends nothing", sentMessages.length === 0);
  }
}

// --- accessibilityJSON is populated end-to-end when both content
// scripts are actually loaded together, in real manifest.json order ---
{
  const dom = new JSDOM(
    `<html><body><main><button id="cta">Buy now</button></main></body></html>`,
    { url: "https://example.com/pricing", runScripts: "outside-only", pretendToBeVisual: true }
  );
  const window = dom.window;
  const sentMessages = [];
  let inspectMessageListener = null;
  window.chrome = {
    runtime: {
      sendMessage: (message) => sentMessages.push(message),
      onMessage: { addListener: (fn) => { inspectMessageListener = fn; } }
    }
  };
  const vmContext = dom.getInternalVMContext();
  vm.createContext(vmContext);
  vm.runInContext(fs.readFileSync(path.join(__dirname, "..", "src", "content.js"), "utf8"), vmContext);
  vm.runInContext(fs.readFileSync(path.join(__dirname, "..", "src", "element-accessibility-inspector.js"), "utf8"), vmContext);

  inspectMessageListener({ kind: "capture.inspect.toggle" });
  const button = window.document.getElementById("cta");
  button.dispatchEvent(new window.MouseEvent("click", { bubbles: true, cancelable: true }));

  const accessibility = JSON.parse(sentMessages[0].payload.accessibilityJSON);
  check(
    "accessibilityJSON is populated when element-accessibility-inspector.js is loaded alongside content.js",
    accessibility.role === "button" && accessibility.accessibleName === "Buy now" && accessibility.focusable === true
  );
}

// --- typographyJSON's variableFontAxes/openTypeFeatures are populated
// end-to-end when typography-features-inspector.js is loaded alongside
// content.js ---
{
  const dom = new JSDOM(
    `<html><body><button id="cta" style="font-variation-settings: 'wght' 650; font-feature-settings: 'liga' 1;">Buy now</button></body></html>`,
    { url: "https://example.com/pricing", runScripts: "outside-only", pretendToBeVisual: true }
  );
  const window = dom.window;
  const sentMessages = [];
  let inspectMessageListener = null;
  window.chrome = {
    runtime: {
      sendMessage: (message) => sentMessages.push(message),
      onMessage: { addListener: (fn) => { inspectMessageListener = fn; } }
    }
  };
  const vmContext = dom.getInternalVMContext();
  vm.createContext(vmContext);
  vm.runInContext(fs.readFileSync(path.join(__dirname, "..", "src", "content.js"), "utf8"), vmContext);
  vm.runInContext(fs.readFileSync(path.join(__dirname, "..", "src", "typography-features-inspector.js"), "utf8"), vmContext);

  inspectMessageListener({ kind: "capture.inspect.toggle" });
  window.document.getElementById("cta").dispatchEvent(new window.MouseEvent("click", { bubbles: true, cancelable: true }));

  const typography = JSON.parse(sentMessages[0].payload.typographyJSON);
  check(
    "typographyJSON's variableFontAxes/openTypeFeatures are populated when typography-features-inspector.js is loaded alongside content.js",
    typography.variableFontAxes.wght === 650 && typography.openTypeFeatures.liga === 1
  );
}

runFullPageCaptureTests().then(() => {
  console.log(`=== ${failureCount === 0 ? "ALL CHECKS PASSED" : `${failureCount} CHECK(S) FAILED`} ===`);
  process.exit(failureCount === 0 ? 0 : 1);
}).catch((error) => {
  console.error("FAIL  full-page capture test harness threw:", error);
  process.exit(1);
});
