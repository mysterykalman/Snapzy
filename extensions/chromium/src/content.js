// Capture browser bridge — content script: Inspect Mode overlay, element
// evidence, and locator strategy.
//
// Ported from the original Capture app's extensions/chromium (owned by
// the user; see docs/REFERENCE_PROVENANCE.md).
//
// NOT YET LOADED INTO A REAL CHROME SESSION in this environment — written
// against documented DOM/CSSOM APIs and verified at the DOM/data level
// via tests/content.test.js, but needs manual load-and-click QA in an
// actual browser before shipping.
//
// Content scripts never talk to the native host directly — every message
// here goes through `chrome.runtime.sendMessage` to the background
// service worker, which alone owns the native-messaging port.
//
// Payload shape matches `ElementLocator`/`AuditFinding.elementAnchor`
// (Snapzy/Services/Inspection/ElementLocator.swift) field-for-field, so
// the app can decode it directly: `locator.candidates` (each
// `{strategy, value}`, one of 8 priority-ordered strategy names),
// `viewport`, `rect`, plus loosely-typed `*JSON` forensic categories as
// actual JSON strings.

(() => {
  const OVERLAY_ID = "__capture-inspect-overlay__";
  let inspectModeActive = false;
  let overlayElement = null;
  let currentHoverTarget = null;
  // A fresh id per navigation/injection — if the page navigates, session
  // state must be re-established deliberately.
  const tabSessionId = (globalThis.crypto && globalThis.crypto.randomUUID) ? globalThis.crypto.randomUUID() : `${Date.now()}`;

  function ensureOverlay() {
    if (overlayElement) return overlayElement;
    const el = document.createElement("div");
    el.id = OVERLAY_ID;
    el.style.position = "fixed";
    el.style.zIndex = "2147483647"; // stay above page content
    el.style.pointerEvents = "none";
    el.style.border = "2px solid #4F6BFF";
    el.style.background = "rgba(79, 107, 255, 0.12)";
    el.style.borderRadius = "2px";
    el.style.transition = "all 60ms ease-out";
    el.style.display = "none";
    document.documentElement.appendChild(el);
    overlayElement = el;
    return el;
  }

  function showOverlay(target) {
    const overlay = ensureOverlay();
    const rect = target.getBoundingClientRect();
    overlay.style.left = `${rect.left}px`;
    overlay.style.top = `${rect.top}px`;
    overlay.style.width = `${rect.width}px`;
    overlay.style.height = `${rect.height}px`;
    overlay.style.display = "block";
  }

  function hideOverlay() {
    if (overlayElement) overlayElement.style.display = "none";
  }

  function accessibleName(element) {
    return (
      element.getAttribute("aria-label") ||
      (element.labels && element.labels[0] && element.labels[0].textContent.trim()) ||
      element.getAttribute("alt") ||
      element.getAttribute("title") ||
      (element.textContent ? element.textContent.trim().slice(0, 80) : "") ||
      null
    );
  }

  function absoluteDOMPath(element) {
    const path = [];
    let node = element;
    while (node && node.nodeType === Node.ELEMENT_NODE) {
      let segment = node.tagName.toLowerCase();
      const parent = node.parentElement;
      if (parent) {
        const siblings = Array.from(parent.children).filter((sibling) => sibling.tagName === node.tagName);
        if (siblings.length > 1) segment += `:nth-of-type(${siblings.indexOf(node) + 1})`;
      }
      path.unshift(segment);
      node = parent;
    }
    return path.join(" > ");
  }

  /// A standard absolute XPath (1-indexed among same-tag siblings, same
  /// convention every browser's own "Copy XPath" DevTools feature uses)
  /// — kept separate from `absoluteDOMPath` (a CSS-selector-shaped
  /// fallback locator with a different purpose: re-finding the element
  /// later) since this is purely for display/copy, evaluable with
  /// `document.evaluate` if a caller wants to.
  function absoluteXPath(element) {
    const path = [];
    let node = element;
    while (node && node.nodeType === Node.ELEMENT_NODE) {
      let segment = node.tagName.toLowerCase();
      const parent = node.parentElement;
      if (parent) {
        const siblings = Array.from(parent.children).filter((sibling) => sibling.tagName === node.tagName);
        if (siblings.length > 1) segment += `[${siblings.indexOf(node) + 1}]`;
      }
      path.unshift(segment);
      node = parent;
    }
    return "/" + path.join("/");
  }

  /// Builds every locator candidate we can, in `ElementLocator.Strategy
  /// .priorityOrder`'s order — the Mac side (`ElementLocator.primary`)
  /// picks the strongest one that's actually present, so it's fine for
  /// most elements to only produce a handful of these.
  function buildLocatorCandidates(element) {
    const candidates = [];

    const testId = element.getAttribute("data-testid") || element.getAttribute("data-test-id");
    if (testId) candidates.push({ strategy: "dataTestID", value: `[data-testid="${testId}"]` });

    if (element.id) candidates.push({ strategy: "stableID", value: `#${element.id}` });

    const role = element.getAttribute("role") || element.getAttribute("type") || null;
    const name = accessibleName(element);
    if (role && name) candidates.push({ strategy: "roleAndAccessibleName", value: `${role}:"${name}"` });

    const nameAttr = element.getAttribute("name");
    if (nameAttr) candidates.push({ strategy: "semanticAttributes", value: `${element.tagName.toLowerCase()}[name="${nameAttr}"]` });

    if (element.classList.length > 0) {
      candidates.push({
        strategy: "classAndStructure",
        value: `${element.tagName.toLowerCase()}.${Array.from(element.classList).join(".")}`
      });
    }

    const text = element.textContent ? element.textContent.trim() : "";
    if (text) candidates.push({ strategy: "textFingerprint", value: text.slice(0, 80) });

    const parent = element.parentElement;
    if (parent) {
      candidates.push({
        strategy: "ancestryFingerprint",
        value: `${parent.tagName.toLowerCase()} > ${element.tagName.toLowerCase()}`
      });
    }

    // Always present — the guaranteed fallback candidate.
    candidates.push({ strategy: "absoluteDOMPath", value: absoluteDOMPath(element) });

    return candidates;
  }

  function collectEvidence(element) {
    const rect = element.getBoundingClientRect();
    const style = window.getComputedStyle(element);
    return {
      url: location.href,
      title: document.title,
      viewport: {
        width: window.innerWidth,
        height: window.innerHeight,
        devicePixelRatio: window.devicePixelRatio || 1,
        scrollX: window.scrollX,
        scrollY: window.scrollY
      },
      locator: { candidates: buildLocatorCandidates(element) },
      xpath: absoluteXPath(element),
      rect: { x: rect.left, y: rect.top, width: rect.width, height: rect.height },
      // The *authored* CSSOM values `getComputedStyle` reports, not the
      // actually-rendered font face (a separate, network/glyph-dependent
      // "actual rendered font" detection, out of scope for a synchronous
      // evidence snapshot like this one).
      typographyJSON: JSON.stringify({
        fontFamily: style.fontFamily,
        fontSize: style.fontSize,
        fontWeight: style.fontWeight,
        fontStyle: style.fontStyle,
        lineHeight: style.lineHeight,
        letterSpacing: style.letterSpacing,
        wordSpacing: style.wordSpacing,
        textTransform: style.textTransform,
        textDecoration: style.textDecoration,
        color: style.color,
        // Variable-font axes / OpenType feature detection — provided by
        // a future typography-features-inspector.js content script when
        // loaded alongside this one (guarded the same way accessibilityJSON
        // is, since content.test.js's own narrower jsdom harness loads
        // content.js in isolation).
        variableFontAxes: typeof window.__captureTypographyFeaturesInspector !== "undefined"
          ? window.__captureTypographyFeaturesInspector.variableFontAxes(element)
          : {},
        openTypeFeatures: typeof window.__captureTypographyFeaturesInspector !== "undefined"
          ? window.__captureTypographyFeaturesInspector.openTypeFeatures(element)
          : {}
      }),
      // Gradients/shadows/filters are reported as their raw CSS value
      // rather than hand-parsed into angle/stops/x/y/blur components;
      // that structured parsing is real future work, not faked here.
      appearanceJSON: JSON.stringify({
        color: style.color,
        backgroundColor: style.backgroundColor,
        backgroundImage: style.backgroundImage,
        borderRadius: style.borderRadius,
        boxShadow: style.boxShadow,
        filter: style.filter,
        opacity: style.opacity
      }),
      // `borderTopWidth`/etc. are real, separately-queryable CSSOM
      // longhands (unlike the individual `border-*-radius` corner
      // longhands, which several browser engines including jsdom's CSSOM
      // implementation don't decompose from the `border-radius`
      // shorthand — that shorthand is reported once, in `appearanceJSON`,
      // instead).
      boxModelJSON: JSON.stringify({
        padding: style.padding,
        margin: style.margin,
        border: style.border,
        borderTopWidth: style.borderTopWidth,
        borderTopStyle: style.borderTopStyle,
        borderTopColor: style.borderTopColor,
        borderRightWidth: style.borderRightWidth,
        borderRightStyle: style.borderRightStyle,
        borderRightColor: style.borderRightColor,
        borderBottomWidth: style.borderBottomWidth,
        borderBottomStyle: style.borderBottomStyle,
        borderBottomColor: style.borderBottomColor,
        borderLeftWidth: style.borderLeftWidth,
        borderLeftStyle: style.borderLeftStyle,
        borderLeftColor: style.borderLeftColor
      }),
      // Accessible name/role/description/focusable/tab index/ARIA
      // attributes/hidden-inert/disabled state — provided by a future
      // separate element-accessibility-inspector.js content script.
      // Guarded rather than assumed present: this file is also loaded
      // standalone (without that script) by content.test.js's own jsdom
      // harness, so accessibilityJSON is simply absent there rather than
      // throwing.
      accessibilityJSON: typeof window.__captureElementAccessibilityInspector !== "undefined"
        ? JSON.stringify(window.__captureElementAccessibilityInspector.inspectElementAccessibility(element))
        : null
    };
  }

  function handleMouseOver(event) {
    if (!inspectModeActive) return;
    const target = event.target;
    if (target === overlayElement || target === currentHoverTarget) return;
    currentHoverTarget = target;
    showOverlay(target);
  }

  /// Plain click while Inspect Mode is on: report evidence
  /// (inspect.element.result). Alt/Option-click: one-click element
  /// capture — ask the background worker to capture the visible tab and
  /// crop to this element (capture.element.result). Two interactions on
  /// the same click handler rather than a second mode, since both need
  /// an element under the pointer and differ only in what happens after.
  function handleClick(event) {
    if (!inspectModeActive) return;
    event.preventDefault();
    event.stopPropagation();
    const target = event.target;
    const evidence = collectEvidence(target);

    if (event.altKey) {
      chrome.runtime.sendMessage({
        kind: "capture.bridge.request",
        type: "capture.element.result",
        tabSessionId,
        payload: { locator: evidence.locator, rect: evidence.rect, devicePixelRatio: evidence.viewport.devicePixelRatio }
      });
    } else {
      chrome.runtime.sendMessage({
        kind: "capture.bridge.request",
        type: "inspect.element.result",
        tabSessionId,
        payload: evidence
      });
    }
  }

  function setInspectMode(active) {
    inspectModeActive = active;
    if (!active) {
      hideOverlay();
      currentHoverTarget = null;
    }
  }

  document.addEventListener("mouseover", handleMouseOver, true);
  document.addEventListener("click", handleClick, true);

  /// Waits for the browser to actually repaint after a scroll — two
  /// animation frames (one for the scroll to apply, one for the
  /// resulting paint to land) plus a short settle delay for any
  /// scroll-triggered lazy-loading/animations, before the next tile is
  /// captured. A real, working first version of "stable browser capture
  /// controls," not a substitute for genuinely detecting paint/layout
  /// stability.
  function waitForRepaint() {
    return new Promise((resolve) => {
      requestAnimationFrame(() => requestAnimationFrame(() => setTimeout(resolve, 120)));
    });
  }

  function captureTile() {
    return new Promise((resolve) => {
      chrome.runtime.sendMessage({ kind: "capture.bridge.capture_tile" }, resolve);
    });
  }

  /// Automatic vertical/horizontal/reverse full-page browser capture:
  /// scrolls along `axis` in slightly-overlapping steps (90% of one
  /// viewport extent, so a fractional-pixel/rounding mismatch between
  /// steps can never leave a gap), snapping one tile per step, then
  /// restores the original scroll position and hands every tile to the
  /// background worker as one `capture.fullpage.result` message
  /// (Mac-side stitching happens separately). `reverse` starts at the
  /// end of the page/row and works backward toward the start, rather
  /// than the normal start-to-end order.
  async function captureFullPage(axis, reverse) {
    const isHorizontal = axis === "horizontal";
    const originalScroll = isHorizontal ? window.scrollX : window.scrollY;
    const viewportExtent = isHorizontal ? window.innerWidth : window.innerHeight;
    const scrollStep = Math.max(1, Math.floor(viewportExtent * 0.9));
    const tiles = [];

    const scrollTo = (value) => window.scrollTo(isHorizontal ? value : window.scrollX, isHorizontal ? window.scrollY : value);
    const currentScroll = () => (isHorizontal ? window.scrollX : window.scrollY);

    // `scrollTo` clamps to the page's real scrollable range in both real
    // browsers and this suite's jsdom simulation, so asking for an
    // enormous value is a reliable way to find the true end of the
    // page/row without needing `scrollWidth`/`scrollHeight` (which can be
    // thrown off by fixed/sticky layout in ways `scrollTo`'s own clamping
    // isn't).
    scrollTo(reverse ? Number.MAX_SAFE_INTEGER : 0);
    await waitForRepaint();

    let previousScroll = -1;
    while (currentScroll() !== previousScroll) {
      previousScroll = currentScroll();
      const tile = await captureTile();
      if (!tile || !tile.imageDataBase64) break;
      tiles.push(
        isHorizontal
          ? { scrollX: currentScroll(), imageDataBase64: tile.imageDataBase64 }
          : { scrollY: currentScroll(), imageDataBase64: tile.imageDataBase64 }
      );
      scrollTo(currentScroll() + (reverse ? -scrollStep : scrollStep));
      await waitForRepaint();
    }

    scrollTo(originalScroll);

    if (tiles.length === 0) return;
    chrome.runtime.sendMessage({
      kind: "capture.bridge.request",
      type: "capture.fullpage.result",
      tabSessionId,
      payload: { devicePixelRatio: window.devicePixelRatio || 1, axis: isHorizontal ? "horizontal" : "vertical", tiles }
    });
  }

  /// Manual (user-paced) scrolling capture: unlike `captureFullPage`'s
  /// fixed-step auto-scroll loop, here the *user* scrolls at their own
  /// pace and explicitly snaps each tile — useful when a page needs more
  /// settle time than the fixed delay allows, or the user wants to
  /// deliberately choose which sections become tiles. State lives here
  /// in the content script (the only place that can see the real scroll
  /// position at snap time); the axis is inferred from whichever
  /// direction has actually moved by the time capture finishes,
  /// defaulting to vertical if the page never scrolled at all (e.g. a
  /// single-tile manual capture).
  let manualCapture = null; // { tiles: [{scrollX, scrollY, imageDataBase64}], startScrollX, startScrollY }

  function manualCaptureStart() {
    manualCapture = { tiles: [], startScrollX: window.scrollX, startScrollY: window.scrollY };
  }

  async function manualCaptureSnap() {
    if (!manualCapture) return;
    const tile = await captureTile();
    if (!tile || !tile.imageDataBase64) return;
    manualCapture.tiles.push({ scrollX: window.scrollX, scrollY: window.scrollY, imageDataBase64: tile.imageDataBase64 });
  }

  function manualCaptureFinish() {
    if (!manualCapture || manualCapture.tiles.length === 0) {
      manualCapture = null;
      return;
    }
    const { tiles, startScrollX, startScrollY } = manualCapture;
    // Whichever axis actually varied across the snapped tiles is the one
    // being captured; a purely single-tile (or no-scroll) capture is
    // reported as vertical, matching captureFullPage's default.
    const scrollXVaries = tiles.some((tile) => tile.scrollX !== startScrollX);
    const scrollYVaries = tiles.some((tile) => tile.scrollY !== startScrollY);
    const isHorizontal = scrollXVaries && !scrollYVaries;
    const payloadTiles = tiles.map((tile) =>
      isHorizontal
        ? { scrollX: tile.scrollX, imageDataBase64: tile.imageDataBase64 }
        : { scrollY: tile.scrollY, imageDataBase64: tile.imageDataBase64 }
    );
    chrome.runtime.sendMessage({
      kind: "capture.bridge.request",
      type: "capture.fullpage.result",
      tabSessionId,
      payload: { devicePixelRatio: window.devicePixelRatio || 1, axis: isHorizontal ? "horizontal" : "vertical", tiles: payloadTiles }
    });
    manualCapture = null;
  }

  chrome.runtime.onMessage.addListener((message) => {
    if (message && message.kind === "capture.inspect.toggle") {
      setInspectMode(!inspectModeActive);
    } else if (message && message.kind === "capture.fullpage.trigger") {
      captureFullPage(message.axis === "horizontal" ? "horizontal" : "vertical", message.reverse === true);
    } else if (message && message.kind === "capture.fullpage.manual.start") {
      manualCaptureStart();
    } else if (message && message.kind === "capture.fullpage.manual.snap") {
      manualCaptureSnap();
    } else if (message && message.kind === "capture.fullpage.manual.finish") {
      manualCaptureFinish();
    }
  });
})();
