# Offline work in the refresh branch

This describes the local refresh implementation, not a deployed release. See [REFRESH_PLAN.md](REFRESH_PLAN.md) for validation and rollout gates.

## Before entering a school

Sign in and open each scheduled delivery while connected. Each delivery has its own visit records. Opening a visit prepares its classroom expectations on the server and downloads classroom records to this device. The school hub reports whether classroom records are ready on this device or available only while connected. A visit never opened and prepared on this device cannot be assumed available offline.

School contacts and map metadata are included in preparation. This does not download every map or photo file for offline viewing. Keep required maps separately available until media download readiness is implemented.

## Recording work

Classroom status and name changes use Firestore's local write queue. The app distinguishes local confirmation, server acknowledgement, and an unconfirmed write. Rejected classroom changes appear in a Review banner while the app session remains active. That rejection banner is not yet a durable recovery journal across app termination.

Photos and signatures use a separate durable evidence journal. The app saves their files and metadata before starting an upload, and retains local media until the server acknowledges the metadata. Uploads resume when the app can run after restart, reconnect, or returning to the foreground. iOS may suspend work while the app is in the background; continuous background transfer is not promised.

Pending evidence belongs to the account that captured it. Switching accounts does not upload another person's queue. Sign back into the original account to continue its pending uploads.

## Understanding upload status

Tap the evidence status indicator to see pending photos/signatures, retry errors, or pause/resume an upload. “Saved on this device” does not mean another team member can see it yet. A detected network connection does not prove that Firebase can be reached. Retry preserves the queued evidence when Wi-Fi has no usable internet.

The evidence indicator counts photo and signature uploads. It is not a global acknowledgement indicator for every Firestore edit, note, or checklist item.

## Sign-off and corrections

A signature freezes the delivery summary reviewed at capture time. Each signature has its own immutable record and image path; later corrections create another record. A cached or incomplete summary remains marked for review and is never silently promoted to a server-fresh sign-off after reconnection. “Data read” describes when the client read the summary; it is not independent server verification of its truth or a transaction across all source documents.

Visit histories are separate. Legacy school-only records remain available for historical reading/export and are not automatically assigned to a guessed visit.

## Older pending work

The previous app's local queue records are preserved. Photos migrate automatically only when their original account can be established. Unattributed older records remain on the device for review. Administrators can export recoverable older photo files through the upload detail sheet. Do not clear app storage or uninstall the app while unrecovered evidence remains.

## Remaining release checks

Automated tests cover simulated restart/retry, metadata failure, duplicate IDs, account changes, and frozen snapshots. Physical-device tests must still cover app termination, low storage, camera capture, Wi-Fi without internet, connection flapping, two-device changes, and native Storage retry behaviour. Offline preparation time and the performance targets in the plan have not yet been measured on a representative school.
