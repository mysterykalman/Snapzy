# Reference & Donor Provenance

Capture (this repository, built on the Snapzy foundation) draws on several
other repositories during its migration to a full-featured personal
application. This document tracks, per subsystem, which source was
consulted, its license, and how it was used. Update it whenever code is
reused, adapted, or materially informed by an external/donor repository.

## Repositories

| Repo | Path | License | Status | Usage policy |
|---|---|---|---|---|
| Capture (original) | `~/Documents/GitHub/Capture` | No license chosen yet (`LICENSE` is a placeholder; copyright held by the user) | Read-only donor | Owned by the user — logic may be freely ported/adapted since there is no third-party license to satisfy. Still: don't port weak/superseded implementations (see `docs/STRUCTURE.md` migration notes below). |
| Capso-Capture | `~/Documents/GitHub/Capso-Capture` | Business Source License 1.1. Licensor: `lzhgus`. Licensed Work: "Capso", (c) 2026 lzhgus. Additional Use Grant permits personal use, internal-org use, and use as a component of a product whose primary purpose is not screen capture. | Read-only donor | This is a **third-party-licensed product**, not automatically the user's own IP, despite containing migration work derived from the user's original Capture. Personal use of Capture (this app) is covered by the Additional Use Grant since Capture's primary purpose is screen capture *and* it is for personal, non-commercial use — re-check this clause before any commercial distribution. Treat Capso-Capture as **study + selective adapt** for infrastructure that is clearly a clean rewrite of the user's own original Capture concepts (e.g. BrowserBridgeKit transport), not as a general BSL code source. Do not import Capso-only proprietary features unrelated to the user's original Capture. |
| SnapShotKit | `~/Documents/GitHub/Capture-References/SnapShotKit` | MIT (c) 2026 Bheema Rajulu | Read-only donor | Permissive — may adapt directly. Must retain MIT notice for any file with materially copied code (see "Attribution" below). |
| Snappilot | `~/Documents/GitHub/Capture-References/snappilot` | Claimed MIT via README badge; **no `LICENSE` file present in the repo**. | Read-only donor | Treat as study-only until an explicit LICENSE file is confirmed upstream or the author is asked directly, per the instruction that README wording alone is not sufficient. Do not commit verbatim code from this repo; reimplement ideas (OCR-indexed history) independently. |
| paint-macos | `~/Documents/GitHub/Capture-References/paint-macos` | MIT (c) 2026 Manuel Rizzo | Read-only donor | Permissive — architecture/study reference for drawing tool state machines; Snapzy's own editor is already mature, so this is consulted for ideas, not wholesale replacement. |
| figma-overlay | `~/Documents/GitHub/Capture-References/figma-overlay` | MIT (c) 2023 Pitu | Read-only donor | Permissive — adapt concepts (SVG paste, overlay, opacity, nudge/align) into a native Capture-specific workflow. |
| QuickRecorder | `~/Documents/GitHub/Capture-References/QuickRecorder` | AGPL-3.0 | Read-only donor | **Study only.** No source may be copied or adapted. Used only to understand mature ScreenCaptureKit/recording UX patterns, reimplemented independently. |

## Feature / subsystem provenance log

| Feature / subsystem | Source(s) consulted | License | Reused / Adapted / Study-only | Files materially derived | Attribution required |
|---|---|---|---|---|---|
| CI build artifact pipeline | Capture-Snapzy `ci.yml`, `release-publish.yml` (existing) | N/A (own repo) | Reused pattern | `.github/workflows/dev-artifact.yml` | No |
| BrowserBridge transport (Unix-socket IPC + Chrome Native Messaging framing/protocol) | Capso-Capture `Packages/BrowserBridgeKit` | BSL 1.1 (personal use permitted) | Reused (ported near-verbatim; renamed `Capso`/bundle-ID identifiers to Snapzy equivalents) | `Packages/BrowserBridgeKit/**`, `Snapzy/Services/BrowserBridge/BrowserBridgeCoordinator.swift` | No (BSL has no attribution clause; provenance noted in file header comments) |
| Metadata stripping (EXIF/GPS/IPTC re-encode) | Capture `mac/Sources/CaptureCore/MetadataStripper.swift` | Owned by user (no third-party license) | Reused near-verbatim | `Snapzy/Services/Privacy/MetadataStripper.swift` | No |
| Privacy preflight (email/phone/credit-card/API-key/IP/confidential-term detection) | Capture `mac/Sources/CaptureCore/PrivacyPreflight.swift` | Owned by user | Reused near-verbatim | `Snapzy/Services/Privacy/PrivacyPreflight.swift` | No |
| Smart Redact (OCR-line-based redaction proposals) | Capture `mac/Sources/CaptureCore/SmartRedact.swift` | Owned by user | Adapted (Capture's `Region` wrapper replaced with plain `CGRect`; Snapzy has no equivalent abstraction elsewhere) | `Snapzy/Services/Privacy/SmartRedact.swift` | No |
| Client-safe export preset (OCR scan + metadata strip coordinator) | Capture `mac/Sources/CaptureVision/ClientSafeExportPreparer.swift` | Owned by user | Adapted (Capture's own `TextRecognizer` OCR wrapper replaced with Snapzy's existing, more mature `OCRService` — Snapzy already has a stronger OCR pipeline, so KEEP SNAPZY applied here rather than porting a redundant one) | `Snapzy/Services/Privacy/ClientSafeExportPreparer.swift` | No |
| PDF export (multi-page, password/permissions, tall-image pagination) | Capture `mac/Sources/CapturePDF/PDFExport.swift` | Owned by user | Reused near-verbatim | `Snapzy/Services/Export/PDFExport.swift` | No |
| PDF permanent redaction (rasterize targeted page, re-embed others as vector) | Capture `mac/Sources/CapturePDF/PDFRedactor.swift` | Owned by user | Reused near-verbatim | `Snapzy/Services/Export/PDFRedactor.swift` | No |
| Contact sheet generator (grid/vertical/horizontal layouts) | Capture `mac/Sources/CaptureCore/ContactSheetGenerator.swift` | Owned by user | Adapted (Capture's `ColorHex` helper replaced with Snapzy's existing `SnapzyConfigurationColor`) | `Snapzy/Services/Export/ContactSheetGenerator.swift` | No |
| WCAG contrast checker (ratio/level/suggest-compliant-color) | Capture `mac/Sources/CaptureCore/ContrastChecker.swift` | Owned by user | Reused near-verbatim | `Snapzy/Services/Accessibility/ContrastChecker.swift` | No |

_(Rows are added as each subsystem migration lands; see individual PR/commit messages for detail.)_

## Attribution requirements

- **MIT-licensed sources** (SnapShotKit, paint-macos, figma-overlay): when a file contains code materially copied or closely adapted from one of these, add a header comment naming the source repo, author, and license, and keep a copy of the applicable license text reachable from this document (this file serves as the central NOTICE index; do not scatter separate LICENSE copies unless a file is copied wholesale into its own module).
- **BSL-licensed source (Capso-Capture)**: no attribution requirement under BSL beyond retaining copyright headers if literal text is copied; prefer treating it as an architecture reference and reimplementing rather than copying verbatim, to avoid ambiguity about BSL scope creep into a personal product that may later be shared.
- **AGPL source (QuickRecorder)**: never copied; nothing to attribute.
- **Original Capture**: owned by the user; no external attribution needed.

## Open questions / decisions log

- Snappilot's actual license is unconfirmed (README badge only, no LICENSE file). Decision: treat as study-only pending confirmation.
- Capso-Capture's BSL Additional Use Grant covers personal/internal use of a screen-capture product; this is compatible with Capture's use here as a personal daily-use application. If Capture is ever distributed to others or commercialized, this clause must be re-reviewed.
