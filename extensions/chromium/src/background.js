// Capture browser bridge — background service worker.
//
// Ported from the original Capture app's extensions/chromium (owned by
// the user; see docs/REFERENCE_PROVENANCE.md).
//
// Content scripts never talk to the native host directly (content
// scripts must send requests to the service worker); this is the only
// place `chrome.runtime.connectNative` is called. One long-lived native
// port is kept open and reused across messages rather than reconnecting
// per request, since Chrome starts a fresh snapzy-native-host process for
// each connectNative call.
//
// NOT YET LOADED INTO A REAL CHROME SESSION in this environment — written
// carefully against Chrome's documented extension APIs and verified at
// the DOM/data level via the tests in tests/, but needs manual load-and-
// click QA in an actual browser before shipping (see docs/REFERENCE_PROVENANCE.md).

const NATIVE_HOST_NAME = "com.trongduong.snapzy.browserbridge";

/** @type {chrome.runtime.Port | null} */
let nativePort = null;
/** @type {Map<string, (response: unknown) => void>} */
const pendingRequests = new Map();

function connectToNativeHost() {
  const port = chrome.runtime.connectNative(NATIVE_HOST_NAME);

  port.onMessage.addListener((message) => {
    const requestId = message && typeof message.id === "string" ? message.id : null;
    if (requestId && pendingRequests.has(requestId)) {
      pendingRequests.get(requestId)(message);
      pendingRequests.delete(requestId);
    }
  });

  port.onDisconnect.addListener(() => {
    // The native host process exits when Chrome disconnects it, or the
    // Mac app isn't running / the socket isn't reachable. Any requests
    // still waiting get a synthetic failure rather than hanging forever.
    const disconnectError = chrome.runtime.lastError?.message ?? "Native host disconnected.";
    for (const resolve of pendingRequests.values()) {
      resolve({ ok: false, error: { code: "NATIVE_HOST_DISCONNECTED", message: disconnectError } });
    }
    pendingRequests.clear();
    nativePort = null;
  });

  return port;
}

function sendToNativeHost(envelope) {
  return new Promise((resolve) => {
    if (!nativePort) {
      nativePort = connectToNativeHost();
    }
    pendingRequests.set(envelope.id, resolve);
    nativePort.postMessage(envelope);
  });
}

function makeRequestId() {
  return (typeof globalThis.crypto !== "undefined" && globalThis.crypto.randomUUID) ? globalThis.crypto.randomUUID() : `${Date.now()}-${Math.random()}`;
}

function relayToNativeHost(type, tabSessionId, payload, sendResponse) {
  const envelope = { version: 1, id: makeRequestId(), type, tabSessionId, payload: payload ?? {} };
  sendToNativeHost(envelope).then(sendResponse);
}

/// One-click element capture: capture the *visible tab* — a real,
/// documented Chrome API (`chrome.tabs.captureVisibleTab`) that needs no
/// knowledge of the browser window's on-screen position — and report the
/// full PNG plus the element's CSS-pixel rect/devicePixelRatio so the app
/// can crop precisely itself. This must run in the background worker:
/// `captureVisibleTab` isn't available to content scripts.
function captureElementAndRelay(sender, request, sendResponse) {
  const tabId = sender.tab && sender.tab.id;
  if (tabId == null) {
    sendResponse({ ok: false, error: { code: "NO_ACTIVE_TAB", message: "No tab to capture from." } });
    return;
  }
  chrome.tabs.captureVisibleTab(sender.tab.windowId, { format: "png" }, (dataUrl) => {
    if (chrome.runtime.lastError || !dataUrl) {
      sendResponse({ ok: false, error: { code: "CAPTURE_FAILED", message: chrome.runtime.lastError?.message ?? "captureVisibleTab returned no data." } });
      return;
    }
    const base64 = dataUrl.replace(/^data:image\/png;base64,/, "");
    relayToNativeHost(
      "capture.element.result",
      request.tabSessionId,
      {
        locator: request.payload.locator,
        rect: request.payload.rect,
        devicePixelRatio: request.payload.devicePixelRatio,
        imageDataBase64: base64
      },
      sendResponse
    );
  });
}

/// One tile of automatic vertical/horizontal scrolling full-page capture:
/// the content script drives the scrolling (it's the only side that
/// knows page layout/scroll position) but must ask the background worker
/// to actually snap each tile, since `captureVisibleTab` isn't available
/// to content scripts. Purely local — never touches the native host —
/// one full-page capture ends with a *single* `capture.fullpage.result`
/// relay once every tile is collected.
function captureOneTile(sender, sendResponse) {
  const tabId = sender.tab && sender.tab.id;
  if (tabId == null) {
    sendResponse(null);
    return;
  }
  chrome.tabs.captureVisibleTab(sender.tab.windowId, { format: "png" }, (dataUrl) => {
    if (chrome.runtime.lastError || !dataUrl) {
      sendResponse(null);
      return;
    }
    sendResponse({ imageDataBase64: dataUrl.replace(/^data:image\/png;base64,/, "") });
  });
}

// Content scripts (and the popup, if one is added later) ask the
// background worker to relay a message to the native host/Mac app.
chrome.runtime.onMessage.addListener((request, sender, sendResponse) => {
  if (request && request.kind === "capture.bridge.capture_tile") {
    captureOneTile(sender, sendResponse);
    return true;
  }

  if (!request || request.kind !== "capture.bridge.request") {
    return false; // not for us — let other listeners (if any) handle it
  }

  if (request.type === "capture.element.result") {
    captureElementAndRelay(sender, request, sendResponse);
    return true;
  }

  relayToNativeHost(request.type, request.tabSessionId, request.payload, sendResponse);
  return true; // keep the message channel open for the async sendResponse
});

// Toolbar icon toggles Inspect Mode in the active tab's content script.
chrome.action.onClicked.addListener((tab) => {
  if (tab.id == null) return;
  chrome.tabs.sendMessage(tab.id, { kind: "capture.inspect.toggle" });
});

// Keyboard shortcuts (manifest.json's "commands") trigger a full-page
// auto-scroll capture in the active tab — vertical or horizontal, each
// with a "reverse" (end-to-start) variant.
const FULL_PAGE_COMMANDS = {
  "capture-full-page": { axis: "vertical", reverse: false },
  "capture-full-page-horizontal": { axis: "horizontal", reverse: false },
  "capture-full-page-reverse": { axis: "vertical", reverse: true },
  "capture-full-page-horizontal-reverse": { axis: "horizontal", reverse: true }
};

// Manual (user-paced) scrolling capture: the user scrolls at their own
// pace and explicitly snaps each tile, rather than the fixed-step
// auto-scroll loop above — useful for pages where the settle delay isn't
// enough (slow-loading content, heavy animation) or where auto-scroll's
// uniform step misses a specific point the user wants included. Each of
// the three commands is just forwarded to the content script, which owns
// the actual tile-collection state.
const MANUAL_FULL_PAGE_COMMANDS = {
  "capture-full-page-manual-start": "capture.fullpage.manual.start",
  "capture-full-page-manual-snap": "capture.fullpage.manual.snap",
  "capture-full-page-manual-finish": "capture.fullpage.manual.finish"
};

chrome.commands.onCommand.addListener((command) => {
  const spec = FULL_PAGE_COMMANDS[command];
  if (spec) {
    chrome.tabs.query({ active: true, currentWindow: true }, (tabs) => {
      if (tabs[0] && tabs[0].id != null) {
        chrome.tabs.sendMessage(tabs[0].id, { kind: "capture.fullpage.trigger", axis: spec.axis, reverse: spec.reverse });
      }
    });
    return;
  }

  const manualKind = MANUAL_FULL_PAGE_COMMANDS[command];
  if (manualKind) {
    chrome.tabs.query({ active: true, currentWindow: true }, (tabs) => {
      if (tabs[0] && tabs[0].id != null) {
        chrome.tabs.sendMessage(tabs[0].id, { kind: manualKind });
      }
    });
    return;
  }

  if (command === "capture-accessibility-audit") {
    chrome.tabs.query({ active: true, currentWindow: true }, (tabs) => {
      if (tabs[0] && tabs[0].id != null) {
        chrome.tabs.sendMessage(tabs[0].id, { kind: "capture.accessibility.audit.trigger" });
      }
    });
  }

  if (command === "capture-ecommerce-audit") {
    chrome.tabs.query({ active: true, currentWindow: true }, (tabs) => {
      if (tabs[0] && tabs[0].id != null) {
        chrome.tabs.sendMessage(tabs[0].id, { kind: "capture.ecommerce.audit.trigger" });
      }
    });
  }
});
