# BTS Delivery — main-flow UI concepts

17 November 2026. Nine concept screens across three boards, generated with the built-in image generation tool and reviewed with Astra. These are synthetic design illustrations, not running-app screenshots or a production specification.

## Final boards

- [Delivery recording](01-delivery-recording.png): today's visits → school visit → classroom quantities and evidence.
- [Offline recovery](02-offline-recovery.png): prepare files → continue offline → review conflicting edits and retry uploads.
- [Review and sign-off](03-review-signoff.png): outstanding quantities → signature with visible totals → retained signed record.

## Visual direction

Quiet grouped surfaces, generous spacing, clear text hierarchy, fewer competing actions, and explicit labels alongside status icons. The app's brand colours remain green #2BB673, blue #00AEEF, pink #EC008C and yellow #F9ED32. Use those exact tokens in implementation; generated artwork is illustrative and may vary in pixel colour.

Green identifies primary actions, blue navigation, pink evidence and yellow attention. Offline status is separate from light/dark appearance. Signing retains outstanding quantities rather than declaring the delivery complete.

## Sources

- Supplied Apple Design System PDF: /tmp/codex-remote-attachments/01a1e26d-c2b6-7022-9636-994f38618886/F2C63966-208E-4FE1-81ED-FC911CD7F894/1-Apple-Design-System.pdf
- [Apple HIG: Designing for iOS](https://developer.apple.com/design/human-interface-guidelines/designing-for-ios)
- [Apple HIG: Layout](https://developer.apple.com/design/human-interface-guidelines/layout)
- [Apple HIG: Color](https://developer.apple.com/design/human-interface-guidelines/color)
- Existing brand tokens: lib/app/theme/brand_colors.dart
- Existing implementation plan: UI_OVERHAUL_PLAN.md

The supplied PDF is an independently compiled reference, not an Apple publication. These concepts use original layouts and synthetic content. They do not establish App Store approval.

## Before implementation

- Validate text contrast, scalable text, screen reader labels and touch targets in real widgets. Bright brand blue/green may need darker text variants; do not copy raster text colours blindly.
- Preserve the existing detailed final-review safeguards: show the complete delivery snapshot and exceptions before committing a signature. The board compresses this flow for presentation.
- A server-saved label must require actual server acknowledgement; otherwise show saved locally or pending.
- Use precise file-download wording in place of the abbreviated “Files saved” label.
- Match controls and icons consistently across all screens. Support dark appearance separately from connectivity.
- Original drafts are retained under drafts/. Prompts are in PROMPTS.md and REFINEMENT_PROMPTS.md.

