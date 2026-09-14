// Real DOM-level verification of src/accessibility-audit.js using jsdom
// -- builds real DOM trees and checks this code's actual output against
// them, not just "it parses." Same category of limitation as
// content.test.js: this is real DOM/CSSOM behavior, not a live Chrome
// extension runtime (no interactive browser session available here).
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

function loadAudit(html) {
  const dom = new JSDOM(html, { url: "https://example.com/page", runScripts: "outside-only" });
  const window = dom.window;
  const source = fs.readFileSync(path.join(__dirname, "..", "src", "accessibility-audit.js"), "utf8");
  const vmContext = dom.getInternalVMContext();
  vm.createContext(vmContext);
  vm.runInContext(source, vmContext);
  return window.__captureAccessibilityAudit;
}

// --- Heading outline ---
{
  const audit = loadAudit(`
    <html><body>
      <h1>Page Title</h1>
      <h2>Section</h2>
      <h4>Skipped level 3</h4>
      <div role="heading" aria-level="2">ARIA heading</div>
    </body></html>
  `);
  const result = audit.headingOutline();
  check("headingOutline finds every real and ARIA heading", result.headings.length === 4);
  check("headingOutline reads the correct level for a real <h1>", result.headings[0].level === 1);
  check("headingOutline reads aria-level for a role=heading element", result.headings[3].level === 2);
  check("headingOutline flags a skipped level (H2 -> H4)", result.issues.some((i) => i.type === "skippedLevel"));
  check("headingOutline does not flag missingH1 when an H1 exists", !result.issues.some((i) => i.type === "missingH1"));
}

{
  const audit = loadAudit(`<html><body><h2>No H1 here</h2></body></html>`);
  const result = audit.headingOutline();
  check("headingOutline flags missingH1 when there is no H1", result.issues.some((i) => i.type === "missingH1"));
}

// --- Landmarks ---
{
  const audit = loadAudit(`
    <html><body>
      <header>Top</header>
      <nav>Nav</nav>
      <main>Main</main>
      <aside>Side</aside>
      <footer>Bottom</footer>
      <div role="search">Search</div>
    </body></html>
  `);
  const result = audit.landmarks();
  const types = result.map((l) => l.type);
  check("landmarks detects header/nav/main/aside/footer via implicit HTML5 elements", ["banner", "navigation", "main", "complementary", "contentinfo"].every((t) => types.includes(t)));
  check("landmarks detects an explicit role=search landmark", types.includes("search"));
}

// --- Image audit ---
{
  const audit = loadAudit(`
    <html><body>
      <img src="a.png" alt="A real description">
      <img src="b.png" alt="">
      <img src="c.png">
      <img src="d.png" role="presentation">
      <a href="/x"><img src="e.png" alt="Go to X"></a>
    </body></html>
  `);
  const result = audit.imageAudit();
  check("imageAudit finds all 5 images", result.length === 5);
  check("imageAudit does not flag an image with real alt text", !result[0].missingAlt);
  check("imageAudit flags an image with empty alt", result[1].missingAlt);
  check("imageAudit flags an image with no alt attribute at all", result[2].missingAlt);
  check("imageAudit does not flag a role=presentation image even with no alt", !result[3].missingAlt && result[3].isPresentation);
  check("imageAudit detects an image inside a link", result[4].isInsideLink);
}

// --- Link audit ---
{
  const audit = loadAudit(`
    <html><body>
      <a href="/pricing">View pricing plans</a>
      <a href="/x">Click here</a>
      <a href="/y"></a>
      <a href="/z" aria-label="Download the report">Read more</a>
    </body></html>
  `);
  const result = audit.linkAudit();
  check("linkAudit finds all 4 links", result.length === 4);
  check("linkAudit does not flag a link with a real descriptive name", !result[0].isVague && !result[0].isEmpty);
  check("linkAudit flags a vague 'Click here' link", result[1].isVague);
  check("linkAudit flags a link with no accessible name at all", result[2].isEmpty);
  check("linkAudit prefers aria-label over vague visible text", result[3].accessibleName === "Download the report" && !result[3].isVague);
}

// --- Form audit ---
{
  const audit = loadAudit(`
    <html><body>
      <form>
        <label for="email">Email</label>
        <input id="email" type="email" required>
        <label>Name <input type="text" id="name"></label>
        <input type="text" id="unlabeled">
        <input type="text" aria-label="Search query">
        <input type="hidden" id="csrf" value="x">
      </form>
    </body></html>
  `);
  const result = audit.formAudit();
  check("formAudit excludes hidden fields entirely", result.every((f) => f.type !== "hidden"));
  check("formAudit finds the 4 visible fields", result.length === 4);
  check("formAudit recognizes a label[for] association", result[0].isLabeled);
  check("formAudit marks the label[for] field as required", result[0].isRequired);
  check("formAudit recognizes a wrapping <label> association", result[1].isLabeled);
  check("formAudit flags a field with no label at all", !result[2].isLabeled);
  check("formAudit recognizes an aria-label association", result[3].isLabeled);
}

// --- Target size audit ---
// jsdom has no real layout engine, so getBoundingClientRect() always
// returns all-zero by default — stub it per-element (keyed by a data
// attribute) to give this audit real, controlled sizes to check against,
// the same way content.test.js stubs scrollY/innerHeight for its own
// layout-dependent logic.
{
  const dom = new JSDOM(`
    <html><body>
      <button id="big">Big enough</button>
      <button id="small">Too small</button>
      <a href="/x" id="empty">Not laid out</a>
    </body></html>
  `, { url: "https://example.com/page", runScripts: "outside-only" });
  const window = dom.window;
  const sizes = { big: { width: 30, height: 30 }, small: { width: 16, height: 16 }, empty: { width: 0, height: 0 } };
  window.HTMLElement.prototype.getBoundingClientRect = function () {
    const size = sizes[this.id] || { width: 0, height: 0 };
    return { x: 0, y: 0, top: 0, left: 0, right: size.width, bottom: size.height, width: size.width, height: size.height };
  };
  const source = fs.readFileSync(path.join(__dirname, "..", "src", "accessibility-audit.js"), "utf8");
  const vmContext = dom.getInternalVMContext();
  vm.createContext(vmContext);
  vm.runInContext(source, vmContext);
  const result = window.__captureAccessibilityAudit.targetSizeAudit(window.document, 24);

  check("targetSizeAudit finds the 2 laid-out controls (excludes the zero-size one)", result.length === 2);
  check("targetSizeAudit does not flag a control at/above the threshold", !result.find((r) => r.width === 30).belowThreshold);
  check("targetSizeAudit flags a control below the threshold", result.find((r) => r.width === 16).belowThreshold);
}

// --- duplicateIdAudit (spec §2.19 "Automated WCAG audit" — WCAG 4.1.1) ---
{
  const audit = loadAudit(`
    <html><body>
      <div id="a">First</div>
      <div id="a">Duplicate</div>
      <div id="a">Another duplicate</div>
      <div id="b">Unique</div>
    </body></html>
  `);
  const result = audit.duplicateIdAudit();
  check("duplicateIdAudit finds exactly the one real duplicated id", result.length === 1 && result[0].id === "a");
  check("duplicateIdAudit reports the real total count for the duplicated id", result[0].count === 3);
}

{
  const audit = loadAudit(`<html><body><div id="a">Only one</div></body></html>`);
  check("duplicateIdAudit finds no duplicates when every real id is unique", audit.duplicateIdAudit().length === 0);
}

// --- htmlLangAudit (spec §2.19 "Automated WCAG audit" — WCAG 3.1.1) ---
{
  const audit = loadAudit(`<html lang="en"><body></body></html>`);
  const result = audit.htmlLangAudit();
  check("htmlLangAudit reads a real authored lang attribute and reports it as present", result.lang === "en" && result.isMissing === false);
}

{
  const audit = loadAudit(`<html><body></body></html>`);
  check("htmlLangAudit reports isMissing:true when there's genuinely no lang attribute", audit.htmlLangAudit().isMissing === true);
}

{
  const audit = loadAudit(`<html lang=""><body></body></html>`);
  check("htmlLangAudit reports isMissing:true for a real empty lang attribute, not just an absent one", audit.htmlLangAudit().isMissing === true);
}

// --- positiveTabIndexAudit (spec §2.19 "Automated WCAG audit" — WCAG 2.4.3 anti-pattern) ---
{
  const audit = loadAudit(`
    <html><body>
      <button tabindex="5">Reordered ahead</button>
      <a href="/x" tabindex="0">Normal</a>
      <div tabindex="-1">Programmatically focusable only</div>
    </body></html>
  `);
  const result = audit.positiveTabIndexAudit();
  check("positiveTabIndexAudit flags exactly the real positive tabindex element", result.length === 1 && result[0].tabIndex === 5);
}

{
  const audit = loadAudit(`<html><body><a href="/x" tabindex="0">Fine</a><div tabindex="-1">Fine too</div></body></html>`);
  check("positiveTabIndexAudit does not flag real tabindex 0 or negative values", audit.positiveTabIndexAudit().length === 0);
}

// --- runAccessibilityAudit bundles everything ---
{
  const audit = loadAudit(`<html><body><h1>Title</h1><main>Content</main></body></html>`);
  const result = audit.runAccessibilityAudit();
  check(
    "runAccessibilityAudit returns all nine categories",
    ["headingOutline", "landmarks", "images", "links", "forms", "targetSizes", "duplicateIds", "htmlLang", "positiveTabIndexElements"].every((key) => key in result)
  );
}

console.log(`=== ${failureCount === 0 ? "ALL CHECKS PASSED" : `${failureCount} CHECK(S) FAILED`} ===`);
process.exit(failureCount === 0 ? 0 : 1);
