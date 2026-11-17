# Offline work in the refresh branch

This describes the local refresh implementation, not a deployed release. See [REFRESH_PLAN.md](REFRESH_PLAN.md) for validation and rollout gates.

## Prepare a visit before entering a school

Sign in and open each scheduled delivery while connected. Each delivery has its own quantities, progress, notes, timers, photos and sign-offs. The school hub distinguishes classroom records ready on this device from records available only while connected. A visit never prepared on this device/account cannot be assumed available offline.

Record readiness and media readiness are separate. Use **Offline media → Download for offline** to save the school map and the classroom photos found during that check. Keep the app open until the download status confirms completion. Newly added team photos are included when you check and download again.

## Maps, PDFs and photos

Downloaded images and PDFs open from the device without first requesting a download URL. Each copy belongs to the account and visit that downloaded it. The app checks file integrity on reopening, reports missing/damaged files, and publishes only fully verified downloads.

Maps can change. Their saved date describes the last successful check, not proof that the school has made no later changes. A failed replacement download retains the previous copy. **Open previously saved map** clearly identifies that older file. Current map readiness does not count it as the replacement.

Downloads use authenticated references in the configured Firebase Storage bucket. Unsupported external links are not included. The limits are 25 MiB per file and 200 MiB for this app's downloaded media across all accounts on this device. Media discovery is bounded to 500 files and 400 classrooms per visit; oversized inventories report a failure instead of claiming readiness.

You can cancel/retry downloads or remove downloaded copies. **Clear downloaded media on this device** removes downloaded copies for all accounts after confirmation, including damaged or inaccessible old copies. It does not remove delivery records, drafts, unsent edits, pending uploads or remote signed evidence. If the native download cannot stop, the app explains that reopening may be required before clearing or retrying.

## Drafts and field edits

Common classroom forms preserve drafts by account, visit and record: names, notes, pack counts, status and actual consumable quantities. Close or Back preserves the draft; **Discard draft** removes only that draft. It does not cancel a change already submitted to Firestore.

“Saving draft…” means the latest text is not yet confirmed on disk. A force-quit during that short interval may lose those newest keystrokes. “Draft saved on this device” confirms the stored revision. If local storage fails, the form retains the input and reports the failure.

Core field saves first retain a durable copy of the intended edit and then submit it. Feedback distinguishes server-confirmed, locally queued and saved-for-review states. Note/count changes and their classroom audit metadata are submitted together. The loading checklist also retains save state instead of closing before an uncertain network operation finishes.

## Reviewing an interrupted or rejected edit

The **Saved edits** banner survives reopening the app. It includes core classroom rename/status edits, note creation/editing/deletion, actual consumable quantities, pack-count additions and loading-checklist marks.

A restart compares retained edits with current server values; it does not automatically reapply an older edit. Review shows what you saved alongside current values. If the native Firestore queue is still handling the original write, wait for it to finish. When an explicit retry is possible, the app checks again that the record has not changed since review. A deleted record is not silently recreated. Notes use stable identifiers to avoid duplicate creation after an interrupted Save.

A matching current server value is reported as a match, not proof of which device wrote it. Clearing the retained copy requires a current comparison. Original queued writes cannot be cancelled by dismissing the review screen.

Template/configuration editing, administrative imports and unused school-note APIs are outside this durable field-edit slice and still need their separate interaction review.

## Photos and signatures awaiting upload

Captured photos and signatures have a separate durable evidence journal. Files and metadata are saved before upload; local media remains until the server acknowledges its metadata. Uploads resume when the app can run after restart, reconnect or foreground entry. iOS may suspend background work; continuous background transfer is not promised.

Pending evidence remains bound to the account that captured it. Switching accounts does not upload another person's queue. Sign into the original account to continue its work. Tap the evidence indicator to inspect, retry, pause or resume pending uploads.

A detected network connection does not prove that Firebase is reachable. “Saved on this device” does not mean other staff can see it yet. The evidence indicator counts photo/signature uploads; ordinary edits have their own recovery state.

## Sign-off and historical evidence

A signature freezes the summary reviewed at capture time. Each signature has its own immutable record and image path. Corrections append another record. Cached or incomplete summaries stay marked for review and are never silently promoted to server-fresh sign-offs.

“Data read” describes a client read, not independent verification or a transaction across every source document. Removing a photo from the live classroom retains its stored image so earlier signed records keep their original evidence. Historical school-only records are not assigned to guessed visits.

## Older pending work

Previous-version queue records remain preserved. Photos migrate only when their originating account can be established. Unknown-owner records remain on the device for review; administrators can export recoverable older photos from the evidence upload sheet. Do not uninstall or clear all app storage while unrecovered work remains.

## Release checks

Automated and simulator evidence is recorded in the plan. Physical-device checks must still cover low storage, camera capture, real reception dropouts, connection flapping and two-device work. Performance targets remain unmeasured on representative schools. Cached permission information can only learn about assignment revocation after reconnection.
