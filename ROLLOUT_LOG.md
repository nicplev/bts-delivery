# Production rollout log — bts-delivery-app

Changes made to the production Firebase project, newest last. Read-only checks are not listed.

## 2026-11-18 — pre-rollout state and backup

State observed before any change (read-only):
- Firestore rules and Storage rules live in production are identical to commit `d1b2a3d` (the original app source). The new access-model rules are **not** deployed.
- No `staff_access` collection exists. Collections: 15 users, 14 staff, 59 schools, 62 deliveries, 19 signed_school_summaries.
- Live Cloud Functions (1st gen, Node 20, us-central1): `calendar`, `onDeliveryChanged`, `timerAutoStop`.
- Firestore point-in-time recovery off, no backup schedule, delete protection off.
- App Storage bucket: 2,225 files, 1.73 GiB (2,221 under `schools/`, plus a 9 KB Firestore export from 2025-10-09 in `firestore-backup/`).

Changes (approved by the owner):
- Created private bucket `gs://bts-delivery-app-backups` (us-central1, uniform access, public access prevention enforced).
- Firestore managed export of the whole `(default)` database to
  `gs://bts-delivery-app-backups/firestore/2026-11-18-pre-rollout`
  — finished 2026-11-18 09:33 UTC, state SUCCESSFUL, 5,497 documents, 2.39 MB.
  Restore with: `gcloud firestore import gs://bts-delivery-app-backups/firestore/2026-11-18-pre-rollout --project bts-delivery-app`
  (an import overwrites documents with the same ID; it does not delete documents created afterwards).

Storage files were inventoried but not copied. The new rules do not delete files.

## 2026-11-18 — owner's access decisions (no production change)

- Everyone keeps their current role (all 14 legacy staff records say admin); roles can be changed later in the app.
- Nic, Ari and Bill are super admins. Only super admins add, rename, re-role or remove people, create sign-ins and invitations, send password reset emails, turn sign-in off/on and grant super admin. Ordinary admins keep everything else, including allocating staff to schools. Nobody can change their own super admin, sign-in or role; super admins must have that removed before they can be disabled, re-roled or deleted.
- Of the two staff records sharing Helena's sign-in, the one named "Helena" is linked; the other ("helena.scott248") is left unlinked and can be deleted from the app later.
- The two logins with no staff record and no name are not linked, so they cannot use the new app. Their Auth accounts are left in place (not deleted).
- "Beta Admin" keeps access for now.
- Reviewed list: 13 access links, 3 of them super admin. `functions/scripts/seed-staff-access.cjs` checked it against production in check-only mode on 2026-11-18: 13 to create, no problems. The list itself is kept outside the repository.

Not yet done: rules/indexes/Functions deploy, writing the access links, app release.
