# Capture-Snapzy — Product Completeness Audit

**Date:** 2026-09-15
**Method:** Full read of `~/Documents/GitHub/Capture/docs/SPEC_DIGEST.md` (the master Capture spec digest), cross-referenced against the actual current `Snapzy/` source (grep + direct file reads, not filename guessing), via 11 parallel research passes covering every numbered spec section (§2.1–2.28, §3.x, §4). This document is the working checklist for closing the highest-value gaps; see `docs/REFERENCE_PROVENANCE.md` for licensing/provenance of what's already been ported.

**Classification key:**
- **A** — already complete
- **B** — partially complete (real code exists, meaningfully incomplete)
- **C** — missing but high value
- **D** — missing but low value / polish
- **E** — intentionally superseded by a different/stronger Snapzy-native implementation
- **F** — blocked by environment/credentials/manual QA (e.g. needs a real live Chrome session)

## Headline findings

1. **Two subsystems built entirely this session had zero UI consumers until just now**: the full visual-diff/baseline module (`ImageDiff`/`BaselineStore`/`PageLayoutDiff`/`ElementDiff`/`MultiElementComparison` — 4 commits) and `AuditReport`'s Markdown/HTML/PDF export. Both are now being wired in as part of this pass.
2. **The browser-inspector "flagship differentiator" (§2.14, spec's own words) has strong backend but zero presentation UI.** No hover card, forensic card, DOM navigation, live-edit, or multi-select comparison view exists anywhere in `Snapzy/Features/`. This is the single largest gap in the whole audit, but building the full interactive live-Chrome UI is also the least verifiable in this environment (no live browser session available) — treated as a longer-horizon item, tackled incrementally.
3. **No Capture Tray / multi-capture assembly system exists at all** (§2.5, spec's own words: "first-class core workflow"). `ContactSheetGenerator.swift` is fully implemented and tested but has zero UI callers — dead code.
4. **No Universal Snap Engine exists** (§2.3) — three separate, independent snap implementations exist (crop-edge, combine-canvas, text-highlighter), none shared, and capture-region selection has no snapping at all.
5. **The Browser Bookmarks Bar Privacy Rule is entirely unimplemented** (§2.4) despite being explicitly flagged in the spec as a **hard requirement**.
6. **No Command Palette exists.** ⇧⌘K is already taken by a read-only shortcut cheat-sheet, not a searchable/executable palette.
7. Of the spec's 22 named global shortcut actions, **5 have no bindable global shortcut at all** (Capture Tray add/open, Delayed Capture, Toggle Inspect Mode, Command Palette), and Pin Last Capture only works via a hover-scoped shortcut, not a true global one.
8. Several ecommerce-intelligence JS functions (`shopifyThemeIntelligence`, `plpCardScan`, `recommendationsIntelligence`, `ecommerceImageAudit`) are fully implemented and tested in JS but have **no Swift mapper and are never included in the snapshot sent to the app** — same "orphaned feature" pattern as #1.
9. `InspectionResultsView` stores CRO `componentDetections` but never renders them — a one-line-of-value wiring gap.

## Full classified inventory (condensed)

### §2.1–2.2 Capture Engine + Area↔Window flow
| Item | Class | Notes |
|---|---|---|
| Area capture core (crosshair, live dims, loupe) | A | `AreaSelectionWindow.swift`, `AreaSelectionMagnifier.swift` |
| Area capture precision (ratio lock, presets, snap-to-window/content, numeric x/y/w/h entry) | C | None of these exist |
| Frozen Area | A | `FrozenAreaCaptureSession.swift` |
| Window capture (shadow toggle, desktop-icon exclusion) | B | Shadow is a global pref, not per-capture Option-click override (see below) |
| Window capture (transparent-outside-window / custom live Backdrop) | E | Snapzy does backdrop compositing post-capture via Annotate/Mockup instead |
| Full Screen (display/all-displays/cursor) | A | `ScreenCaptureManager.swift` |
| Full Screen HDR/SDR toggle | C | Only a fixed SDR color-space path exists |
| Repeat Area (single unnamed slot) | B | `ScreenshotLastAreaStore.swift` — one rect only |
| **Named Repeat Regions** | **C** | Entirely missing |
| Element Capture (browser-bridge DOM bounding box + padding) | C | `SmartElementCaptureController` is AX/pixel-based, not DOM-based; no bridge message type for it |
| Full Page Browser Capture (DOM-aware mode) | C | Only pixel-based Scrolling Capture exists |
| Scrolling Capture (vertical/auto/manual/max-height/sticky-suppress) | B | Mature; missing horizontal/free-pan, user-adjustable scroll speed, true tiled rendering |
| Measured Capture (live-size drag baked into output) | E | `PixelMeterOverlay` ruler is a different, standalone tool, and per its own provenance note isn't wired to any shortcut yet |
| Multi-region Capture (one session, N regions) | E | Superseded by post-hoc History multi-select export |
| **Timed/Delayed Capture** (countdown, repeat-N-seconds, burst) | **C** | Entirely missing |
| **Stable/Browser-stabilized Capture** (disable animations, wait for network-idle) | **C** | Entirely missing |
| Cursor as editable object | B | Only none/baked exist; no editable cursor object |
| Capture presets (bundle mode+cursor+destination+naming+retention) | B | Only Annotate-canvas-level presets exist, not full-workflow presets |
| **Capture metadata sidecar** (sourceApp/url/viewport/DPR/scroll/etc.) | **C** | Entirely missing for screenshots |
| Area↔Window in-flow toggle (mechanism) | A | Real, robust — default key is "A" not literally Space (remappable) |
| **Option-click capture-without-shadow** | **C** | `WindowShadowPreference` exists globally; no per-click modifier override — small, well-scoped fix |

### §2.3–2.4 Snap Engine & Bookmarks Bar Privacy
| Item | Class | Notes |
|---|---|---|
| **Universal Snap Engine** (shared subsystem) | **C** | Three separate unrelated implementations; capture-region selection has zero snapping |
| Crop-edge snapping | A | `CropEdgeSnapping.swift`, real pixel-content-edge detection |
| Snap settings UI (per-target checkboxes, tolerance slider, disable modifier) | C | Only two plain on/off toggles exist |
| **Browser Bookmarks Bar Privacy Rule** (hard requirement) | **C** | Zero implementation — no detection, no redaction style, no settings |

### §2.5–2.6 Multi-Capture/Assembly & Crop
| Item | Class | Notes |
|---|---|---|
| **Capture Tray** (persistent, add/reorder/assemble) | **C** | Entirely absent — "first-class core workflow" per spec |
| **Assembly layouts** (Grid/Comparison/Before-After/Responsive Strip) | **C** | Absent; only freeform-canvas + single-row/column "Combine Images" exists |
| **Contact Sheet generation UI** | **C** (quick win) | `ContactSheetGenerator.swift` fully built & tested, zero UI callers |
| Crop to Object (pixel edge detection) | A | `CropContentAnalyzer.swift`, wired with shortcut |
| Crop to DOM Element | C | Foundation (`ElementEvidence`) exists but never connected to crop tool |
| Crop precision (custom ratio entry, numeric x/y/w/h, reset-to-source) | C | Only fixed presets exist |

### §2.8–2.9 Editor/Annotation + §3.14
| Item | Class | Notes |
|---|---|---|
| Core annotation set (arrow/rect/ellipse/text/freehand/highlighter/spotlight/blur/watermark) | A | Full, real implementations |
| Counter annotation formats (A,B,C / roman / custom start / auto-renumber) | B → mostly closed | Numeric/alphabetic/Roman styles + custom start value implemented (`CounterNumberingStyle`, quick properties bar picker). Auto-renumber-on-delete deliberately deferred: it would silently change other counters' displayed values whenever one is removed, a bigger UX/undo-semantics decision than this pass, not just a rendering change. |
| **Stamps** (check/X/warning/bug/CRO) | **C** | Entirely missing, high value given Inspection Results feature exists |
| **Measurement annotation tool** | **C** | No measurement/ruler/guide object exists in the editor at all |
| Group/ungroup, lock, hide, explicit z-order, align, distribute | C | None of these exist on annotation objects |
| Tiled rendering for huge scrolling images | C | No `CATiledLayer`/chunked decode anywhere — real memory-safety gap for very tall captures |
| Loupe/Magnifier as persistent annotation object | E | Capture-time loupe exists instead; not a canvas object |

### §2.26 Export/Share
| Item | Class | Notes |
|---|---|---|
| PDF/PPTX export + History bulk-export menu | A | Fixed this session |
| **`AuditReport` Markdown/HTML export UI wiring** | **C** (quick win) | Fully built & tested, zero UI callers |
| Export format coverage (HEIF/AVIF/TIFF) | C | Only PNG/JPEG/WebP export |
| Native Share sheet | A | Real, wired |
| S3/R2 cloud upload | A | Substantial, exceeds spec's "optional" bar |
| Named export presets (Slack/Client Deck/Jira/Audit PDF) | C | Not implemented |

### §2.10 Screen Recording
| Item | Class | Notes |
|---|---|---|
| Core pipeline (ScreenCaptureKit/AVAssetWriter, screen+mic+system-audio tracks) | A | Mature |
| Cursor/click/keystroke as **structured, editable** sidecar tracks | C | Baked into pixels at record time, contradicting spec's own "don't bake in" principle; cursor-position data exists but only feeds auto-zoom |
| Post-record cuts/split/freeze-frame | C | Not in `VideoEditorState`'s `EditorAction` enum at all |
| Post-record cursor-treatment/click-halo editing | C | Not possible since effects are baked in |
| Low-disk warnings, smart typing compression, captions/transcription | C | None implemented |
| Trim/speed/manual-zoom/GIF export/Backdrop | A | Solid |

### §2.14–2.18 Browser Inspector / Typography / Colour / Assets / Responsive (the "flagship differentiator")
| Item | Class | Notes |
|---|---|---|
| Locator strategy + `ElementEvidence` schema | A | Complete, matches spec's 8-strategy priority order exactly |
| Hover card / forensic card / DOM navigation / live-edit UI | **C — largest single gap in the audit** | Zero UI; data model + diff engine (`ElementDiff`, `MultiElementComparison`, `PageLayoutDiff`) is real and often exceeds spec, but nothing shows it live over a hovered element |
| Multi-select inspection ("11 of 12 use radius 8px") | B | `MultiElementComparison.swift` implements this exactly, unreachable from any UI |
| Typography inspector (rendered font, fallback, variable axes, OpenType) | B | JS collection real & tested; zero UI |
| Colour/design-token inspector (page-wide inventory, token detection, gradients/shadows structured) | C | Only raw CSS strings captured, no structured parsing/UI |
| Asset Inspector (image hover card, upscaling warnings, SVG/icon ID) | C | No dedicated asset-inspection content script exists at all |
| Responsive/State Lab (multi-viewport panes, breakpoint auto-discovery) | C | Entirely absent; diff *modes* to consume it already exist (`ImageDiff`, `PageLayoutDiff`) |
| Manifest permission model (`<all_urls>` host permission, always-injected content scripts) | B | Spec wants active-tab/on-demand injection only — real hardening gap |

### §2.19–2.21 Accessibility / Performance-SEO / Ecommerce
| Item | Class | Notes |
|---|---|---|
| Accessibility audit (heading/landmarks/images/links/forms/dup-id/lang/tabindex) | A/B | Solid hand-rolled rule set, real and tested |
| Automated WCAG-2.2-mapped audit (axe-core-style), APCA score | C | Not built; APCA explicitly deferred with documented rationale |
| Focus order overlay, keyboard journey recorder, vision simulation, motion inspection | C | None implemented |
| **Core Web Vitals / performance module** | **C** | Completely greenfield — zero code either language |
| **SEO/page metadata card + social preview** | **C** | Completely greenfield |
| Technology fingerprinting | A | 15 real detectors, confidence+signals, tested |
| **CRO component detections wiring into `InspectionResultsView`** | **C (quick win)** | Data already flows end-to-end via `EcommerceAuditMapper`, view just never renders it |
| Shopify theme intelligence / PLP scanner / recommendations intelligence / ecommerce image audit — Swift mappers | C | All real & tested in JS, **never included in the snapshot sent to the app at all** |

### §2.22 Visual Diff and Baselines
| Item | Class | Notes |
|---|---|---|
| Diff engine (pixel/perceptual/layout/content/element/style-property modes) | A | Fully built this session, exceeds spec in places |
| **UI to actually use any of it** | **C (highest-value quick-ish win)** | Zero UI consumers anywhere — `BaselineStore`, `ImageDiff`, `PageLayoutDiff` etc. are all unreachable |
| Blink/heatmap comparison views | D | Missing from `ImageDiff` itself; low priority until base UI exists |
| Figma/design overlay | A | Native `FigmaOverlayManager`, built this session |

### §2.23–2.25 History/Projects/Search & Documentation/Audit Mode
| Item | Class | Notes |
|---|---|---|
| History + OCR full-text search | A | Built this session |
| Search by URL/domain/page-title/source-app/tag/viewport/technology | C | None of this metadata is captured onto history records at all |
| FTS5 full-text index | B | Current search is an in-memory substring scan, functionally fine at small scale but not the specified engine |
| Content-addressed (SHA256) dedupe | C | Not implemented |
| **Capture blackout list** (exclude apps/domains from history/OCR/cloud) | **C** | Real privacy gap; only Snapzy's-own-window exclusion exists, nothing for password managers/banking apps |
| Projects/Sessions grouping, `.capture` package format | E | Deliberately simpler flat History + SQLite model instead — a real product decision, not an oversight |
| Audit Finding data model | A | Complete, matches spec fields verbatim |
| Audit board views (page/category/severity/status) | B | Only severity grouping exists |
| **Step Recorder** (Snagit-style numbered workflow capture) | **C** | Entirely absent — single largest gap in this cluster |
| Developer handoff export (Markdown/HTML/PDF) | A (once wired) | `AuditReport.swift` — see quick win above |

### §2.27–2.28, §4 UI Architecture / Permissions / Shortcuts
| Item | Class | Notes |
|---|---|---|
| Remappable shortcuts UI + conflict detection | A | Solid, real, exceeds spec in places |
| 19 of 22 spec shortcut actions bindable | A | — |
| **Command Palette** | **C** | Does not exist in any form |
| **Capture Tray shortcuts, Delayed Capture shortcut, Toggle Inspect Mode shortcut** | **C** | No bindable action exists since the underlying features don't exist |
| Pin Last Capture as a true global shortcut | B | Only hover-scoped via Quick Access today |
| Quick Access Overlay | B | Real and feature-rich; missing OCR action and native-Share action from its card |
| Progressive permissions | B | Mostly lazy-request, but onboarding also offers Screen Recording/Accessibility upfront (hybrid, not a strict violation) |

## Priority order for implementation (this pass)

Per explicit instruction: functional workflows over decorative polish, C items and important B items before D-level polish (Help/changelog explicitly deferred). Ordering by value ÷ effort, each its own CI-verified commit:

1. **Quick wins** (data already exists, pure wiring): CRO component detections in `InspectionResultsView`; `AuditReport` Markdown/HTML export button; Contact Sheet UI entry point.
2. **Visual diff/Baseline UI** — the biggest "backend built, nothing shows it" gap; makes 4 prior commits' worth of work actually usable.
3. **Ecommerce Swift mappers** for the JS functions already tested but never wired (`shopifyThemeIntelligence` first — selector-free, easiest).
4. **Delayed/Timed Capture** — self-contained, no dependencies, real spec-named gap.
5. **Option-click capture-without-shadow** — small, well-scoped, reuses existing `WindowShadowPreference`.
6. **Capture blackout list** -- investigated and deliberately deferred: accurate enforcement needs to know which app was actually captured, but `CaptureContext` (the type that already resolves `appName` at capture time) is never threaded into `PostCaptureActionHandler`/`CaptureHistoryStore.addCapture` today. By the time those run, the frontmost app has often already changed back to Snapzy itself, so checking "frontmost app" there would silently misidentify almost every capture. Doing this correctly means adding a `sourceAppName` parameter through every `handleScreenshotCapture(s)`/`addCapture` call site across the whole capture pipeline (fullscreen/area/window/scrolling/recording) -- a real, wider change that deserves its own careful, individually-verified pass rather than a rushed one bundled into this session's remaining budget. Left for a follow-up.
7. **Command Palette** — self-contained, high value per spec's own framing as the toolbar "release valve."
8. Continue down the list as time/session budget allows; Capture Tray/Assembly, Universal Snap Engine, and Bookmarks Bar Privacy are the largest remaining C items and will be tackled as scoped MVPs, documented honestly per item if reduced in scope.

Help/What's New/changelog UI is explicitly deferred until this list is substantially worked through, per instruction.
