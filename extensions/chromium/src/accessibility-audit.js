// Capture browser bridge — accessibility audit content script (heading
// outline, landmarks, images, links, forms, plus a small explicit WCAG
// rule set).
//
// Ported from the original Capture app's extensions/chromium (owned by
// the user; see docs/REFERENCE_PROVENANCE.md). Its output JSON shape is
// the exact contract Snapzy/Services/Accessibility/AccessibilityAuditMapper.swift
// decodes — this file was ported specifically to lock that contract in.
//
// A separate file from content.js (both load as content scripts per
// manifest.json) rather than folding this into content.js's existing
// Inspect Mode logic — this is a distinct on-demand analysis pass over
// the whole page, not part of the hover/click element-evidence flow.
//
// NOT YET LOADED INTO A REAL CHROME SESSION in this environment —
// verified instead with real jsdom DOM-level tests
// (tests/accessibility-audit.test.js) that build real DOM trees and check
// this code's actual output against them, not just "it parses."
//
// Every function here is a pure DOM -> data-structure query with no side
// effects (no message-sending, no mutation) so it's testable in complete
// isolation; `runAccessibilityAudit()` at the bottom is the one entry
// point that bundles all of them together and is what a
// `capture.accessibility.audit.trigger` message (wired up the same way
// `capture.fullpage.trigger` is in content.js) actually calls.

(() => {
  /// Real headings (`<h1>`-`<h6>`) plus ARIA `role="heading"` elements
  /// (using `aria-level`, defaulting to 2 per the ARIA spec's own default
  /// for an explicit heading role with no level given). `issues` flags
  /// the two most common, unambiguous hierarchy problems: no H1 present
  /// at all, and a level that skips one or more steps deeper than the
  /// previous heading (e.g. H2 straight to H4) — both real, well-defined
  /// problems; more subjective heading-structure judgment calls are left
  /// to a human reviewer rather than guessed at here.
  function headingOutline(root = document) {
    const nodes = Array.from(root.querySelectorAll("h1, h2, h3, h4, h5, h6, [role='heading']"));
    const headings = nodes.map((node) => {
      const tagLevel = /^H[1-6]$/.test(node.tagName) ? Number(node.tagName[1]) : null;
      const ariaLevel = node.getAttribute("aria-level");
      const level = ariaLevel ? Number(ariaLevel) : tagLevel ?? 2;
      return { level, text: (node.textContent || "").trim(), tagName: node.tagName.toLowerCase() };
    });

    const issues = [];
    if (!headings.some((h) => h.level === 1)) {
      issues.push({ type: "missingH1", message: "No H1 heading found on the page." });
    }
    for (let i = 1; i < headings.length; i++) {
      const gap = headings[i].level - headings[i - 1].level;
      if (gap > 1) {
        issues.push({
          type: "skippedLevel",
          message: `Heading level jumps from ${headings[i - 1].level} to ${headings[i].level} ("${headings[i].text.slice(0, 40)}").`
        });
      }
    }

    return { headings, issues };
  }

  /// Matches by explicit ARIA role first, then the equivalent implicit
  /// HTML5 landmark element (per the HTML-ARIA mapping spec), so a page
  /// using either convention (or both) is detected correctly.
  const LANDMARK_ROLES = {
    header: ["banner"],
    nav: ["navigation"],
    main: ["main"],
    aside: ["complementary"],
    footer: ["contentinfo"],
    form: ["form"],
    search: ["search"]
  };

  function landmarks(root = document) {
    const found = [];
    for (const [tagName, roles] of Object.entries(LANDMARK_ROLES)) {
      const roleSelector = roles.map((role) => `[role="${role}"]`).join(", ");
      const elements = new Set([
        ...root.querySelectorAll(tagName),
        ...root.querySelectorAll(roleSelector)
      ]);
      for (const element of elements) {
        found.push({ type: roles[0], tagName: element.tagName.toLowerCase() });
      }
    }
    return found;
  }

  /// `role="presentation"`/`role="none"` images are intentionally
  /// decorative — a missing/empty alt there is correct, not a violation,
  /// so they're reported separately rather than flagged.
  function imageAudit(root = document) {
    const images = Array.from(root.querySelectorAll("img"));
    return images.map((img) => {
      const role = img.getAttribute("role");
      const isPresentation = role === "presentation" || role === "none";
      const alt = img.getAttribute("alt");
      const hasAlt = alt !== null && alt.trim().length > 0;
      const isInsideLink = !!img.closest("a[href]");
      return {
        src: img.getAttribute("src") || "",
        isPresentation,
        hasAlt,
        isInsideLink,
        // A decorative image correctly has no alt text; a real content
        // image with no alt text is the actual accessibility problem.
        missingAlt: !isPresentation && !hasAlt
      };
    });
  }

  /// A small, deliberately conservative list of common vague labels —
  /// this is meant to catch the obvious, common case ("click here", "read
  /// more" with no other context), not to be an exhaustive linguistic
  /// judgment of every possible vague phrasing.
  const VAGUE_LINK_TEXTS = new Set(["click here", "here", "read more", "more", "link", "learn more"]);

  function linkAudit(root = document) {
    const links = Array.from(root.querySelectorAll("a[href]"));
    return links.map((link) => {
      const accessibleName = (link.getAttribute("aria-label") || link.textContent || "").trim();
      return {
        href: link.getAttribute("href") || "",
        accessibleName,
        isEmpty: accessibleName.length === 0,
        isVague: VAGUE_LINK_TEXTS.has(accessibleName.toLowerCase())
      };
    });
  }

  /// A field counts as labeled if it has: a `<label for="...">` pointing
  /// at it, an ancestor `<label>` wrapping it (the other valid HTML
  /// labeling pattern), `aria-label`, or `aria-labelledby`. `hidden`/
  /// `type="hidden"` fields are excluded — they're never visible to a
  /// user, so an unlabeled hidden field isn't an accessibility problem.
  function formAudit(root = document) {
    const fields = Array.from(root.querySelectorAll("input, select, textarea")).filter(
      (field) => field.getAttribute("type") !== "hidden"
    );
    return fields.map((field) => {
      const id = field.getAttribute("id");
      const hasForLabel = !!(id && root.querySelector(`label[for="${id}"]`));
      const hasWrappingLabel = !!field.closest("label");
      const hasAriaLabel = !!field.getAttribute("aria-label");
      const hasAriaLabelledby = !!field.getAttribute("aria-labelledby");
      const isLabeled = hasForLabel || hasWrappingLabel || hasAriaLabel || hasAriaLabelledby;
      return {
        tagName: field.tagName.toLowerCase(),
        type: field.getAttribute("type") || null,
        isLabeled,
        isRequired: field.hasAttribute("required") || field.getAttribute("aria-required") === "true"
      };
    });
  }

  /// WCAG 2.2 §2.5.8's Target Size (Minimum) criterion: an interactive
  /// control's clickable/tappable area should be at least 24×24 CSS
  /// pixels (the spec-recommended default; the real WCAG criterion has
  /// additional exemptions — e.g. inline text links, or a control with
  /// enough spacing to its neighbors — deliberately not modeled here, so
  /// this is a simple first pass flagging raw size only, meant to guide
  /// review rather than be a final compliance verdict). Zero-size
  /// elements (`display: none`, detached, not yet laid out) are excluded
  /// — they're not visible target-size violations, just not visible.
  function targetSizeAudit(root = document, threshold = 24) {
    const controls = Array.from(root.querySelectorAll(
      "a[href], button, input, select, textarea, [role='button'], [role='link'], [role='checkbox'], [role='radio']"
    ));
    return controls
      .map((control) => {
        const rect = control.getBoundingClientRect();
        return { tagName: control.tagName.toLowerCase(), width: rect.width, height: rect.height };
      })
      .filter((entry) => entry.width > 0 && entry.height > 0)
      .map((entry) => ({ ...entry, belowThreshold: entry.width < threshold || entry.height < threshold }));
  }

  /// Rather than bundling a third-party engine (a real licensing/bundle-
  /// size decision), this implements a small, explicit set of the
  /// simplest genuinely-automatable WCAG success criteria as this
  /// project's own real rules. WCAG 4.1.1 (duplicate ids break `for`/
  /// `aria-labelledby`/fragment-link references — a real parsing
  /// failure, not a style nitpick); WCAG 3.1.1 (a missing/empty
  /// `<html lang>` means assistive tech can't correctly choose a
  /// pronunciation/braille table for the page's actual language); and
  /// the WCAG 2.4.3 anti-pattern of a positive `tabindex` (it silently
  /// reorders the tab sequence ahead of the page's natural DOM order — a
  /// `tabindex="0"` or negative value is fine and not flagged).
  function duplicateIdAudit(root = document) {
    const counts = new Map();
    for (const el of root.querySelectorAll("[id]")) {
      const id = el.getAttribute("id");
      if (!id) continue;
      counts.set(id, (counts.get(id) || 0) + 1);
    }
    return Array.from(counts.entries())
      .filter(([, count]) => count > 1)
      .map(([id, count]) => ({ id, count }));
  }

  function htmlLangAudit(root = document) {
    const lang = root.documentElement ? root.documentElement.getAttribute("lang") : null;
    return { lang, isMissing: !lang || lang.trim().length === 0 };
  }

  function positiveTabIndexAudit(root = document) {
    return Array.from(root.querySelectorAll("[tabindex]"))
      .map((el) => ({ tagName: el.tagName.toLowerCase(), tabIndex: parseInt(el.getAttribute("tabindex"), 10) }))
      .filter((entry) => Number.isFinite(entry.tabIndex) && entry.tabIndex > 0);
  }

  function runAccessibilityAudit(root = document) {
    return {
      headingOutline: headingOutline(root),
      landmarks: landmarks(root),
      images: imageAudit(root),
      links: linkAudit(root),
      forms: formAudit(root),
      targetSizes: targetSizeAudit(root),
      duplicateIds: duplicateIdAudit(root),
      htmlLang: htmlLangAudit(root),
      positiveTabIndexElements: positiveTabIndexAudit(root)
    };
  }

  /// Runs the audit and relays it to the background worker as
  /// `accessibility.audit.result` — the whole audit result travels as one
  /// opaque JSON string (`auditJSON`) rather than the extension and the
  /// app both having to agree on a fully-typed IPC schema for every
  /// individual finding type; `AccessibilityAuditMapper` decodes it
  /// app-side.
  function runAndReportAccessibilityAudit() {
    const result = runAccessibilityAudit();
    if (typeof chrome === "undefined" || !chrome.runtime || !chrome.runtime.sendMessage) return;
    const tabSessionId = (globalThis.crypto && globalThis.crypto.randomUUID) ? globalThis.crypto.randomUUID() : `${Date.now()}`;
    chrome.runtime.sendMessage({
      kind: "capture.bridge.request",
      type: "accessibility.audit.result",
      tabSessionId,
      payload: {
        tabSessionId,
        url: location.href,
        auditJSON: JSON.stringify(result),
        viewportWidth: window.innerWidth,
        viewportHeight: window.innerHeight
      }
    });
  }

  if (typeof chrome !== "undefined" && chrome.runtime && chrome.runtime.onMessage) {
    chrome.runtime.onMessage.addListener((message) => {
      if (message && message.kind === "capture.accessibility.audit.trigger") {
        runAndReportAccessibilityAudit();
      }
    });
  }

  const api = {
    headingOutline, landmarks, imageAudit, linkAudit, formAudit, targetSizeAudit,
    duplicateIdAudit, htmlLangAudit, positiveTabIndexAudit,
    runAccessibilityAudit, runAndReportAccessibilityAudit
  };

  // Exposed for the jsdom test harness (which loads this file's source
  // directly into a `vm` context rather than through a real `<script>`
  // tag) and for a future message-handler wiring, without polluting the
  // page's own global scope with these names.
  if (typeof module !== "undefined" && module.exports) {
    module.exports = api;
  } else {
    // `window`, not `globalThis` — a real content-script's `window` is
    // the page's own window either way, but jsdom's `vm.runInContext`
    // test harness (see accessibility-audit.test.js) only reliably
    // reflects an assignment back onto the object actually passed to
    // `vm.createContext` (jsdom's `window`), not `globalThis`, which is a
    // separate proxy inside that context.
    window.__captureAccessibilityAudit = api;
  }
})();
