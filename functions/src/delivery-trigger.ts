import * as functions from "firebase-functions";
import * as admin from "firebase-admin";
import {FieldValue, Timestamp} from "firebase-admin/firestore";

export function changedSchoolIds(before: unknown, after: unknown): string[] {
  return [...new Set([before, after].filter((id): id is string =>
    typeof id === "string" && id.length > 0 && !id.includes("/")))];
}

export const onDeliveryChange = functions.firestore
  .document("deliveries/{deliveryId}")
  .onWrite(async (change, context) => {
    const before = change.before.data();
    const after = change.after.data();
    const changeType = !before ? "created" : !after ? "deleted" : "updated";
    const db = admin.firestore();
    const timestamp = Timestamp.fromDate(new Date(context.timestamp));

    const staff = db.collection("staff");
    const schools = changedSchoolIds(before?.schoolId, after?.schoolId);
    const queries = [staff.where("role", "in", ["admin", "manager"])];
    if (schools.length > 0) {
      queries.push(staff.where("assignedSchoolIds", "array-contains-any", schools));
    }
    const snapshots = await Promise.all(queries.map((query) => query.get()));
    const affected = new Set(snapshots.flatMap((snapshot) => snapshot.docs.map((doc) => doc.id)));

    const system = db.collection("system_metadata").doc("calendar_last_updated");
    await db.runTransaction(async (tx) => {
      const prior = (await tx.get(system)).get("lastUpdated");
      if (prior && prior.toMillis() > timestamp.toMillis()) return;
      tx.set(system, {lastUpdated: timestamp, changeType}, {merge: true});
    });

    // Only subscriptions already in use need per-staff change notifications.
    const ids = [...affected];
    for (let offset = 0; offset < ids.length; offset += 400) {
      const refs = ids.slice(offset, offset + 400)
        .map((id) => db.collection("calendar_metadata").doc(id));
      await db.runTransaction(async (tx) => {
        const docs = await tx.getAll(...refs);
        for (const doc of docs) {
          const prior = doc.get("lastDeliveryChange");
          if (doc.get("subscriptionActive") === true &&
              (!prior || prior.toMillis() <= timestamp.toMillis())) {
            tx.update(doc.ref, {
              lastDeliveryChange: timestamp,
              token: FieldValue.delete(),
            });
          }
        }
      });
    }
    return null;
  });
