// Real DOM-level verification of src/element-accessibility-inspector.js
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

function loadInspector(html) {
  const dom = new JSDOM(html, { url: "https://example.com/page", runScripts: "outside-only" });
  const window = dom.window;
  const source = fs.readFileSync(path.join(__dirname, "..", "src", "element-accessibility-inspector.js"), "utf8");
  const vmContext = dom.getInternalVMContext();
  vm.createContext(vmContext);
  vm.runInContext(source, vmContext);
  return { window, api: window.__captureElementAccessibilityInspector };
}

{
  const { window, api } = loadInspector(`
    <label for="email">Email address</label>
    <input id="email" type="email">
  `);
  const input = window.document.getElementById("email");
  check("accessibleName finds the <label for> text for a form control", api.accessibleName(input) === "Email address");
  check("role infers textbox for an <input type=email>", api.role(input) === "textbox");
}

{
  const { window, api } = loadInspector(`<button aria-label="Close dialog">X</button>`);
  const button = window.document.querySelector("button");
  check("aria-label wins over visible text for accessibleName", api.accessibleName(button) === "Close dialog");
  check("role is button for a <button>", api.role(button) === "button");
}

{
  const { window, api } = loadInspector(`
    <span id="name1">Save</span>
    <span id="name2">changes</span>
    <button aria-labelledby="name1 name2">ignored text</button>
  `);
  const button = window.document.querySelector("button");
  check("aria-labelledby joins multiple referenced elements' text", api.accessibleName(button) === "Save changes");
}

{
  const { window, api } = loadInspector(`<img src="logo.png" alt="Acme logo">`);
  const img = window.document.querySelector("img");
  check("accessibleName uses alt text for an <img>", api.accessibleName(img) === "Acme logo");
  check("role is img for a real content image", api.role(img) === "img");
}

{
  const { window, api } = loadInspector(`<img src="spacer.gif" alt="">`);
  const img = window.document.querySelector("img");
  check("role is presentation for an empty-alt image", api.role(img) === "presentation");
}

{
  const { window, api } = loadInspector(`<a href="/pricing">Pricing</a>`);
  const link = window.document.querySelector("a");
  check("role is link for an <a href>", api.role(link) === "link");
  check("a real link is focusable", api.isFocusable(link) === true);
  check("a real link has a default tabIndex of 0", api.tabIndex(link) === 0);
}

{
  const { window, api } = loadInspector(`<a>Not a real link</a>`);
  const link = window.document.querySelector("a");
  check("an <a> with no href is not focusable", api.isFocusable(link) === false);
  check("an <a> with no href has a default tabIndex of -1", api.tabIndex(link) === -1);
}

{
  const { window, api } = loadInspector(`<div tabindex="3">Custom widget</div>`);
  const div = window.document.querySelector("div");
  check("an explicit positive tabindex is respected", api.tabIndex(div) === 3);
  check("an explicit tabindex makes a plain div focusable", api.isFocusable(div) === true);
}

{
  const { window, api } = loadInspector(`<button disabled>Submit</button>`);
  const button = window.document.querySelector("button");
  check("a disabled button reports isDisabled true", api.isDisabled(button) === true);
  check("a disabled button is not focusable", api.isFocusable(button) === false);
}

{
  const { window, api } = loadInspector(`<fieldset disabled><input id="f1"></fieldset>`);
  const input = window.document.querySelector("input");
  check("a control inside a disabled fieldset is disabled", api.isDisabled(input) === true);
}

{
  const { window, api } = loadInspector(`<div hidden><button id="b1">Hidden button</button></div>`);
  const button = window.document.getElementById("b1");
  check("a button inside a hidden ancestor reports isHiddenOrInert true", api.isHiddenOrInert(button) === true);
  check("a hidden button is not focusable", api.isFocusable(button) === false);
}

{
  const { window, api } = loadInspector(`<div aria-hidden="true"><a href="/x" id="a1">link</a></div>`);
  const link = window.document.getElementById("a1");
  check("aria-hidden on an ancestor makes a descendant isHiddenOrInert true", api.isHiddenOrInert(link) === true);
}

{
  const { window, api } = loadInspector(`
    <span id="desc">Enter your full legal name</span>
    <input id="name" aria-describedby="desc">
  `);
  const input = window.document.getElementById("name");
  check("description resolves aria-describedby's referenced text", api.description(input) === "Enter your full legal name");
}

{
  const { window, api } = loadInspector(`<input id="plain">`);
  const input = window.document.getElementById("plain");
  check("description is null when there is no aria-describedby", api.description(input) === null);
}

{
  const { window, api } = loadInspector(`<div role="button" aria-pressed="true" aria-label="Toggle">T</div>`);
  const div = window.document.querySelector("div");
  const attrs = api.ariaAttributes(div);
  check("ariaAttributes captures every aria-* attribute present", attrs["aria-pressed"] === "true" && attrs["aria-label"] === "Toggle");
  check("explicit role='button' overrides the implicit generic div role", api.role(div) === "button");
}

{
  const { window, api } = loadInspector(`
    <label for="q">Search</label>
    <input id="q" type="search" aria-describedby="hint" required>
    <span id="hint">Press enter to search</span>
  `);
  const input = window.document.getElementById("q");
  const bundle = api.inspectElementAccessibility(input);
  check(
    "inspectElementAccessibility bundles name/role/description/focusable/tabIndex together",
    bundle.accessibleName === "Search" &&
    bundle.role === "searchbox" &&
    bundle.description === "Press enter to search" &&
    bundle.focusable === true &&
    bundle.tabIndex === 0 &&
    bundle.disabled === false &&
    bundle.hidden === false
  );
}

if (failureCount > 0) {
  console.error(`\n${failureCount} check(s) FAILED`);
  process.exit(1);
} else {
  console.log("\nAll element-accessibility-inspector checks passed.");
}
