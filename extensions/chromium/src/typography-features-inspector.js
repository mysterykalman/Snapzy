// Capture browser bridge — variable-font-axis / OpenType-feature inspector
// content script.
//
// Ported from the original Capture app's extensions/chromium (owned by
// the user; see docs/REFERENCE_PROVENANCE.md).
//
// Both are read directly from real computed style (`font-variation-
// settings`/`font-feature-settings`) rather than needing actual font-file
// parsing: the CSS values authored/computed for an element already name
// exactly which variable-font axes and OpenType features are *requested*
// for it, which is the practical, DOM-only half of "does this element use
// variable-font axes / OpenType features" a caller actually wants --
// whether the loaded font file *supports* a requested axis/feature at all
// needs real font-file introspection (parsing its `fvar`/`GSUB` tables),
// which is a separate, larger feature not attempted here.
//
// NOT YET LOADED INTO A REAL CHROME SESSION in this environment --
// verified with real jsdom CSSOM-level tests
// (tests/typography-features-inspector.test.js).
(() => {
  /// Parses a CSS `font-variation-settings`/`font-feature-settings`
  /// value's comma-separated `'tag' value` entries into a plain
  /// `{tag: value}` map -- the same shape for both properties, since they
  /// share this exact grammar (a quoted 4-character tag followed by a
  /// number). Returns `{}` for `"normal"` (both properties' real initial
  /// value) or an empty/absent value, rather than `null` -- "no
  /// axes/features requested" is itself a meaningful, common answer, not
  /// an error.
  function parseTagValuePairs(cssValue) {
    if (!cssValue || cssValue === "normal") return {};
    const result = {};
    const pattern = /["']([a-zA-Z0-9]{4})["']\s+(-?[\d.]+)/g;
    let match;
    while ((match = pattern.exec(cssValue)) !== null) {
      result[match[1]] = Number(match[2]);
    }
    return result;
  }

  /// Variable-font axes -- e.g. `{wght: 650, wdth: 100}` for an element
  /// authored with `font-variation-settings: 'wght' 650, 'wdth' 100`.
  function variableFontAxes(element, win = window) {
    return parseTagValuePairs(win.getComputedStyle(element).fontVariationSettings);
  }

  /// OpenType feature detection -- e.g. `{liga: 1, smcp: 1}` for
  /// `font-feature-settings: 'liga' 1, 'smcp' 1`. A feature's real
  /// human-readable name (e.g. `smcp` -> "Small Capitals") is left to a
  /// caller/UI layer -- a small lookup table of OpenType's own registered
  /// 4-character feature tags, not attempted here to keep this file
  /// focused on real CSSOM extraction rather than reproducing a
  /// standards-body reference table.
  function openTypeFeatures(element, win = window) {
    return parseTagValuePairs(win.getComputedStyle(element).fontFeatureSettings);
  }

  /// A page-wide font inventory table (font | elements | weights | sizes).
  /// Walks every element with its own real direct text content (not just
  /// any element -- an empty `<div>` wrapping other elements shouldn't
  /// count as "using" a font) and groups them by their real computed
  /// font/size/weight/line-height combination, reporting each group's
  /// real element count -- a "source" column (local/remote/Google
  /// Fonts/etc.) needs real resource-timing/network data this DOM-only
  /// function doesn't have, so it's left out here rather than guessed.
  /// Sorted by count descending, the most-used combinations first -- the
  /// natural reading order for "what fonts does this page actually use."
  function fontInventory(root = document, win = window) {
    const elements = Array.from(root.querySelectorAll("*")).filter((el) =>
      Array.from(el.childNodes).some((node) => node.nodeType === 3 && node.textContent.trim().length > 0)
    );

    const groups = new Map();
    for (const el of elements) {
      const style = win.getComputedStyle(el);
      const key = `${style.fontFamily}|${style.fontSize}|${style.fontWeight}|${style.lineHeight}`;
      if (!groups.has(key)) {
        groups.set(key, {
          fontFamily: style.fontFamily,
          fontSize: style.fontSize,
          fontWeight: style.fontWeight,
          lineHeight: style.lineHeight,
          elementCount: 0
        });
      }
      groups.get(key).elementCount += 1;
    }

    return Array.from(groups.values()).sort((a, b) => b.elementCount - a.elementCount);
  }

  /// Type scale extraction: cluster font usage into likely roles and flag
  /// one-off outliers. A thin, honest layer over `fontInventory`'s own
  /// real grouping -- each already-computed group *is* a likely "role"
  /// (heading/body/caption/etc., though this doesn't presume to label
  /// them), and "flag one-off outliers" is literally "which of these real
  /// groups have an unusually low real element count" -- `outlierThreshold`
  /// (default 1, a literal "one-off") is the count at or below which a
  /// group counts as an outlier, deliberately a simple absolute threshold
  /// rather than a guessed statistical one.
  function typeScaleOutliers(inventory, outlierThreshold = 1) {
    return inventory.filter((entry) => entry.elementCount <= outlierThreshold);
  }

  /// Copy formats: CSS declaration, Tailwind-like config, SCSS token,
  /// JSON token, plain-language spec, Markdown table. Pure string
  /// rendering of an already-known typography snapshot
  /// (`{fontFamily, fontSize, fontWeight, lineHeight}` -- real values a
  /// caller has already read via `getComputedStyle`).
  function exportTypographyToken(typo, format, tokenName = "text") {
    switch (format) {
      case "cssDeclaration":
        return `font-family: ${typo.fontFamily};\nfont-size: ${typo.fontSize};\nfont-weight: ${typo.fontWeight};\nline-height: ${typo.lineHeight};`;
      case "tailwind":
        return `module.exports = {\n  theme: {\n    extend: {\n      fontSize: {\n        '${tokenName}': ['${typo.fontSize}', { lineHeight: '${typo.lineHeight}', fontWeight: '${typo.fontWeight}' }]\n      }\n    }\n  }\n};`;
      case "scss":
        return `$${tokenName}-font-family: ${typo.fontFamily};\n$${tokenName}-font-size: ${typo.fontSize};\n$${tokenName}-font-weight: ${typo.fontWeight};\n$${tokenName}-line-height: ${typo.lineHeight};`;
      case "json":
        return JSON.stringify({ [tokenName]: typo }, null, 2);
      case "plainLanguage":
        return `${typo.fontFamily}, ${typo.fontSize} at ${typo.lineHeight} line-height, weight ${typo.fontWeight}`;
      case "markdown":
        return `| Property | Value |\n|---|---|\n| Font Family | ${typo.fontFamily} |\n| Font Size | ${typo.fontSize} |\n| Font Weight | ${typo.fontWeight} |\n| Line Height | ${typo.lineHeight} |`;
      default:
        return null;
    }
  }

  const api = { parseTagValuePairs, variableFontAxes, openTypeFeatures, fontInventory, typeScaleOutliers, exportTypographyToken };

  if (typeof module !== "undefined" && module.exports) {
    module.exports = api;
  } else {
    window.__captureTypographyFeaturesInspector = api;
  }
})();
