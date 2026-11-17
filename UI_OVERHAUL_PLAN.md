# BTS Delivery UI overhaul plan

17 November 2026. Baseline: b54ab2a. Astra reviews; Sol 6.1 implements. The user authorised implementation after saving this plan. Preserve all four company colours, delivery visit isolation, existing offline recovery, evidence and final sign-off review.

## Direction and references

Create a calm, familiar iPhone experience with original BTS layouts. Prioritise finding a classroom, recording quantities, understanding saved/pending work and completing an accurate sign-off. Keep the recent card simplification; improve the underlying hierarchy and task structure.

The supplied 57-page Apple Design System PDF (exported 29 October 2026) identifies itself on pages 1 and 57 as an independently compiled Claude Design System artifact, not an Apple publication. Its semantic colours, scalable type, grouped lists and restrained navigation materials are useful references. Kit dimensions, React/CSS recipes and claimed version details are not universal implementation requirements. Apple kit artwork must not be bundled into this app.

Current official references reviewed:

- [Designing for iOS](https://developer.apple.com/design/human-interface-guidelines/designing-for-ios): focus on primary tasks and adapt to system preferences.
- [Color](https://developer.apple.com/design/human-interface-guidelines/color) and [Typography](https://developer.apple.com/design/human-interface-guidelines/typography): preserve branding through adaptive semantic colours and a legible hierarchy.
- [Materials](https://developer.apple.com/design/human-interface-guidelines/materials): keep Liquid Glass out of content; use custom effects sparingly. Opaque records and forms remain the default.
- [Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility): 44 pt default controls and ideally at least 200% text enlargement. The current HIG table also lists a 28 pt minimum; BTS deliberately targets 44–48 for field work.
- [Dark Mode](https://developer.apple.com/design/human-interface-guidelines/dark-mode): follow system appearance by default. Do not treat the PDF's absolute wording as an App Store rejection rule.
- [Tab bars](https://developer.apple.com/design/human-interface-guidelines/tab-bars), [Scroll views](https://developer.apple.com/design/human-interface-guidelines/scroll-views), [Sheets](https://developer.apple.com/design/human-interface-guidelines/sheets): clear destinations, predictable scrolling, scoped forms.
- [App Review guidelines](https://developer.apple.com/app-store/review/guidelines/): native conventions are appropriate; copying another app's identity or assets is different. Approval also depends on completeness and functionality.
- [Apple Design Resources licence](https://developer.apple.com/support/downloads/terms/apple-design-resources/Apple-Design-Resources-License-20230621-English.pdf): kit assets are for permitted mockups, not embedding in software. Font and symbol permissions are separate.

## Current findings

- AppTokens uses fixed light surfaces/text and AppTheme.darkTheme returns lightTheme.
- Too many bold, tightly tracked headings compete with operational body text at 15–16 pt.
- Address, readiness, files and timer push the visit's primary task down the page.
- Calendar view and calendar settings use ambiguous competing affordances.
- Packs expectations, actual quantities and status are split across multiple groups.
- Sign-off mixes a long review and handwriting; current shortcut and field semantics work. User confirmed on 17 November that manual simulator scrolling works normally. A focused capture view is a usability improvement, not a fix for an established scroll lock.
- Records readiness, downloaded media, saved edits and uploads are separate facts; never conceal them in one misleading Synced label.

## Visual system

Keep green #2BB673, blue #00AEEF, pink #EC008C and yellow #F9ED32 as exact brand constants. Use semantic adaptive values for canvas, surfaces, text, separators and state. Preserve readable brand shades. Use green for prominent actions with tested label contrast, blue for navigation, and restrained pink/yellow accents. Error/destructive treatments must be explicit and consistent, with icon/text; native destructive controls may use system red without changing the brand palette.

Use system-appropriate typography, around 17 pt operational body, 17–20 pt semibold section titles and 13–15 pt secondary metadata. Avoid aggressive negative tracking. Begin with 16–20 pt gutters, a 4/8 pt spacing rhythm and consistent group corners. Prefer one surface per task, grouped rows and separators over nested panels. These are product starting values, not copied kit specifications.

Use short functional transitions and press states; respect reduced motion. Real light/dark/high-contrast variants must include startup, error, dialogs and media/recovery surfaces. Signature ink stays black on a deliberate white canvas.

## Screens and flows

### Deliveries

Retain Deliveries, Schools and Profile, with Today/Calendar inside Deliveries. Keep navigation predictable and evaluate retaining each tab's place without leaking account state. Today shows date/count, school, schedule/logistics, instructions and one primary Open school action plus checklist status. Rename calendar settings/subscription affordance so it cannot be mistaken for Calendar view.

### Visit and classroom

Keep school and immutable visit context visible. Move full address to Info. Condense normal readiness/download/timer presentation while keeping pending/errors and active timer actions visible. Details may open a sheet; records, media, edits and uploads remain separately labelled.

Create one Packs section with expected quantity, actual recorded quantity and explicit pack completion state. Do not equate pack completion with all classroom work. Follow with consistent Consumables, Photos and Notes groups. Expectation editing remains role-appropriate and distinct from recording a delivery. A Next classroom action, if implemented, names its destination and never writes/completes implicitly.

### Sign-off

Prototype review followed by a focused capture view. Review shows expected/recorded outcomes, notes, exceptions and missing data. Empty notes must be explicit or disappear only after successful loading; failures cannot look empty.

Capture includes visit identity, Name, white handwriting canvas, Clear, Back to review and Review and save. Preserve name/strokes when returning to review. Keep the existing final server/snapshot review before persistence and re-review changed data. Preserve pending evidence, corrections and history. Reuse existing app-owned persistence and scope; do not create a second queue. Target one vertical scroll owner per destination, with drawing only inside the canvas.

### Offline and supporting screens

Keep truthful Saved on this device, Waiting to upload, Needs review and Download incomplete states. Connection does not prove server acknowledgement. Recovery actions remain reachable. Apply grouped forms and adaptive colours to Info, Schools, Profile, auth, admin and media viewers without weakening validation, role scope or drafts. Wide layouts should use useful columns rather than importing desktop-only kit controls.

## Implementation checklist

- [x] Review HIG, supplied PDF, existing screens and independent Astra recommendations.
- [x] Recover disk space and save the plan before implementation.
- [ ] Produce a coordinated prototype: Today, visit/classroom and sign-off review/capture, with offline, dark and large-text variants; Astra reviews before production changes.
- [ ] Implement adaptive semantic colours, typography and shared components, including real dark/high-contrast modes and isolated accessibility semantics.
- [ ] Simplify daily navigation, visit context and classroom Packs work.
- [ ] Implement and validate focused sign-off capture with retained draft and final review safeguards.
- [ ] Apply the system to secondary forms, recovery and media states; inspect remaining exceptions.
- [ ] Run meaningful route/state tests, combined suite/analyzer, native build and visual walkthrough.
- [ ] Complete physical-device, two-device, representative performance and release acceptance separately.

Retain Flutter/Firebase. Cupertino/adaptive widgets can improve iOS interaction, but Flutter does not automatically inherit native Liquid Glass behaviour. No speculative native bridge, heavy blur dependency or SwiftUI rewrite is planned. Implement bounded slices and keep app data contracts unchanged.

## Acceptance

- At default text on a 390×844 reference screen, task content appears without scrolling past a full viewport of utilities; allow documented long-name/accessibility exceptions.
- Frequent controls have at least 44×44 logical-point hit areas, preferably 48. Labels grow/stack rather than shrink.
- Check 200% text, largest supported accessibility text, VoiceOver order, light/dark/high contrast, reduced motion/transparency and real keyboard clearance.
- Exercise actual finger scrolling and handwriting, return-to-review retention, correction cancellation and sign-off data changes.
- Preserve two-visit isolation, account ownership, drafts and pending work through rejected writes, restart, reconnect and media failures. No acknowledged work lost or duplicate operation after retry.
- Re-run the 84-test baseline and relevant new tests, analyzer, screenshots and native build. User-confirmed current scrolling does not validate a replacement screen.
- Record before/after performance on representative hardware/data; use the refresh interval as a frame budget (16.7 ms at 60 Hz, 8.3 ms at 120 Hz), and preserve the existing 250 ms local-save feedback target. Do not claim unmeasured improvements.
- Existing migration, security, rollout and physical-device gates in REFRESH_PLAN.md remain open until their own evidence exists. No automatic production deployment.

## Work journal

17 November: removed this task's regenerable 6.9 GB Xcode derived data and PDF preview images. User explicitly approved removal of the separate lumi_reading_tracker (8.4 GB) and parent-signup (4.3 GB) Xcode derived-data caches. Source projects, simulator data, supplied PDF and prior evidence exports are retained.
