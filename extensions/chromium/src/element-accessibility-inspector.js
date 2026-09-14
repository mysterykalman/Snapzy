// Capture browser bridge — per-element accessibility inspection (accessible
// name, role, description, focusable?, tab index, ARIA attributes,
// hidden/inert state, disabled state). Distinct from accessibility-audit.js,
// which runs a whole-page pass over headings/landmarks/images/links/forms;
// this is the single-element inspector meant to sit alongside content.js's
// own Inspect Mode hover/click evidence for one selected node.
//
// Ported from the original Capture app's extensions/chromium (owned by
// the user; see docs/REFERENCE_PROVENANCE.md).
//
// NOT YET LOADED INTO A REAL CHROME SESSION in this environment --
// verified with real jsdom DOM-level tests
// (tests/element-accessibility-inspector.test.js).
//
// The accessible-name computation here is a deliberately practical subset
// of the W3C accname algorithm (https://www.w3.org/TR/accname-1.2/),
// covering the common real-world cases an inspector needs to show a user,
// not a full spec-compliant implementation (which also recurses into
// aria-owns, handles CSS generated content, table captions, etc. -- out
// of scope for a DOM-only content script): aria-labelledby > aria-label >
// associated <label> (for form controls) > alt text (for <img>) > title
// attribute > visible text content (for naturally-labeled elements like
// links/buttons) > empty string.
(() => {
  const IMPLICIT_ROLES = {
    a: (el) => (el.hasAttribute("href") ? "link" : "generic"),
    button: () => "button",
    input: (el) => {
      const type = (el.getAttribute("type") || "text").toLowerCase();
      const map = {
        checkbox: "checkbox", radio: "radio", button: "button", submit: "button",
        reset: "button", range: "slider", search: "searchbox", email: "textbox",
        tel: "textbox", url: "textbox", number: "spinbutton", text: "textbox"
      };
      return map[type] || "textbox";
    },
    select: (el) => (el.multiple ? "listbox" : "combobox"),
    textarea: () => "textbox",
    img: (el) => (el.getAttribute("alt") === "" ? "presentation" : "img"),
    h1: () => "heading", h2: () => "heading", h3: () => "heading",
    h4: () => "heading", h5: () => "heading", h6: () => "heading",
    nav: () => "navigation", main: () => "main", header: () => "banner",
    footer: () => "contentinfo", aside: () => "complementary", form: () => "form",
    ul: () => "list", ol: () => "list", li: () => "listitem",
    table: () => "table"
  };

  function implicitRole(element) {
    const tagName = element.tagName.toLowerCase();
    const resolver = IMPLICIT_ROLES[tagName];
    return resolver ? resolver(element) : "generic";
  }

  /// Explicit `role="..."` wins over the implicit HTML semantics, per
  /// ARIA's own precedence rules.
  function role(element) {
    return element.getAttribute("role") || implicitRole(element);
  }

  function textOf(el) {
    return (el.textContent || "").replace(/\s+/g, " ").trim();
  }

  function labelledByText(element, root) {
    const ids = (element.getAttribute("aria-labelledby") || "").trim();
    if (!ids) return null;
    const parts = ids.split(/\s+/).map((id) => {
      const referenced = root.getElementById ? root.getElementById(id) : null;
      return referenced ? textOf(referenced) : "";
    }).filter((text) => text.length > 0);
    return parts.length > 0 ? parts.join(" ") : null;
  }

  function associatedLabelText(element, root) {
    const id = element.getAttribute("id");
    if (id) {
      const forLabel = root.querySelector(`label[for="${id}"]`);
      if (forLabel) return textOf(forLabel);
    }
    const wrapping = element.closest ? element.closest("label") : null;
    return wrapping ? textOf(wrapping) : null;
  }

  /// The accessible name for one element -- see the algorithm-subset note
  /// at the top of this file for the precedence order and its deliberate
  /// scope limits.
  function accessibleName(element, root = element.ownerDocument || document) {
    const labelledBy = labelledByText(element, root);
    if (labelledBy) return labelledBy;

    const ariaLabel = element.getAttribute("aria-label");
    if (ariaLabel && ariaLabel.trim().length > 0) return ariaLabel.trim();

    const tagName = element.tagName.toLowerCase();
    if (["input", "select", "textarea"].includes(tagName)) {
      const labelText = associatedLabelText(element, root);
      if (labelText) return labelText;
    }

    if (tagName === "img") {
      const alt = element.getAttribute("alt");
      if (alt !== null) return alt.trim();
    }

    const title = element.getAttribute("title");
    if (["a", "button"].includes(tagName) || element.getAttribute("role") === "button") {
      const visibleText = textOf(element);
      if (visibleText) return visibleText;
    }
    if (title && title.trim().length > 0) return title.trim();

    const fallbackText = textOf(element);
    return fallbackText;
  }

  /// `aria-describedby`'s referenced text -- the other half of ARIA's
  /// name/description pair (kept separate from `accessibleName` since a
  /// description supplements rather than replaces the name).
  function description(element, root = element.ownerDocument || document) {
    const ids = (element.getAttribute("aria-describedby") || "").trim();
    if (!ids) return null;
    const parts = ids.split(/\s+/).map((id) => {
      const referenced = root.getElementById ? root.getElementById(id) : null;
      return referenced ? textOf(referenced) : "";
    }).filter((text) => text.length > 0);
    return parts.length > 0 ? parts.join(" ") : null;
  }

  const NATURALLY_FOCUSABLE_TAGS = new Set(["a", "button", "input", "select", "textarea", "summary", "iframe"]);

  /// Natively focusable elements (with the usual exception that an
  /// `<a>`/area without `href` is not), any element with a real
  /// non-negative `tabindex`, `contenteditable`, minus anything disabled
  /// or hidden from the accessibility tree -- an element the user truly
  /// cannot Tab to, not just "the tag is normally interactive."
  function isFocusable(element) {
    if (isDisabled(element)) return false;
    if (isHiddenOrInert(element)) return false;
    const tabIndexAttr = element.getAttribute("tabindex");
    if (tabIndexAttr !== null) {
      const parsed = Number(tabIndexAttr);
      return !Number.isNaN(parsed) && parsed >= 0;
    }
    const tagName = element.tagName.toLowerCase();
    if (tagName === "a" || tagName === "area") return element.hasAttribute("href");
    if (element.getAttribute("contenteditable") === "true") return true;
    return NATURALLY_FOCUSABLE_TAGS.has(tagName);
  }

  /// The real effective tab index, following the platform's own default:
  /// naturally-focusable elements default to 0 (not "no tabindex"),
  /// everything else defaults to -1 (not programmatically reachable via
  /// Tab) unless overridden.
  function tabIndex(element) {
    const attr = element.getAttribute("tabindex");
    if (attr !== null) {
      const parsed = Number(attr);
      return Number.isNaN(parsed) ? -1 : parsed;
    }
    const tagName = element.tagName.toLowerCase();
    if (tagName === "a" || tagName === "area") return element.hasAttribute("href") ? 0 : -1;
    return NATURALLY_FOCUSABLE_TAGS.has(tagName) ? 0 : -1;
  }

  /// `hidden` attribute, `aria-hidden`, `inert` (attribute or the live
  /// IDL property, since jsdom and real browsers alike expose `.inert`),
  /// or an ancestor with any of those, since a node inside a hidden/inert
  /// subtree is itself hidden/inert even with none of its own attributes
  /// set.
  function isHiddenOrInert(element) {
    let node = element;
    while (node && node.nodeType === 1) {
      if (node.hasAttribute("hidden")) return true;
      if (node.getAttribute("aria-hidden") === "true") return true;
      if (node.hasAttribute("inert") || node.inert === true) return true;
      node = node.parentElement;
    }
    return false;
  }

  /// The native `disabled` IDL/attribute, ARIA's `aria-disabled="true"`
  /// equivalent for custom widgets, or an ancestor `<fieldset disabled>`
  /// (which natively disables every descendant form control per the HTML
  /// spec, even though only the fieldset itself carries the attribute).
  function isDisabled(element) {
    if (element.hasAttribute("disabled") || element.disabled === true) return true;
    if (element.getAttribute("aria-disabled") === "true") return true;
    const fieldset = element.closest ? element.closest("fieldset[disabled]") : null;
    return !!fieldset;
  }

  /// Every `aria-*` attribute actually present on the element, as a plain
  /// key/value map (raw, unresolved -- a caller wanting e.g.
  /// `aria-labelledby`'s referenced text uses `accessibleName`/
  /// `description` above instead).
  function ariaAttributes(element) {
    const result = {};
    for (const attr of Array.from(element.attributes || [])) {
      if (attr.name.startsWith("aria-")) result[attr.name] = attr.value;
    }
    return result;
  }

  /// Bundles every field above for one element -- the shape a caller
  /// (content.js's Inspect Mode, or a future accessibility side panel)
  /// actually wants for a per-element inspection card.
  function inspectElementAccessibility(element, root = element.ownerDocument || document) {
    return {
      role: role(element),
      accessibleName: accessibleName(element, root),
      description: description(element, root),
      focusable: isFocusable(element),
      tabIndex: tabIndex(element),
      hidden: isHiddenOrInert(element),
      disabled: isDisabled(element),
      ariaAttributes: ariaAttributes(element)
    };
  }

  const api = {
    role, accessibleName, description, isFocusable, tabIndex,
    isHiddenOrInert, isDisabled, ariaAttributes, inspectElementAccessibility
  };

  if (typeof module !== "undefined" && module.exports) {
    module.exports = api;
  } else {
    window.__captureElementAccessibilityInspector = api;
  }
})();
