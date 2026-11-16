import * as functions from "firebase-functions";
import * as admin from "firebase-admin";
import {Timestamp} from "firebase-admin/firestore";

const MAX_TIMER_DURATION_MS = 5 * 60 * 60 * 1000;

export const autoStopExpiredTimers = functions.pubsub
  .schedule("every 15 minutes")
  .timeZone("Australia/Melbourne")
  .onRun(async () => {
    const db = admin.firestore();
    const now = Timestamp.now();
    const timers = await db.collectionGroup("timers").where("isActive", "==", true).get();
    let stopped = 0;
    for (const timer of timers.docs) {
      if (!/^(schools\/[^/]+|deliveries\/[^/]+\/workspace\/[^/]+)\/timers\/active$/.test(timer.ref.path)) continue;
      const data = timer.data();
      if (!isExpired(data, now)) continue;

      try {
        if (await stopExpiredTimer(db, timer.ref, sessionId(data), now)) stopped++;
      } catch {
        functions.logger.error("Could not auto-stop an expired timer.", {path: timer.ref.path});
      }
    }
    functions.logger.info("Expired timer check finished.", {stopped});
    return null;
  });

export function sessionId(data: FirebaseFirestore.DocumentData): string {
  const id = data.sessionId;
  if (typeof id === "string" && id) return id;
  return `legacy-${data.startedAt.seconds}-${data.startedAt.nanoseconds}`;
}

function isExpired(
  data: FirebaseFirestore.DocumentData,
  now: FirebaseFirestore.Timestamp
): boolean {
  return data.isActive === true &&
    data.startedAt instanceof Timestamp &&
    data.startedAt.toMillis() <= now.toMillis() - MAX_TIMER_DURATION_MS;
}

export async function stopExpiredTimer(
  db: FirebaseFirestore.Firestore,
  ref: FirebaseFirestore.DocumentReference,
  expectedSession: string,
  now: FirebaseFirestore.Timestamp
): Promise<boolean> {
  return db.runTransaction(async (tx) => {
    const data = (await tx.get(ref)).data();
    if (!data || !isExpired(data, now) || sessionId(data) !== expectedSession) return false;

    const stopped = {
      sessionId: expectedSession,
      isActive: false,
      stoppedAt: now,
      stoppedByUid: "system",
      stoppedByName: "System (Auto-stopped)",
    };
    tx.create(ref.collection("history").doc(expectedSession), {...data, ...stopped});
    tx.update(ref, stopped);
    return true;
  });
}
