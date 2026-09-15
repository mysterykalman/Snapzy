// Real DOM-level verification of src/ecommerce-intelligence.js using
// jsdom -- builds real DOM trees (including real
// <script type="application/ld+json"> blocks) and checks this code's
// actual output against them. Same category of limitation as
// content.test.js/accessibility-audit.test.js: real DOM/CSSOM behavior,
// not a live Chrome extension runtime.
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

function load(html, windowSetup) {
  const dom = new JSDOM(html, { url: "https://example.com/product/widget", runScripts: "outside-only" });
  const window = dom.window;
  if (windowSetup) windowSetup(window);
  const source = fs.readFileSync(path.join(__dirname, "..", "src", "ecommerce-intelligence.js"), "utf8");
  const vmContext = dom.getInternalVMContext();
  vm.createContext(vmContext);
  vm.runInContext(source, vmContext);
  return window.__captureEcommerceIntelligence;
}

// --- Technology fingerprinting ---
{
  const api = load(`
    <html><head>
      <script src="https://cdn.shopify.com/s/files/theme.js"></script>
      <script src="https://www.googletagmanager.com/gtag/js?id=G-XXXX"></script>
    </head><body></body></html>
  `, (window) => {
    window.gtag = function () {};
    window.dataLayer = [];
  });
  const result = api.technologyFingerprint();
  const shopify = result.find((r) => r.technology === "Shopify");
  const ga4 = result.find((r) => r.technology === "Google Analytics (GA4)");

  check("technologyFingerprint detects Shopify from a cdn.shopify.com script", !!shopify);
  check("Shopify detection cites the actual matching script as a signal", shopify.signals.some((s) => s.includes("cdn.shopify.com")));
  check("technologyFingerprint detects GA4 from multiple independent signals with high confidence", ga4.confidence === "high" && ga4.signals.length >= 2);
  check("technologyFingerprint does not report an undetected technology (WooCommerce)", !result.some((r) => r.technology === "WooCommerce"));
}

{
  const api = load(`<html><head></head><body class="woocommerce"></body></html>`);
  const result = api.technologyFingerprint();
  const woo = result.find((r) => r.technology === "WooCommerce");
  check("technologyFingerprint detects WooCommerce from a body class with medium confidence (one signal)", woo && woo.confidence === "medium");
}

// --- Search-tool detection ---
{
  const api = load(`
    <html><head><script src="https://cdn.jsdelivr.net/algoliasearch.js"></script></head><body></body></html>
  `, (window) => { window.algoliasearch = function () {}; });
  const result = api.technologyFingerprint();
  const algolia = result.find((r) => r.technology === "Algolia");
  check("technologyFingerprint detects Algolia with high confidence from two real signals (global + script src)", algolia && algolia.category === "search" && algolia.confidence === "high");
}

{
  const api = load(`<html><head><script src="https://js.klevu.com/klevu-search.js"></script></head><body></body></html>`);
  const result = api.technologyFingerprint();
  const klevu = result.find((r) => r.technology === "Klevu");
  check("technologyFingerprint detects Klevu from a real script src", klevu && klevu.category === "search" && klevu.signals.some((s) => s.includes("klevu.com")));
}

{
  const api = load(`<html><head><script src="https://cdn.searchspring.net/snap.js"></script></head><body></body></html>`);
  const result = api.technologyFingerprint();
  const searchspring = result.find((r) => r.technology === "Searchspring");
  check("technologyFingerprint detects Searchspring from a real script src", searchspring && searchspring.category === "search");
}

// --- Additional storefront-platform detection ---
{
  const api = load(`<html><head></head><body></body></html>`, (window) => { window.BCData = {}; });
  const result = api.technologyFingerprint();
  const bigcommerce = result.find((r) => r.technology === "BigCommerce");
  check("technologyFingerprint detects BigCommerce from window.BCData", bigcommerce && bigcommerce.category === "platform");
}

{
  const api = load(`<html><head><script src="https://www.example.com/on/demandware.store/Sites-example-Site/en_US/Home"></script></head><body></body></html>`);
  const result = api.technologyFingerprint();
  const sfcc = result.find((r) => r.technology === "Salesforce Commerce Cloud");
  check("technologyFingerprint detects Salesforce Commerce Cloud from a real demandware.store URL path convention", sfcc && sfcc.signals.some((s) => s.includes("Demandware")));
}

{
  const api = load(`<html><head></head><body></body></html>`, (window) => { window.dw = { ajax: {} }; });
  const result = api.technologyFingerprint();
  const sfcc = result.find((r) => r.technology === "Salesforce Commerce Cloud");
  check("technologyFingerprint detects Salesforce Commerce Cloud from window.dw.ajax", !!sfcc);
}

{
  const api = load(`
    <html><head><script src="https://example.myshopify.com/cdn/shop/t/1/assets/hydrogen-chunk.js"></script></head>
    <body><div id="__remixContext"></div></body></html>
  `);
  const result = api.technologyFingerprint();
  const hydrogen = result.find((r) => r.technology === "Shopify Hydrogen (headless)");
  check("technologyFingerprint detects Shopify Hydrogen from a Remix hydration marker plus an explicit Hydrogen script reference", !!hydrogen);
}

{
  // A plain Remix app with no Hydrogen reference at all must NOT be
  // misidentified as Shopify Hydrogen -- Remix alone is too general a
  // signal (used by many non-Shopify sites).
  const api = load(`<html><head></head><body><div id="__remixContext"></div></body></html>`);
  const result = api.technologyFingerprint();
  check("technologyFingerprint does not flag a plain Remix app (no Hydrogen reference) as Shopify Hydrogen", !result.some((r) => r.technology === "Shopify Hydrogen (headless)"));
}

// --- CRO component classification ---
{
  const api = load(`
    <html><body>
      <div id="announce-bar" class="announcement-bar" role="region">Free shipping over $50</div>
      <div id="mini-cart" class="cart-drawer" aria-hidden="true">Your cart is empty</div>
      <button id="sticky-atc" class="add-to-cart-sticky" style="position: sticky;">Add to Cart</button>
      <details id="faq-item"><summary>Shipping info</summary><p>Ships in 2 days</p></details>
      <div id="disclosure" aria-expanded="false" aria-controls="panel1">More details</div>
      <div id="reviews-section" class="product-reviews" itemtype="https://schema.org/AggregateRating"></div>
      <div id="pdp-gallery" class="product-media-gallery">
        <img src="a.jpg"><img src="b.jpg"><img src="c.jpg">
      </div>
      <div id="plain">Nothing special here</div>
    </body></html>
  `);
  const result = api.croComponentClassification();

  const announcementBar = result.find((r) => r.component === "announcementBar" && r.selector === "#announce-bar");
  check("croComponentClassification detects the announcement bar with high confidence (class + role signals)", announcementBar && announcementBar.confidence === "high");

  const cartDrawer = result.find((r) => r.component === "cartDrawer" && r.selector === "#mini-cart");
  check("croComponentClassification detects the cart drawer with high confidence (naming convention + aria-hidden signals)", cartDrawer && cartDrawer.confidence === "high");

  const stickyATC = result.find((r) => r.component === "stickyAddToCart" && r.selector === "#sticky-atc");
  check("croComponentClassification detects the sticky Add to Cart button from real authored position:sticky plus an ATC identifier", !!stickyATC);
  check("croComponentClassification's sticky-ATC signal cites the real authored position value", stickyATC.signals.some((s) => s.includes("position:sticky")));

  const accordionDetails = result.find((r) => r.component === "accordion" && r.selector === "#faq-item");
  check("croComponentClassification detects a real native <details>/<summary> accordion", !!accordionDetails);

  const accordionAria = result.find((r) => r.component === "accordion" && r.selector === "#disclosure");
  check("croComponentClassification detects an ARIA disclosure-widget accordion pattern", !!accordionAria);

  const reviews = result.find((r) => r.component === "reviews" && r.selector === "#reviews-section");
  check("croComponentClassification detects reviews with high confidence (microdata + class signals)", reviews && reviews.confidence === "high");

  const gallery = result.find((r) => r.component === "productGallery" && r.selector === "#pdp-gallery");
  check("croComponentClassification detects the product gallery from a real naming convention with 3 real <img> children", !!gallery);

  check("croComponentClassification does not classify a plain unrelated div as any component", !result.some((r) => r.selector === "#plain"));
}

{
  // Negative case: position:sticky alone, with no Add to Cart identifier
  // at all, must not be misclassified as a sticky ATC button -- the
  // classifier requires both signals together, not sticky positioning
  // alone (a sticky header/nav is common and isn't an ATC button).
  const api = load(`<html><body><div id="sticky-header" style="position: sticky;">Header content</div></body></html>`);
  const result = api.croComponentClassification();
  check("croComponentClassification does not classify a sticky header with no ATC identifier as stickyAddToCart", !result.some((r) => r.component === "stickyAddToCart"));
}

// --- A/B testing platform detection + experimentAwareness ---
{
  const api = load(`<html><head><script src="https://cdn.optimizely.com/js/12345.js"></script></head><body></body></html>`, (window) => {
    window.optimizely = [];
  });
  const result = api.technologyFingerprint();
  const optimizely = result.find((r) => r.technology === "Optimizely");
  check("technologyFingerprint detects Optimizely with high confidence from two real signals", optimizely && optimizely.category === "abTesting" && optimizely.confidence === "high");
}

{
  const api = load(`<html><head><script src="https://dev.visualwebsiteoptimizer.com/j.php?a=123"></script></head><body></body></html>`);
  const result = api.technologyFingerprint();
  const vwo = result.find((r) => r.technology === "VWO");
  check("technologyFingerprint detects VWO from a real script src", vwo && vwo.category === "abTesting");
}

{
  const api = load(`<html><head><script src="https://www.googleoptimize.com/optimize.js?id=GTM-XXXX"></script></head><body></body></html>`);
  const result = api.technologyFingerprint();
  const optimize = result.find((r) => r.technology === "Google Optimize");
  check("technologyFingerprint detects Google Optimize from a real script src", !!optimize);
}

{
  const api = load(`<html><body></body></html>`, (window) => {
    window.document.cookie = "optimizelyEndUserId=abc123; path=/";
    window.document.cookie = "sessionid=xyz; path=/";
    window.localStorage.setItem("vwo_uuid_v2", "1234");
    window.localStorage.setItem("unrelated_key", "value");
  });
  const result = api.experimentAwareness(undefined, new Date("2024-01-01T00:00:00.000Z"));
  check("experimentAwareness detects a real experiment-shaped cookie and ignores an unrelated one", result.experimentCookieNames.includes("optimizelyEndUserId") && !result.experimentCookieNames.includes("sessionid"));
  check("experimentAwareness detects a real experiment-shaped localStorage key and ignores an unrelated one", result.experimentLocalStorageKeys.includes("vwo_uuid_v2") && !result.experimentLocalStorageKeys.includes("unrelated_key"));
  check("experimentAwareness reports hasExperimentSignal:true when a real signal is present", result.hasExperimentSignal === true);
  check("experimentAwareness reports the real supplied timestamp as ISO 8601", result.capturedAt === "2024-01-01T00:00:00.000Z");
}

{
  const api = load(`<html><body></body></html>`);
  const result = api.experimentAwareness(undefined, new Date("2024-01-01T00:00:00.000Z"));
  check("experimentAwareness reports hasExperimentSignal:false with empty cookies/localStorage", result.hasExperimentSignal === false && result.experimentCookieNames.length === 0 && result.experimentLocalStorageKeys.length === 0);
}

// --- cartPriceConsistencyCheck ---
{
  const api = load(`<html><body></body></html>`);
  const matching = api.cartPriceConsistencyCheck(59.99, 49.99, 10);
  check("cartPriceConsistencyCheck reports matches:true when the real cart price equals PDP price minus the real discount", matching.matches === true && matching.expectedCartPrice === 49.99);

  const mismatched = api.cartPriceConsistencyCheck(59.99, 55.00, 10);
  check("cartPriceConsistencyCheck reports matches:false for a genuine real mismatch", mismatched.matches === false);

  const noDiscount = api.cartPriceConsistencyCheck(59.99, 59.99);
  check("cartPriceConsistencyCheck defaults discountAmount to 0 and matches when PDP and cart price are identical", noDiscount.matches === true);

  const missingData = api.cartPriceConsistencyCheck(null, 59.99);
  check("cartPriceConsistencyCheck returns matches:null (not false) when a real price is missing", missingData.matches === null);
}

// --- recommendationsIntelligence ---
{
  const api = load(`
    <html><body>
      <div id="recs" class="nosto_element" data-vendor="nosto">
        <a href="/products/widget-a">Widget A</a>
        <a href="/products/widget-b">Widget B</a>
        <a href="/products/widget-a">Widget A</a>
        <a href="/products/current-product">Current Product</a>
      </div>
    </body></html>
  `);
  const result = api.recommendationsIntelligence("#recs", undefined, "/products/current-product");
  check("recommendationsIntelligence reports the real total link count", result.count === 4);
  check("recommendationsIntelligence reports the real unique href count", result.uniqueCount === 3);
  check("recommendationsIntelligence collects each real link's label text", result.labels.includes("Widget A") && result.labels.includes("Widget B"));
  check("recommendationsIntelligence flags the real duplicate href", result.duplicateHrefs.includes("/products/widget-a"));
  check("recommendationsIntelligence detects the real self-recommendation (current product recommending itself)", result.recommendsCurrentProduct === true);
  check("recommendationsIntelligence detects the real vendor from a known naming convention", result.vendor === "Nosto");
}

{
  const api = load(`<html><body><div id="recs"><a href="/products/a">A</a></div></body></html>`);
  const result = api.recommendationsIntelligence("#recs");
  check("recommendationsIntelligence reports vendor:null for an unrecognized/absent vendor signal rather than guessing", result.vendor === null);
  check("recommendationsIntelligence reports recommendsCurrentProduct:false when no current product URL is supplied", result.recommendsCurrentProduct === false);
}

{
  const api = load(`<html><body></body></html>`);
  check("recommendationsIntelligence returns null when the container selector matches nothing real", api.recommendationsIntelligence("#nonexistent") === null);
}

// --- shopifyThemeIntelligence ---
{
  const api = load(`
    <html><body>
      <div id="shopify-section-header-123">Header</div>
      <div id="shopify-section-main-product-456">
        <div data-block-id="block-1">Reviews app block</div>
        <div data-block-id="block-2">Upsell app block</div>
      </div>
    </body></html>
  `, (window) => {
    window.Shopify = { theme: { name: "Dawn", id: 987654321, theme_store_id: 887, role: "main" }, template: "product" };
  });
  const result = api.shopifyThemeIntelligence();
  check("shopifyThemeIntelligence reads the real theme name/id/theme_store_id", result.themeName === "Dawn" && result.themeId === 987654321 && result.themeStoreId === 887);
  check("shopifyThemeIntelligence reads the real template type", result.templateType === "product");
  check("shopifyThemeIntelligence finds real section IDs from the shopify-section- DOM convention", result.sectionIds.includes("header-123") && result.sectionIds.includes("main-product-456"));
  check("shopifyThemeIntelligence finds real app-block IDs from data-block-id attributes", result.appBlockIds.includes("block-1") && result.appBlockIds.includes("block-2"));
}

{
  const api = load(`<html><body></body></html>`);
  const result = api.shopifyThemeIntelligence();
  check("shopifyThemeIntelligence reports null (never a guess) when window.Shopify is genuinely absent", result.themeName === null && result.themeId === null && result.themeStoreId === null && result.templateType === null);
  check("shopifyThemeIntelligence reports empty arrays rather than crashing when no sections/app-blocks exist", result.sectionIds.length === 0 && result.appBlockIds.length === 0);
}

// --- ecommerceImageAudit ---
{
  const api = load(`
    <html><body>
      <div id="pdp-gallery" class="product-media-gallery">
        <a href="https://example.com/images/full-1.jpg"><img src="thumb1.jpg" width="80" height="80" alt="Front view"></a>
        <a href="https://example.com/pdp/widget"><img src="thumb2.jpg" width="80" height="80" alt="Side view"></a>
        <img src="thumb3.jpg" data-zoom-image="zoom3.jpg" alt="Back view">
      </div>
    </body></html>
  `);
  const result = api.ecommerceImageAudit("#pdp-gallery");
  check("ecommerceImageAudit counts the real gallery image count", result.galleryCount === 3);
  check("ecommerceImageAudit reads each real thumbnail's authored width/height", result.thumbnails[0].width === 80 && result.thumbnails[0].height === 80);
  check("ecommerceImageAudit reads each real thumbnail's alt text", result.thumbnails[0].alt === "Front view");
  check("ecommerceImageAudit detects a zoom source via a same-extension image href", result.thumbnails[0].hasZoomSource === true);
  check("ecommerceImageAudit does not flag an anchor linking to a real product page as a zoom source", result.thumbnails[1].hasZoomSource === false);
  check("ecommerceImageAudit detects a zoom source via a real data-zoom-image attribute", result.thumbnails[2].hasZoomSource === true);
  check("ecommerceImageAudit's zoomSourceCount reflects exactly the real 2 zoom-capable thumbnails", result.zoomSourceCount === 2);
}

{
  const api = load(`<html><body><div id="empty-gallery" class="product-media-gallery"></div></body></html>`);
  const result = api.ecommerceImageAudit("#empty-gallery");
  check("ecommerceImageAudit reports a real zero gallery count for an empty container, not a crash", result.galleryCount === 0 && result.thumbnails.length === 0);
}

{
  const api = load(`<html><body></body></html>`);
  check("ecommerceImageAudit returns null when the gallery selector matches nothing real on the page", api.ecommerceImageAudit("#nonexistent") === null);
}

// --- Structured data extraction ---
{
  const productJSONLD = JSON.stringify({
    "@context": "https://schema.org",
    "@type": "Product",
    name: "Widget Pro",
    sku: "WID-100",
    offers: { "@type": "Offer", price: "29.99", priceCurrency: "USD", availability: "https://schema.org/InStock" },
    aggregateRating: { "@type": "AggregateRating", ratingValue: "4.5", reviewCount: "120" }
  });
  const api = load(`
    <html><head><script type="application/ld+json">${productJSONLD}</script></head><body></body></html>
  `);
  const items = api.extractStructuredData();
  check("extractStructuredData finds the Product item", items.some((i) => i["@type"] === "Product"));

  const pdp = api.extractPDPData();
  check("extractPDPData extracts the real title", pdp.title === "Widget Pro");
  check("extractPDPData extracts the real SKU", pdp.sku === "WID-100");
  check("extractPDPData extracts the real price and currency", pdp.price === "29.99" && pdp.currency === "USD");
  check("extractPDPData strips the schema.org URL prefix from availability", pdp.availability === "InStock");
  check("extractPDPData extracts rating value and review count", pdp.ratingValue === "4.5" && pdp.reviewCount === "120");
}

// --- @graph shape ---
{
  const graphJSONLD = JSON.stringify({
    "@context": "https://schema.org",
    "@graph": [
      { "@type": "BreadcrumbList", itemListElement: [] },
      { "@type": "Product", name: "Graph Widget", offers: { "@type": "Offer", price: "9.99", priceCurrency: "EUR" } }
    ]
  });
  const api = load(`<html><head><script type="application/ld+json">${graphJSONLD}</script></head><body></body></html>`);
  const items = api.extractStructuredData();
  check("extractStructuredData handles the @graph array shape", items.some((i) => i["@type"] === "Product") && items.some((i) => i["@type"] === "BreadcrumbList"));

  const pdp = api.extractPDPData();
  check("extractPDPData finds the Product inside a @graph block", pdp && pdp.title === "Graph Widget");
}

// --- extractBreadcrumbs ---
{
  const breadcrumbJSONLD = JSON.stringify({
    "@type": "BreadcrumbList",
    itemListElement: [
      { "@type": "ListItem", position: 2, name: "Widgets", item: "https://example.com/widgets" },
      { "@type": "ListItem", position: 1, name: "Home", item: "https://example.com/" },
      { "@type": "ListItem", position: 3, name: "Widget Pro", item: { "@id": "https://example.com/widgets/pro" } }
    ]
  });
  const api = load(`<html><head><script type="application/ld+json">${breadcrumbJSONLD}</script></head><body></body></html>`);
  const breadcrumbs = api.extractBreadcrumbs();
  check("extractBreadcrumbs finds all three real breadcrumb entries", breadcrumbs.length === 3);
  check("extractBreadcrumbs sorts by the schema's own position field, not array order", breadcrumbs.map((b) => b.name).join(",") === "Home,Widgets,Widget Pro");
  check("extractBreadcrumbs reads a plain string item URL", breadcrumbs[0].url === "https://example.com/");
  check("extractBreadcrumbs reads an item object's @id as the URL", breadcrumbs[2].url === "https://example.com/widgets/pro");
}

{
  const api = load(`<html><head></head><body></body></html>`);
  check("extractBreadcrumbs returns an empty array when there's no real BreadcrumbList on the page", api.extractBreadcrumbs().length === 0);
}

// --- Malformed JSON-LD doesn't break the rest of the page's data ---
{
  const validJSONLD = JSON.stringify({ "@type": "Product", name: "Still Works", offers: { price: "5.00" } });
  const api = load(`
    <html><head>
      <script type="application/ld+json">{ not valid json </script>
      <script type="application/ld+json">${validJSONLD}</script>
    </head><body></body></html>
  `);
  const items = api.extractStructuredData();
  check("A malformed JSON-LD block is skipped without breaking extraction of a later valid block", items.some((i) => i.name === "Still Works"));
}

// --- Price consistency check ---
{
  const productJSONLD = JSON.stringify({
    "@type": "Product", name: "Widget", offers: { price: "29.99", priceCurrency: "USD" }
  });
  const matchingApi = load(`
    <html><head><script type="application/ld+json">${productJSONLD}</script></head>
    <body><div class="product-price">$29.99</div></body></html>
  `);
  const matchingResult = matchingApi.priceConsistencyCheck();
  check("priceConsistencyCheck reports matches:true when visible price equals schema price", matchingResult.matches === true);

  const mismatchApi = load(`
    <html><head><script type="application/ld+json">${productJSONLD}</script></head>
    <body><div class="product-price">$24.99</div></body></html>
  `);
  const mismatchResult = mismatchApi.priceConsistencyCheck();
  check("priceConsistencyCheck reports matches:false for a real price mismatch", mismatchResult.matches === false);
  check("priceConsistencyCheck reports the actual schema and visible price values", mismatchResult.schemaPrice === 29.99 && mismatchResult.visiblePrice === 24.99);
}

{
  const microdataApi = load(`
    <html><body><span itemprop="price" content="15.50">$15.50</span></body></html>
  `);
  const result = microdataApi.priceConsistencyCheck();
  // No schema.org JSON-LD Product here, so schemaPrice is null and no
  // pass/fail verdict can be made either way (not enough data to compare).
  check("priceConsistencyCheck returns matches:null when there's no schema price to compare against", result.matches === null && result.visiblePrice === 15.5);
}

// --- PLP card scanner ---
{
  const api = load(`
    <html><body>
      <div class="product-grid">
        <div class="product-card">
          <img src="a.jpg"><div class="price">$10</div><span class="badge">Sale</span>
          <button class="add-to-cart">Add to cart</button>
        </div>
        <div class="product-card">
          <img src="b.jpg"><div class="price">$20</div>
        </div>
        <div class="product-card">
          <div class="price">$30</div><span class="review-count">12 reviews</span>
        </div>
      </div>
    </body></html>
  `);
  const result = api.plpCardScan(undefined, ".product-card");
  check("plpCardScan finds all 3 cards", result.cardCount === 3);
  check("plpCardScan's image distribution reflects exactly 2 of 3 cards having an image", result.distribution.withImage === 67);
  check("plpCardScan's price distribution reflects all 3 cards having a price", result.distribution.withPrice === 100);
  check("plpCardScan's badge distribution reflects exactly 1 of 3 cards having a badge", result.distribution.withBadge === 33);
  check("plpCardScan's CTA distribution reflects exactly 1 of 3 cards having a CTA", result.distribution.withCTA === 33);
}

{
  const api = load(`<html><body><div class="unrelated"></div></body></html>`);
  const result = api.plpCardScan(undefined, ".product-card");
  check("plpCardScan with zero matching cards reports a 0% distribution, not NaN/crash", result.cardCount === 0 && result.distribution.withImage === 0);
}

// --- imageRatioConsistency ---
{
  const api = load(`<html><body></body></html>`);
  const result = api.imageRatioConsistency([1.25, 1.25, 1.25, 1.25]);
  check("imageRatioConsistency reports 100% consistency when every real ratio matches", result.consistencyPercentage === 100 && result.mostCommonRatio === 1.25 && result.outlierIndices.length === 0);
}

{
  const api = load(`<html><body></body></html>`);
  // 11 cards share a ratio, 1 doesn't -- mirrors the pattern already
  // proven for MultiElementComparison on the Swift side.
  const ratios = Array(11).fill(0.8).concat([1.5]);
  const result = api.imageRatioConsistency(ratios);
  check("imageRatioConsistency finds the real majority ratio and flags exactly the one real outlier", result.mostCommonRatio === 0.8 && result.outlierIndices.length === 1 && result.outlierIndices[0] === 11);
  check("imageRatioConsistency's percentage reflects 11 of 12 matching", result.consistencyPercentage === Math.round((11 / 12) * 100));
}

{
  const api = load(`<html><body></body></html>`);
  // Real floating-point ratios that are extremely close but not
  // bit-identical (0.8 vs 0.799999...) should still bucket together --
  // real proof this isn't naively comparing raw floats.
  const result = api.imageRatioConsistency([0.8, 0.7999999999, 0.8000000001]);
  check("imageRatioConsistency buckets near-identical real floating-point ratios together", result.consistencyPercentage === 100);
}

{
  const api = load(`<html><body></body></html>`);
  const result = api.imageRatioConsistency([]);
  check("imageRatioConsistency handles an empty real input without crashing", result.consistencyPercentage === 100 && result.mostCommonRatio === null);
}

// --- No product data present ---
{
  const api = load(`<html><head></head><body>No structured data here.</body></html>`);
  check("extractPDPData returns null when there's no Product structured data", api.extractPDPData() === null);
}

// --- runAndReportEcommerceAudit relays a snapshot the same way
// accessibility-audit.js's runAndReportAccessibilityAudit does ---
{
  const sentMessages = [];
  let triggerListener = null;
  load(`<html><body>No structured data here.</body></html>`, (window) => {
    window.chrome = {
      runtime: {
        sendMessage: (message) => sentMessages.push(message),
        onMessage: { addListener: (fn) => { triggerListener = fn; } }
      }
    };
  });

  check("runAndReportEcommerceAudit registers a capture.ecommerce.audit.trigger listener", typeof triggerListener === "function");
  triggerListener({ kind: "capture.ecommerce.audit.trigger" });

  check("runAndReportEcommerceAudit sends exactly one message", sentMessages.length === 1);
  const message = sentMessages[0];
  check("runAndReportEcommerceAudit relays the correct envelope kind/type", message.kind === "capture.bridge.request" && message.type === "ecommerce.audit.result");
  check("runAndReportEcommerceAudit's payload carries the page URL and viewport", message.payload.url === "https://example.com/product/widget" && typeof message.payload.viewportWidth === "number");

  const snapshot = JSON.parse(message.payload.snapshotJSON);
  check(
    "runAndReportEcommerceAudit's snapshotJSON carries the selector-free detectors",
    "priceConsistencyCheck" in snapshot && "technologyFingerprint" in snapshot && "croComponentClassification" in snapshot
  );
}

console.log(`=== ${failureCount === 0 ? "ALL CHECKS PASSED" : `${failureCount} CHECK(S) FAILED`} ===`);
process.exit(failureCount === 0 ? 0 : 1);
