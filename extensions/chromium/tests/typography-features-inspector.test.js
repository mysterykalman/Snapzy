// Real DOM/CSSOM-level verification of src/typography-features-inspector.js
// using jsdom.
//
// Ported from the original Capture app's extensions/chromium (owned by
// the user; see docs/REFERENCE_PROVENANCE.md).

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

function load(html) {
  const dom = new JSDOM(html, { url: "https://example.com", pretendToBeVisual: true, runScripts: "outside-only" });
  const window = dom.window;
  const source = fs.readFileSync(path.join(__dirname, "..", "src", "typography-features-inspector.js"), "utf8");
  const vmContext = dom.getInternalVMContext();
  vm.createContext(vmContext);
  vm.runInContext(source, vmContext);
  return { window, api: window.__captureTypographyFeaturesInspector };
}

// --- parseTagValuePairs ---
{
  const { api } = load(`<html><body></body></html>`);
  check("parseTagValuePairs returns {} for 'normal'", Object.keys(api.parseTagValuePairs("normal")).length === 0);
  check("parseTagValuePairs returns {} for an empty/falsy value", Object.keys(api.parseTagValuePairs("")).length === 0 && Object.keys(api.parseTagValuePairs(null)).length === 0);
}

{
  const { api } = load(`<html><body></body></html>`);
  const parsed = api.parseTagValuePairs("'wght' 650, 'wdth' 100");
  check("parseTagValuePairs extracts every real tag/value pair", parsed.wght === 650 && parsed.wdth === 100);
}

{
  const { api } = load(`<html><body></body></html>`);
  const parsed = api.parseTagValuePairs("\"liga\" 1, \"smcp\" 1");
  check("parseTagValuePairs handles real double-quoted tags too", parsed.liga === 1 && parsed.smcp === 1);
}

// --- variableFontAxes ---
{
  const { window, api } = load(`<div id="a" style="font-variation-settings: 'wght' 650, 'wdth' 100;">x</div>`);
  const axes = api.variableFontAxes(window.document.getElementById("a"), window);
  check("variableFontAxes reads real authored variable-font axes from computed style", axes.wght === 650 && axes.wdth === 100);
}

{
  const { window, api } = load(`<div id="a">x</div>`);
  const axes = api.variableFontAxes(window.document.getElementById("a"), window);
  check("variableFontAxes returns {} for an element with no real variable-font axes authored", Object.keys(axes).length === 0);
}

// --- openTypeFeatures ---
{
  const { window, api } = load(`<div id="a" style="font-feature-settings: 'liga' 1, 'smcp' 1;">x</div>`);
  const features = api.openTypeFeatures(window.document.getElementById("a"), window);
  check("openTypeFeatures reads real authored OpenType features from computed style", features.liga === 1 && features.smcp === 1);
}

{
  const { window, api } = load(`<div id="a">x</div>`);
  const features = api.openTypeFeatures(window.document.getElementById("a"), window);
  check("openTypeFeatures returns {} for an element with no real OpenType features authored", Object.keys(features).length === 0);
}

{
  // Real disambiguation: an element can author variable-font axes and
  // OpenType features independently -- one function's output must not
  // bleed into the other's.
  const { window, api } = load(`<div id="a" style="font-variation-settings: 'wght' 700; font-feature-settings: 'onum' 1;">x</div>`);
  const element = window.document.getElementById("a");
  const axes = api.variableFontAxes(element, window);
  const features = api.openTypeFeatures(element, window);
  check("variableFontAxes and openTypeFeatures independently report only their own real property", axes.wght === 700 && axes.onum === undefined && features.onum === 1 && features.wght === undefined);
}

// --- fontInventory + typeScaleOutliers (type scale extraction) ---
{
  const { window, api } = load(`
    <html><body>
      <h1 style="font-family: Georgia; font-size: 48px; font-weight: 700; line-height: 56px;">Heading one</h1>
      <h1 style="font-family: Georgia; font-size: 48px; font-weight: 700; line-height: 56px;">Heading one again</h1>
      <p style="font-family: Georgia; font-size: 16px; font-weight: 400; line-height: 24px;">Body text one</p>
      <p style="font-family: Georgia; font-size: 16px; font-weight: 400; line-height: 24px;">Body text two</p>
      <p style="font-family: Georgia; font-size: 16px; font-weight: 400; line-height: 24px;">Body text three</p>
      <span style="font-family: Georgia; font-size: 22px; font-weight: 600; line-height: 30px;">A real one-off outlier</span>
    </body></html>
  `);
  const inventory = api.fontInventory(window.document, window);

  check("fontInventory finds exactly the 3 real distinct font/size/weight/line-height combinations", inventory.length === 3);
  check("fontInventory sorts by real element count descending", inventory[0].elementCount === 3 && inventory[0].fontSize === "16px");
  check("fontInventory correctly groups the two identical real h1 elements together", inventory.some((entry) => entry.fontSize === "48px" && entry.elementCount === 2));
  check("fontInventory's total element count across all groups matches the real 6 text-bearing elements", inventory.reduce((sum, e) => sum + e.elementCount, 0) === 6);

  const outliers = api.typeScaleOutliers(inventory);
  check("typeScaleOutliers flags exactly the real one-off (count === 1) group", outliers.length === 1 && outliers[0].fontSize === "22px");
}

{
  const { window, api } = load(`<html><body><div class="wrapper"><em>Wrapper's own direct child is only whitespace/nested text, not counted itself</em></div></body></html>`);
  const inventory = api.fontInventory(window.document, window);
  check("fontInventory does not separately count a wrapper element whose only real content is a nested child element", inventory.length === 1 && inventory[0].elementCount === 1);
}

{
  const { window, api } = load(`<html><body><p style="font-size: 16px;">Only one real usage</p></body></html>`);
  const inventory = api.fontInventory(window.document, window);
  check("fontInventory handles a page with only one real font usage without crashing", inventory.length === 1 && inventory[0].elementCount === 1);
  check("typeScaleOutliers flags the sole real group as an outlier when it's the only usage", api.typeScaleOutliers(inventory).length === 1);
}

{
  const { window, api } = load(`<html><body></body></html>`);
  check("fontInventory returns an empty real array for a page with no text at all", api.fontInventory(window.document, window).length === 0);
}

// --- exportTypographyToken (copy formats) ---
{
  const { api } = load(`<html><body></body></html>`);
  const typo = { fontFamily: "Georgia, serif", fontSize: "32px", fontWeight: "700", lineHeight: "40px" };

  const cssDeclaration = api.exportTypographyToken(typo, "cssDeclaration");
  check("exportTypographyToken(cssDeclaration) includes every real property as a real CSS declaration", cssDeclaration.includes("font-family: Georgia, serif;") && cssDeclaration.includes("font-size: 32px;") && cssDeclaration.includes("line-height: 40px;"));

  const tailwind = api.exportTypographyToken(typo, "tailwind", "heading-lg");
  check("exportTypographyToken(tailwind) embeds the real token name and every real property value", tailwind.includes("'heading-lg'") && tailwind.includes("'32px'") && tailwind.includes("lineHeight: '40px'"));

  const scss = api.exportTypographyToken(typo, "scss", "heading-lg");
  check("exportTypographyToken(scss) produces real per-property SCSS variables using the real token name", scss.includes("$heading-lg-font-size: 32px;") && scss.includes("$heading-lg-font-weight: 700;"));

  const json = JSON.parse(api.exportTypographyToken(typo, "json", "heading-lg"));
  check("exportTypographyToken(json) produces valid real JSON nested under the real token name", json["heading-lg"].fontSize === "32px" && json["heading-lg"].fontWeight === "700");

  const plainLanguage = api.exportTypographyToken(typo, "plainLanguage");
  check("exportTypographyToken(plainLanguage) reads as a real human-readable sentence containing every real value", plainLanguage.includes("Georgia, serif") && plainLanguage.includes("32px") && plainLanguage.includes("40px") && plainLanguage.includes("700"));

  const markdown = api.exportTypographyToken(typo, "markdown");
  check("exportTypographyToken(markdown) produces a real Markdown table row per property", markdown.includes("| Font Size | 32px |") && markdown.includes("| Font Weight | 700 |"));

  check("exportTypographyToken returns null for an unrecognized format rather than crashing", api.exportTypographyToken(typo, "yaml") === null);
}

console.log(`=== ${failureCount === 0 ? "ALL CHECKS PASSED" : `${failureCount} CHECK(S) FAILED`} ===`);
process.exit(failureCount === 0 ? 0 : 1);
