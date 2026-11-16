import * as functions from "firebase-functions";
import * as admin from "firebase-admin";

/**
 * Firestore trigger that runs when a delivery is created, updated, or deleted
 * This helps track calendar changes and can be used for notifications
 */
export const onDeliveryChange = functions.firestore
  .document("deliveries/{deliveryId}")
  .onWrite(async (change, context) => {
    const deliveryId = context.params.deliveryId;
    const before = change.before.exists ? change.before.data() : null;
    const after = change.after.exists ? change.after.data() : null;

    let changeType: string;
    if (!before && after) {
      changeType = "created";
    } else if (before && !after) {
      changeType = "deleted";
    } else {
      changeType = "updated";
    }

    functions.logger.info(`Delivery ${changeType}: ${deliveryId}`);

    const db = admin.firestore();

    try {
      // Update a global calendar metadata document to track last update time
      // This can be used to show users when calendars were last modified
      await db.collection("system_metadata").doc("calendar_last_updated").set({
        lastUpdated: admin.firestore.FieldValue.serverTimestamp(),
        deliveryId,
        changeType,
      }, {merge: true});

      // If the delivery affects specific staff, we could update their metadata here
      if (after && after.staffIds && Array.isArray(after.staffIds)) {
        const staffIds = after.staffIds as string[];

        // Update each affected staff member's calendar metadata
        const batch = db.batch();
        for (const staffId of staffIds) {
          const metadataRef = db.collection("calendar_metadata").doc(staffId);
          batch.set(metadataRef, {
            staffId,
            lastDeliveryChange: admin.firestore.FieldValue.serverTimestamp(),
            lastAffectedDelivery: deliveryId,
          }, {merge: true});
        }
        await batch.commit();

        functions.logger.info(`Updated calendar metadata for ${staffIds.length} staff members`);
      }
    } catch (error) {
      functions.logger.error("Error in delivery change trigger:", error);
      // Don't throw - we don't want to fail the delivery operation
    }

    return null;
  });
