// Capture browser bridge — ecommerce intelligence content script:
// storefront-platform/technology fingerprinting, PDP/schema extraction,
// price consistency, PLP card scanning, CRO component classification,
// Shopify theme intelligence, recommendations intelligence.
//
// Ported from the original Capture app's extensions/chromium (owned by
// the user; see docs/REFERENCE_PROVENANCE.md). A separate content script
// (distinct on-demand analysis passes stay in their own files, same
// pattern as accessibility-audit.js).
//
// NOT YET LOADED INTO A REAL CHROME SESSION in this environment --
// verified with real jsdom DOM-level tests
// (tests/ecommerce-intelligence.test.js) that build real DOM trees
// (including real <script type="application/ld+json"> blocks) and check
// this code's actual output against them.
//
// Every detection is public-data-only (script tags, meta tags, cookies,
// window globals visible to a content script, and structured data the
// page itself published) -- never anything requiring elevated access.

(() => {
  /// Never a proprietary fingerprint DB, just a small explicit detector
  /// registry. Every detection must show Technology / Confidence /
  /// Signals -- never claim a tag is "working" merely because the script
  /// exists. Each entry's `signals` function returns the *specific*
  /// matched evidence (e.g. the actual matching script src) rather than
  /// a bare boolean, so a finding can cite exactly what was observed.
  const TECHNOLOGY_DETECTORS = [
    {
      name: "Shopify",
      category: "platform",
      signals: (ctx) => {
        const found = [];
        if (ctx.window.Shopify) found.push("window.Shopify global present");
        if (ctx.scriptSrcs.some((src) => src.includes("cdn.shopify.com"))) found.push("script from cdn.shopify.com");
        const generator = ctx.document.querySelector('meta[name="generator"]');
        if (generator && /shopify/i.test(generator.getAttribute("content") || "")) found.push("meta generator tag mentions Shopify");
        return found;
      }
    },
    {
      name: "WooCommerce",
      category: "platform",
      signals: (ctx) => {
        const found = [];
        if (ctx.document.body && ctx.document.body.className.includes("woocommerce")) found.push("body class includes 'woocommerce'");
        if (ctx.scriptSrcs.some((src) => src.includes("woocommerce"))) found.push("script path includes 'woocommerce'");
        return found;
      }
    },
    {
      name: "Magento",
      category: "platform",
      signals: (ctx) => {
        const found = [];
        if (ctx.window.Mage) found.push("window.Mage global present");
        if (ctx.scriptSrcs.some((src) => src.includes("/mage/") || src.includes("mage-cache"))) found.push("script path includes Magento markers");
        return found;
      }
    },
    {
      name: "Google Analytics (GA4)",
      category: "analytics",
      signals: (ctx) => {
        const found = [];
        if (typeof ctx.window.gtag === "function") found.push("window.gtag function present");
        if (ctx.window.dataLayer && Array.isArray(ctx.window.dataLayer)) found.push("window.dataLayer array present");
        if (ctx.scriptSrcs.some((src) => src.includes("googletagmanager.com/gtag/js"))) found.push("script from googletagmanager.com/gtag/js");
        return found;
      }
    },
    {
      name: "Meta Pixel",
      category: "analytics",
      signals: (ctx) => {
        const found = [];
        if (typeof ctx.window.fbq === "function") found.push("window.fbq function present");
        if (ctx.scriptSrcs.some((src) => src.includes("connect.facebook.net"))) found.push("script from connect.facebook.net");
        return found;
      }
    },
    {
      name: "Klaviyo",
      category: "esp",
      signals: (ctx) => {
        const found = [];
        if (ctx.window._learnq) found.push("window._learnq global present");
        if (ctx.scriptSrcs.some((src) => src.includes("klaviyo.com"))) found.push("script from klaviyo.com");
        return found;
      }
    },
    // Search intelligence: detect public search tooling (Shopify native,
    // Algolia, Klevu, Searchspring, others) -- the same detector-registry
    // mechanism as the platform/analytics entries above, just a
    // different category.
    {
      name: "Algolia",
      category: "search",
      signals: (ctx) => {
        const found = [];
        if (ctx.window.algoliasearch) found.push("window.algoliasearch function present");
        // Algolia's own search API domains (algolia.net/algolianet.com)
        // are real signals when present, but the JS *client library*
        // itself is commonly loaded from a generic CDN (jsdelivr/unpkg/
        // cdnjs) rather than Algolia's own domain -- so a script whose
        // filename itself names the library (e.g. "algoliasearch.js",
        // "algoliasearch-lite.umd.js") is also treated as a real signal,
        // not just the API domain.
        if (ctx.scriptSrcs.some((src) => src.includes("algolia"))) found.push("script referencing Algolia (domain or library filename)");
        return found;
      }
    },
    {
      name: "Klevu",
      category: "search",
      signals: (ctx) => {
        const found = [];
        if (ctx.window.klevu) found.push("window.klevu global present");
        if (ctx.scriptSrcs.some((src) => src.includes("klevu.com"))) found.push("script from klevu.com");
        return found;
      }
    },
    {
      name: "Searchspring",
      category: "search",
      signals: (ctx) => {
        const found = [];
        if (ctx.window.SearchspringPersonalization || ctx.window.searchspring) found.push("window.Searchspring* global present");
        if (ctx.scriptSrcs.some((src) => src.includes("searchspring.io") || src.includes("searchspring.net"))) found.push("script from a Searchspring domain");
        return found;
      }
    },
    // Storefront-platform detection: Shopify, Shopify Hydrogen/headless
    // signals, Magento/Adobe Commerce, WooCommerce, Salesforce Commerce
    // Cloud, BigCommerce, others -- three more platforms beyond the
    // original Shopify/WooCommerce/Magento trio.
    {
      name: "BigCommerce",
      category: "platform",
      signals: (ctx) => {
        const found = [];
        if (ctx.window.BCData) found.push("window.BCData global present");
        if (ctx.scriptSrcs.some((src) => src.includes("cdn11.bigcommerce.com") || src.includes("bigcommerce.com"))) found.push("script from a BigCommerce CDN domain");
        return found;
      }
    },
    {
      name: "Salesforce Commerce Cloud",
      category: "platform",
      signals: (ctx) => {
        const found = [];
        // Real, public URL-path convention for Salesforce Commerce Cloud
        // (formerly Demandware) storefronts: requests routed through
        // `/on/demandware.store/...`, and static assets served from a
        // `*.demandware.static/` path.
        if (ctx.scriptSrcs.some((src) => src.includes("demandware.static") || src.includes("/on/demandware.store/"))) found.push("script path includes a Demandware/Salesforce Commerce Cloud convention");
        if (ctx.window.dw && ctx.window.dw.ajax) found.push("window.dw.ajax global present (SFCC's own storefront JS namespace)");
        return found;
      }
    },
    // A/B testing technology category.
    {
      name: "Optimizely",
      category: "abTesting",
      signals: (ctx) => {
        const found = [];
        if (ctx.window.optimizely) found.push("window.optimizely global present");
        if (ctx.scriptSrcs.some((src) => src.includes("cdn.optimizely.com"))) found.push("script from cdn.optimizely.com");
        return found;
      }
    },
    {
      name: "VWO",
      category: "abTesting",
      signals: (ctx) => {
        const found = [];
        if (ctx.window._vwo_code || ctx.window.VWO) found.push("window._vwo_code/VWO global present");
        if (ctx.scriptSrcs.some((src) => src.includes("visualwebsiteoptimizer.com"))) found.push("script from visualwebsiteoptimizer.com");
        return found;
      }
    },
    {
      name: "Google Optimize",
      category: "abTesting",
      signals: (ctx) => {
        const found = [];
        if (ctx.scriptSrcs.some((src) => src.includes("googleoptimize.com"))) found.push("script from googleoptimize.com");
        return found;
      }
    },
    {
      name: "Shopify Hydrogen (headless)",
      category: "platform",
      signals: (ctx) => {
        const found = [];
        // Headless Hydrogen storefronts are Remix-based and won't carry
        // the classic `cdn.shopify.com`/`window.Shopify` signals a
        // traditional Liquid theme does -- this looks for Remix's own
        // hydration markers *combined with* an explicit Hydrogen
        // reference, since Remix alone is a much more general signal
        // that would misidentify any non-Shopify Remix app.
        const hasRemixMarker = !!ctx.document.getElementById("__remixContext") || !!ctx.window.__remixContext;
        const hasHydrogenReference = ctx.scriptSrcs.some((src) => src.includes("hydrogen")) ||
          !!ctx.document.querySelector('meta[name="generator"][content*="Hydrogen" i]');
        if (hasRemixMarker && hasHydrogenReference) found.push("Remix hydration marker present alongside an explicit Hydrogen reference");
        return found;
      }
    }
  ];

  /// Every detection must show Technology / Confidence / Signals.
  /// Confidence is deliberately coarse (`high` when 2+ independent
  /// signals agree, `medium` for exactly one) rather than a fake precise
  /// percentage -- this is a heuristic detector, not a certainty.
  function technologyFingerprint(root = document, win = window) {
    const scriptSrcs = Array.from(root.querySelectorAll("script[src]")).map((el) => el.getAttribute("src") || "");
    const ctx = { document: root, window: win, scriptSrcs };

    return TECHNOLOGY_DETECTORS.map((detector) => {
      const signals = detector.signals(ctx);
      return { technology: detector.name, category: detector.category, confidence: signals.length >= 2 ? "high" : signals.length === 1 ? "medium" : "none", signals };
    }).filter((result) => result.signals.length > 0);
  }

  /// Schema inspection: Product/Offer/AggregateRating/BreadcrumbList
  /// structured data. Parses every `<script type="application/ld+json">`
  /// block, tolerating a malformed block (skipped, not fatal to the rest
  /// of the page's structured data) and both a single object and a
  /// `@graph`/array of objects per the JSON-LD spec's own valid shapes.
  function extractStructuredData(root = document) {
    const blocks = Array.from(root.querySelectorAll('script[type="application/ld+json"]'));
    const items = [];
    for (const block of blocks) {
      let parsed;
      try {
        parsed = JSON.parse(block.textContent || "");
      } catch (e) {
        continue;
      }
      const candidates = Array.isArray(parsed) ? parsed : parsed["@graph"] ? parsed["@graph"] : [parsed];
      for (const candidate of candidates) {
        if (candidate && typeof candidate === "object" && candidate["@type"]) {
          items.push(candidate);
        }
      }
    }
    return items;
  }

  function findByType(items, type) {
    return items.filter((item) => {
      const t = item["@type"];
      return t === type || (Array.isArray(t) && t.includes(type));
    });
  }

  /// PDP extraction (public data only): title, price, compare-at,
  /// currency, availability, SKU/IDs when exposed, product JSON/
  /// structured data. Sources the JSON-LD `Product`/`Offer` when present
  /// (authoritative, exact) -- this is the *browser-bridge* piece; the
  /// "compare visible price vs. schema price" consistency check is a
  /// comparison step a caller does with this data plus a separate
  /// visible-DOM-price reading, not modeled here.
  function extractPDPData(root = document) {
    const structuredData = extractStructuredData(root);
    const products = findByType(structuredData, "Product");
    if (products.length === 0) return null;

    const product = products[0];
    const offer = Array.isArray(product.offers) ? product.offers[0] : product.offers;
    const rating = product.aggregateRating;

    return {
      title: product.name || null,
      sku: product.sku || null,
      price: offer ? offer.price ?? null : null,
      currency: offer ? offer.priceCurrency ?? null : null,
      availability: offer ? (offer.availability || "").replace("https://schema.org/", "") || null : null,
      ratingValue: rating ? rating.ratingValue ?? null : null,
      reviewCount: rating ? rating.reviewCount ?? rating.ratingCount ?? null : null
    };
  }

  const PRICE_PATTERN = /[$€£]\s?\d{1,3}(?:[,.]\d{3})*(?:[.,]\d{2})?/;

  /// Price consistency check across visible price / compare-at price /
  /// schema JSON-LD price / selected-variant public data -- flag
  /// mismatches for human review. This reads the *visible* price (a
  /// microdata `itemprop="price"` element, or the first element whose
  /// class name mentions "price" containing currency-looking text -- a
  /// deliberately common-convention-based heuristic, not a claim to
  /// handle every possible price markup) and compares it against the
  /// schema price `extractPDPData` already reads, flagging a mismatch
  /// for a human to review rather than silently trusting either source.
  function findVisiblePriceText(root) {
    const microdataEl = root.querySelector('[itemprop="price"]');
    if (microdataEl) {
      const content = microdataEl.getAttribute("content");
      if (content) return content;
      const match = (microdataEl.textContent || "").match(PRICE_PATTERN);
      if (match) return match[0];
    }
    const priceClassEls = Array.from(root.querySelectorAll('[class*="price"]'));
    for (const el of priceClassEls) {
      const match = (el.textContent || "").match(PRICE_PATTERN);
      if (match) return match[0];
    }
    return null;
  }

  function parsePriceNumber(text) {
    if (!text) return null;
    const digitsOnly = text.replace(/[^0-9.,]/g, "").replace(/,(?=\d{3}\b)/g, "");
    const parsed = Number.parseFloat(digitsOnly);
    return Number.isNaN(parsed) ? null : parsed;
  }

  function priceConsistencyCheck(root = document) {
    const pdp = extractPDPData(root);
    const schemaPrice = pdp ? parsePriceNumber(String(pdp.price ?? "")) : null;
    const visibleRaw = findVisiblePriceText(root);
    const visiblePrice = parsePriceNumber(visibleRaw);

    if (schemaPrice === null || visiblePrice === null) {
      return { schemaPrice, visiblePrice, matches: null }; // not enough data to compare either way
    }
    return { schemaPrice, visiblePrice, matches: Math.abs(schemaPrice - visiblePrice) < 0.01 };
  }

  /// PLP/product-card scanner: inventory card dimensions, image ratio,
  /// title lines, price treatment, badges, review presence, CTA,
  /// swatches ... -> output as a distribution, never an automatic CRO
  /// conclusion. jsdom (this test harness) has no real layout engine, so
  /// pixel dimensions/line-wrapping aren't meaningfully measurable here
  /// -- this scans for real DOM *presence* signals per card (image,
  /// price text, a badge/sale marker, a review/rating indicator, a CTA
  /// button, swatches) and reports the aggregate distribution across all
  /// matched cards -- a percentage/count summary, not a verdict on any
  /// single card.
  function plpCardScan(root = document, cardSelector) {
    const cards = Array.from(root.querySelectorAll(cardSelector));
    const perCard = cards.map((card) => ({
      hasImage: !!card.querySelector("img"),
      hasPrice: !!findVisiblePriceText(card),
      hasBadge: !!card.querySelector('[class*="badge"], [class*="sale"]'),
      hasReview: !!card.querySelector('[class*="review"], [class*="rating"]'),
      hasCTA: !!card.querySelector("button, a[class*='add-to-cart'], a[class*='cta']"),
      hasSwatches: !!card.querySelector('[class*="swatch"]')
    }));

    const count = perCard.length;
    const percentage = (key) => (count === 0 ? 0 : Math.round((perCard.filter((c) => c[key]).length / count) * 100));

    return {
      cardCount: count,
      distribution: {
        withImage: percentage("hasImage"),
        withPrice: percentage("hasPrice"),
        withBadge: percentage("hasBadge"),
        withReview: percentage("hasReview"),
        withCTA: percentage("hasCTA"),
        withSwatches: percentage("hasSwatches")
      }
    };
  }

  /// The PLP scanner's own "image ratio ... -> output as a distribution"
  /// piece, and separately a visual-quality heuristic flag (e.g.
  /// inconsistent ratios within a product grid) -- flags only, not
  /// categorical judgments. Pure numeric consistency math over an array
  /// of already-computed width/height ratios -- deliberately *not*
  /// reading `naturalWidth`/`naturalHeight` internally, since jsdom (this
  /// test harness) never actually decodes images and those always report
  /// 0 here; a caller supplies real ratios (from real decoded images in
  /// production, or directly in a test) and this does the actual
  /// consistency comparison. Ratios are bucketed to 2 decimal places
  /// before grouping, since two product photos meant to share a ratio
  /// (e.g. both "4:5") will essentially never produce bit-identical
  /// floating-point ratios.
  function imageRatioConsistency(ratios) {
    if (ratios.length === 0) return { mostCommonRatio: null, consistencyPercentage: 100, outlierIndices: [] };
    const bucketed = ratios.map((r) => Math.round(r * 100) / 100);
    const counts = new Map();
    for (const ratio of bucketed) counts.set(ratio, (counts.get(ratio) || 0) + 1);
    const mostCommonRatio = Array.from(counts.entries()).sort((a, b) => b[1] - a[1])[0][0];
    const outlierIndices = bucketed.reduce((acc, ratio, i) => {
      if (ratio !== mostCommonRatio) acc.push(i);
      return acc;
    }, []);
    const consistencyPercentage = Math.round(((ratios.length - outlierIndices.length) / ratios.length) * 100);
    return { mostCommonRatio, consistencyPercentage, outlierIndices };
  }

  /// Schema inspection: Product/Offer/AggregateRating/BreadcrumbList
  /// structured data -- the one type name in that list `extractPDPData`
  /// doesn't already cover (Product/Offer/AggregateRating are read
  /// there). Extracts every `BreadcrumbList`'s `itemListElement` entries
  /// as an ordered `{position, name, url}` array -- real schema.org
  /// fields, not guessed -- so a caller can compare key visible values
  /// against the page's actual visible breadcrumb trail. `position` is
  /// read from the schema's own field rather than assumed from array
  /// order, since `itemListElement` entries aren't guaranteed to already
  /// be sorted.
  function extractBreadcrumbs(root = document) {
    const lists = findByType(extractStructuredData(root), "BreadcrumbList");
    if (lists.length === 0) return [];

    const items = (lists[0].itemListElement || []).map((entry) => ({
      position: entry.position ?? null,
      name: entry.name || (entry.item && entry.item.name) || null,
      url: entry.item ? (typeof entry.item === "string" ? entry.item : entry.item["@id"] || entry.item.url || null) : null
    }));
    items.sort((a, b) => (a.position ?? 0) - (b.position ?? 0));
    return items;
  }

  /// CRO component classification (optional local heuristics,
  /// confidence-scored, never silently assumed). Same registry-with-
  /// cited-signals shape as `TECHNOLOGY_DETECTORS` above, applied to
  /// structural/semantic DOM signals instead of script tags --
  /// deliberately scoped to a subset of the full component list where a
  /// real, defensible signal exists without needing actual page layout
  /// (which this jsdom-only test harness can't exercise): an authored
  /// `position: sticky`/`fixed` CSS declaration is readable from
  /// computed style without any real layout math, unlike e.g.
  /// distinguishing "hero" from "collection grid" by geometry alone,
  /// which needs real rendered position/size this environment can't
  /// produce. Each classifier returns matched elements plus the specific
  /// cited evidence, same "never claim more than what was observed"
  /// discipline as the technology fingerprint.
  const CRO_COMPONENT_CLASSIFIERS = [
    {
      component: "announcementBar",
      signals: (el, win) => {
        const found = [];
        const identifier = `${el.className || ""} ${el.id || ""}`.toLowerCase();
        if (/announcement/.test(identifier)) found.push("class/id mentions 'announcement'");
        if (el.getAttribute("role") === "region" && /announcement/.test(identifier)) found.push('role="region" combined with an announcement identifier');
        return found;
      }
    },
    {
      component: "cartDrawer",
      signals: (el) => {
        const found = [];
        const identifier = `${el.className || ""} ${el.id || ""}`.toLowerCase();
        if (/cart-drawer|mini-cart|cart-flyout/.test(identifier)) found.push("class/id matches a cart-drawer naming convention");
        if (el.hasAttribute("aria-hidden") && /cart/.test(identifier)) found.push('has aria-hidden (a toggleable-panel signature) combined with a cart identifier');
        return found;
      }
    },
    {
      component: "stickyAddToCart",
      signals: (el, win) => {
        const found = [];
        const identifier = `${el.className || ""} ${el.id || ""}`.toLowerCase();
        const style = win.getComputedStyle(el);
        const isSticky = style.position === "sticky" || style.position === "fixed";
        const mentionsATC = /add-to-cart|atc|buy-box/.test(identifier) || (el.textContent || "").toLowerCase().includes("add to cart");
        if (isSticky && mentionsATC) found.push(`authored position:${style.position} combined with an Add to Cart identifier`);
        return found;
      }
    },
    {
      component: "accordion",
      signals: (el) => {
        const found = [];
        if (el.tagName === "DETAILS" && el.querySelector("summary")) found.push("a real <details>/<summary> pair (the native HTML accordion primitive)");
        if (el.hasAttribute("aria-expanded") && el.hasAttribute("aria-controls")) found.push("aria-expanded combined with aria-controls (the ARIA disclosure-widget pattern)");
        return found;
      }
    },
    {
      component: "reviews",
      signals: (el) => {
        const found = [];
        const identifier = `${el.className || ""} ${el.id || ""}`.toLowerCase();
        if (el.getAttribute("itemtype") && /AggregateRating|Review/.test(el.getAttribute("itemtype"))) found.push("itemtype references AggregateRating/Review (schema.org microdata)");
        if (/review/.test(identifier)) found.push("class/id mentions 'review'");
        return found;
      }
    },
    {
      component: "productGallery",
      signals: (el) => {
        const found = [];
        const identifier = `${el.className || ""} ${el.id || ""}`.toLowerCase();
        const imageCount = el.querySelectorAll("img").length;
        if (/gallery|product-media|pdp-media/.test(identifier) && imageCount >= 2) found.push(`class/id matches a gallery naming convention with ${imageCount} real <img> children`);
        return found;
      }
    }
  ];

  /// Walks every element once, running each classifier against it, and
  /// returns only real matches with their cited evidence and a coarse
  /// confidence (`high` for 2+ independent signals, `medium` for exactly
  /// one) -- the same confidence convention `technologyFingerprint` uses,
  /// so callers get one consistent shape across both features. "Never
  /// silently assumed" is enforced by requiring at least one real cited
  /// signal for every reported match; there is no default/fallback
  /// classification for an element that matches nothing.
  function croComponentClassification(root = document, win = window) {
    const results = [];
    const elements = root.querySelectorAll("*");
    for (const el of elements) {
      for (const classifier of CRO_COMPONENT_CLASSIFIERS) {
        const signals = classifier.signals(el, win) || [];
        if (signals.length > 0) {
          results.push({
            component: classifier.component,
            confidence: signals.length >= 2 ? "high" : "medium",
            signals,
            selector: el.id ? `#${el.id}` : el.tagName.toLowerCase()
          });
        }
      }
    }
    return results;
  }

  /// Ecommerce image audit: ratio consistency, intrinsic vs rendered
  /// resolution, zoom source, gallery count, thumbnail size, video/model
  /// presence, alt text, format, responsive delivery. Most of this is
  /// already covered by dedicated, independently-tested functions
  /// elsewhere (`imageRatioConsistency` here; a future asset-inspector.js
  /// counterpart for scaling/responsive/video audits) that this audit is
  /// meant to be composed with, not duplicate. What's specific to *this*
  /// function: counting a real PDP gallery's images ("gallery count"),
  /// each thumbnail's real authored dimensions ("thumbnail size"), and
  /// detecting a real "zoom source" signal -- a magnifier/zoom feature's
  /// larger source image, via the two real, commonly-used public
  /// conventions: a `data-zoom-image`/`data-large` attribute on the
  /// `<img>` itself, or its enclosing `<a>` linking directly to a
  /// same-extension image file (the common "click thumbnail to open
  /// full-size" pattern) rather than a product page.
  function ecommerceImageAudit(gallerySelector, root = document) {
    const container = root.querySelector(gallerySelector);
    if (!container) return null;

    const images = Array.from(container.querySelectorAll("img"));
    const thumbnails = images.map((img) => {
      const anchor = img.closest("a");
      const anchorHref = anchor ? anchor.getAttribute("href") : null;
      const hasZoomSource = !!(
        img.getAttribute("data-zoom-image") ||
        img.getAttribute("data-large") ||
        (anchorHref && /\.(jpg|jpeg|png|webp|avif)(\?|$)/i.test(anchorHref))
      );
      const widthAttr = img.getAttribute("width");
      const heightAttr = img.getAttribute("height");
      return {
        src: img.getAttribute("src"),
        width: widthAttr ? parseInt(widthAttr, 10) : null,
        height: heightAttr ? parseInt(heightAttr, 10) : null,
        alt: img.getAttribute("alt") || null,
        hasZoomSource
      };
    });

    return {
      galleryCount: images.length,
      thumbnails,
      zoomSourceCount: thumbnails.filter((t) => t.hasZoomSource).length
    };
  }

  /// Experiment awareness: detect public A/B platform/experiment/
  /// variation IDs, relevant cookies/local storage, timestamp; attach to
  /// capture metadata to avoid comparing screenshots from different
  /// unknown variants. The A/B *platform* itself is detected via
  /// `technologyFingerprint`'s `abTesting` category entries above; this
  /// covers the rest -- real experiment-shaped cookies and localStorage
  /// keys, matched against known real naming conventions (Optimizely's
  /// own `optimizelyEndUserId`, VWO's own `_vwo_uuid`, and generic
  /// `experiment`/`variation`/`ab_test` substrings other platforms
  /// commonly use) -- plus a timestamp, so a caller can attach this to
  /// capture metadata and know two captures might not be directly
  /// comparable if their experiment signals differ.
  function experimentAwareness(win = window, referenceDate = new Date()) {
    const cookiePairs = (win.document.cookie || "").split(";").map((c) => c.trim()).filter(Boolean);
    const experimentCookieNames = cookiePairs
      .map((pair) => pair.split("=")[0])
      .filter((name) => /optimizely|_vwo_|_ga_experiment|ab_test|experiment|variation/i.test(name));

    let experimentLocalStorageKeys = [];
    try {
      for (let i = 0; i < win.localStorage.length; i++) {
        const key = win.localStorage.key(i);
        if (key && /optimizely|vwo|experiment|variation|ab_test/i.test(key)) experimentLocalStorageKeys.push(key);
      }
    } catch (e) {
      // localStorage access can legitimately throw (e.g. a sandboxed
      // iframe with storage access denied) -- absence of a signal here
      // is not itself a finding.
    }

    return {
      hasExperimentSignal: experimentCookieNames.length > 0 || experimentLocalStorageKeys.length > 0,
      experimentCookieNames,
      experimentLocalStorageKeys,
      capturedAt: referenceDate.toISOString()
    };
  }

  /// Shopify theme intelligence where signals permit: theme name/ID/
  /// version, template type, section IDs, app blocks, theme app
  /// extensions -- never guess unexposed values. Reads only real,
  /// publicly-documented Shopify signals: `window.Shopify.theme` (the
  /// storefront's own real object, exposing `name`/`id`/
  /// `theme_store_id`/`role` on any theme that sets it -- most do, since
  /// Shopify's own theme-check/analytics tooling expects it) and
  /// `window.Shopify.template` (the current template type, e.g.
  /// `"product"`/`"collection"`); section IDs and app-block IDs are read
  /// from Shopify Online Store 2.0's own real, documented DOM
  /// conventions (`id="shopify-section-{id}"` wrapper divs and
  /// `data-block-id` attributes on app blocks) rather than guessed at.
  /// Every field is `null`/empty when genuinely absent -- never a
  /// fabricated placeholder.
  function shopifyThemeIntelligence(win = window, root = document) {
    const theme = win.Shopify && win.Shopify.theme ? win.Shopify.theme : null;
    const sectionIds = Array.from(root.querySelectorAll('[id^="shopify-section-"]')).map(
      (el) => el.id.replace("shopify-section-", "")
    );
    const appBlockIds = Array.from(root.querySelectorAll("[data-block-id]")).map((el) => el.getAttribute("data-block-id"));

    return {
      themeName: theme ? theme.name || null : null,
      themeId: theme ? theme.id || null : null,
      themeStoreId: theme ? theme.theme_store_id || null : null,
      templateType: win.Shopify && win.Shopify.template ? win.Shopify.template : null,
      sectionIds,
      appBlockIds
    };
  }

  /// Recommendations intelligence: container/vendor/endpoint/labels/
  /// count/duplicates/relationship-to-current-product where public data
  /// allows comparison. `endpoint` (the actual network request URL a
  /// recommendations widget calls) needs live network observation this
  /// analysis-over-a-DOM-snapshot function doesn't have -- the rest is
  /// real, DOM-derivable: `container` is the caller-supplied selector's
  /// own matched element; `vendor` matches the container's class/id/
  /// `data-vendor` attribute against known real recommendation-widget
  /// naming conventions (Nosto/LimeSpot/Rebuy/Klaviyo); `labels` are each
  /// recommended link's own real text content; `count`/`duplicates` are
  /// computed from the real `href`s -- a duplicate href is a real, known
  /// problem (the same product recommended twice, or the *current*
  /// product recommending itself, both flagged as evidence, not a
  /// merchandising verdict) rather than a guess.
  function recommendationsIntelligence(containerSelector, root = document, currentProductURL = null) {
    const container = root.querySelector(containerSelector);
    if (!container) return null;

    const links = Array.from(container.querySelectorAll("a[href]"));
    const hrefs = links.map((a) => a.getAttribute("href"));
    const labels = links.map((a) => (a.textContent || "").trim());

    const hrefCounts = new Map();
    for (const href of hrefs) hrefCounts.set(href, (hrefCounts.get(href) || 0) + 1);
    const duplicateHrefs = Array.from(hrefCounts.entries()).filter(([, count]) => count > 1).map(([href]) => href);

    const identifier = `${container.className || ""} ${container.id || ""} ${container.getAttribute("data-vendor") || ""}`.toLowerCase();
    const vendorSignatures = [
      { vendor: "Nosto", pattern: /nosto/ },
      { vendor: "LimeSpot", pattern: /limespot/ },
      { vendor: "Rebuy", pattern: /rebuy/ },
      { vendor: "Klaviyo", pattern: /klaviyo/ }
    ];
    const matchedVendor = vendorSignatures.find((v) => v.pattern.test(identifier));

    return {
      count: hrefs.length,
      uniqueCount: hrefCounts.size,
      labels,
      duplicateHrefs,
      recommendsCurrentProduct: currentProductURL ? hrefs.includes(currentProductURL) : false,
      vendor: matchedVendor ? matchedVendor.vendor : null
    };
  }

  /// Link PDP price -> cart price -> applied discount (no backend
  /// inference without connected data) -- a pure comparison over three
  /// already-observed values (each independently captured from its own
  /// real page, e.g. via `extractPDPData`/a cart-page price extraction a
  /// caller supplies), never inferring a discount that wasn't itself
  /// observed. `matches: null` (not `false`) when either price is
  /// missing, same "don't fabricate a verdict from incomplete evidence"
  /// convention `priceConsistencyCheck` already uses.
  function cartPriceConsistencyCheck(pdpPrice, cartPrice, discountAmount = 0) {
    if (pdpPrice == null || cartPrice == null) {
      return { matches: null, expectedCartPrice: null, pdpPrice, cartPrice, discountAmount };
    }
    const expectedCartPrice = Math.round((pdpPrice - discountAmount) * 100) / 100;
    return {
      matches: Math.abs(expectedCartPrice - cartPrice) < 0.01,
      expectedCartPrice,
      pdpPrice,
      cartPrice,
      discountAmount
    };
  }

  /// Assembles the selector-free subset of this file's own detectors --
  /// technology fingerprint, PDP-vs-visible price consistency, CRO
  /// component classification -- into one snapshot and relays it to the
  /// background worker as `ecommerce.audit.result`, exactly the way
  /// accessibility-audit.js's runAndReportAccessibilityAudit relays
  /// `accessibility.audit.result`: the whole snapshot travels as one
  /// opaque JSON string (`snapshotJSON`) that
  /// Snapzy/Services/Accessibility/EcommerceAuditMapper.swift decodes
  /// app-side, rather than the extension and the app agreeing on a
  /// fully-typed IPC schema per detector. plpCardScan/ecommerceImageAudit/
  /// recommendationsIntelligence need a caller-supplied CSS selector so
  /// they're deliberately left out of this page-wide, no-input snapshot.
  function runAndReportEcommerceAudit() {
    const snapshot = {
      priceConsistencyCheck: priceConsistencyCheck(),
      technologyFingerprint: technologyFingerprint(),
      croComponentClassification: croComponentClassification(),
      shopifyThemeIntelligence: shopifyThemeIntelligence()
    };
    if (typeof chrome === "undefined" || !chrome.runtime || !chrome.runtime.sendMessage) return;
    const tabSessionId = (globalThis.crypto && globalThis.crypto.randomUUID) ? globalThis.crypto.randomUUID() : `${Date.now()}`;
    chrome.runtime.sendMessage({
      kind: "capture.bridge.request",
      type: "ecommerce.audit.result",
      tabSessionId,
      payload: {
        tabSessionId,
        url: location.href,
        snapshotJSON: JSON.stringify(snapshot),
        viewportWidth: window.innerWidth,
        viewportHeight: window.innerHeight
      }
    });
  }

  if (typeof chrome !== "undefined" && chrome.runtime && chrome.runtime.onMessage) {
    chrome.runtime.onMessage.addListener((message) => {
      if (message && message.kind === "capture.ecommerce.audit.trigger") {
        runAndReportEcommerceAudit();
      }
    });
  }

  const api = {
    technologyFingerprint, extractStructuredData, extractPDPData, priceConsistencyCheck, plpCardScan, extractBreadcrumbs,
    imageRatioConsistency, croComponentClassification, ecommerceImageAudit, experimentAwareness, shopifyThemeIntelligence,
    recommendationsIntelligence, cartPriceConsistencyCheck, runAndReportEcommerceAudit
  };

  if (typeof module !== "undefined" && module.exports) {
    module.exports = api;
  } else {
    window.__captureEcommerceIntelligence = api;
  }
})();
