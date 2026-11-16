import * as functions from "firebase-functions";
import * as admin from "firebase-admin";

// 5 hours in milliseconds
const MAX_TIMER_DURATION_MS = 5 * 60 * 60 * 1000;

/**
 * Scheduled Cloud Function that auto-stops timers running for more than 5 hours.
 * Runs every 15 minutes to check for expired timers.
 */
export const autoStopExpiredTimers = functions.pubsub
  .schedule("every 15 minutes")
  .timeZone("Australia/Melbourne")
  .onRun(async () => {
    const db = admin.firestore();
    const now = new Date();
    const cutoffTime = new Date(now.getTime() - MAX_TIMER_DURATION_MS);

    functions.logger.info("Auto-stop timer check started", {
      currentTime: now.toISOString(),
      cutoffTime: cutoffTime.toISOString(),
    });

    try {
      // Query all active timers across all schools using collection group query
      const timersSnapshot = await db.collectionGroup("timers")
        .where("isActive", "==", true)
        .get();

      if (timersSnapshot.empty) {
        functions.logger.info("No active timers found");
        return null;
      }

      functions.logger.info(`Found ${timersSnapshot.docs.length} active timers`);

      let stoppedCount = 0;
      let errorCount = 0;

      for (const timerDoc of timersSnapshot.docs) {
        try {
          const timerData = timerDoc.data();
          const startedAt = timerData.startedAt?.toDate();

          if (!startedAt) {
            functions.logger.warn(`Timer ${timerDoc.id} has no startedAt field`);
            continue;
          }

          // Check if timer has exceeded 5 hours
          if (startedAt < cutoffTime) {
            // Extract schoolId from document path: schools/{schoolId}/timers/active
            const pathParts = timerDoc.ref.path.split("/");
            const schoolId = pathParts[1];

            functions.logger.info(`Auto-stopping timer for school ${schoolId}`, {
              startedAt: startedAt.toISOString(),
              elapsedHours: ((now.getTime() - startedAt.getTime()) / (1000 * 60 * 60)).toFixed(2),
            });

            await stopTimerWithHistory(db, schoolId, timerDoc, timerData);
            stoppedCount++;
          }
        } catch (error) {
          errorCount++;
          functions.logger.error(`Error processing timer ${timerDoc.id}:`, error);
        }
      }

      functions.logger.info(`Auto-stop complete: ${stoppedCount} timers stopped, ${errorCount} errors`);
      return null;
    } catch (error) {
      functions.logger.error("Error in auto-stop timer function:", error);
      throw error;
    }
  });

/**
 * Stop a timer and move it to history, following the same logic as the Flutter app
 * (see lib/repositories/schools_repository.dart:2259-2315)
 */
async function stopTimerWithHistory(
  db: FirebaseFirestore.Firestore,
  schoolId: string,
  timerDoc: FirebaseFirestore.QueryDocumentSnapshot,
  timerData: FirebaseFirestore.DocumentData
): Promise<void> {
  const stoppedAt = new Date();
  const batch = db.batch();

  // Prepare history data with stopped info
  const historyData = {
    ...timerData,
    isActive: false,
    stoppedAt: admin.firestore.Timestamp.fromDate(stoppedAt),
    stoppedByUid: "system",
    stoppedByName: "System (Auto-stopped)",
  };

  // Add to history subcollection
  const historyRef = db
    .collection("schools")
    .doc(schoolId)
    .collection("timers")
    .doc("active")
    .collection("history")
    .doc();
  batch.set(historyRef, historyData);

  // Update the active timer document
  batch.update(timerDoc.ref, {
    isActive: false,
    stoppedAt: admin.firestore.Timestamp.fromDate(stoppedAt),
    stoppedByUid: "system",
    stoppedByName: "System (Auto-stopped)",
  });

  await batch.commit();

  functions.logger.info(`Timer auto-stopped for school ${schoolId}`, {
    historyDocId: historyRef.id,
    stoppedAt: stoppedAt.toISOString(),
  });
}
