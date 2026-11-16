import * as functions from "firebase-functions";
import * as admin from "firebase-admin";
import {FieldValue, Timestamp} from "firebase-admin/firestore";
import ical, {ICalCalendar, ICalEventData} from "ical-generator";
import {toZonedTime} from "date-fns-tz";
import {Delivery, Staff} from "./types";
import {validRole} from "./staff-access";

/**
 * HTTP Cloud Function that generates an iCal calendar feed for a staff member
 * GET /calendar/:token.ics
 */
export const generateCalendarFeed = functions.https.onRequest(async (req, res) => {
  res.setHeader("Cache-Control", "private, no-store");
  res.setHeader("X-Robots-Tag", "noindex");
  if (req.method !== "GET") {
    res.status(405).send("Method Not Allowed");
    return;
  }

  const token = /^\/([A-Za-z0-9_-]{32})\.ics$/.exec(req.path)?.[1];
  if (!token) {
    res.status(404).send("Calendar not found");
    return;
  }

  try {
    const db = admin.firestore();
    const feed = await db.runTransaction(async (tx) => {
      const tokens = await tx.get(db.collection("calendar_tokens")
        .where("token", "==", token).limit(2));
      if (tokens.size !== 1) return null;

      const subscription = tokens.docs[0];
      const staffId = subscription.id;
      const uid = subscription.get("uid");
      if (typeof uid !== "string" || !uid || uid.includes("/")) return null;

      const link = await tx.get(db.collection("staff_access").doc(uid));
      if (link.get("staffId") !== staffId) return null;
      const doc = await tx.get(db.collection("staff").doc(staffId));
      const data = doc.data();
      if (!data || data.uid !== uid || !validRole(data.role)) return null;
      const staff = {...data, id: staffId} as Staff;
      const deliveries = await fetchDeliveriesForStaff(db, tx, staff);
      return {staff, deliveries};
    }, {readOnly: true});

    if (!feed) {
      res.status(404).send("Calendar not found");
      return;
    }

    const calendar = generateICalCalendar(feed.staff, feed.deliveries);
    await updateCalendarMetadata(db, feed.staff.id, token);
    res.type("text/calendar").status(200).send(calendar.toString());
  } catch {
    functions.logger.error("Calendar feed generation failed.");
    res.status(500).send("Internal server error");
  }
});

export function schoolQueries(role: unknown, schools: unknown): string[][] | null {
  if (role === "admin" || role === "manager") return null;
  if (role !== "staff" || !Array.isArray(schools)) return [];
  const ids = [...new Set(schools.filter((id): id is string =>
    typeof id === "string" && id.length > 0 && !id.includes("/")))];
  const chunks: string[][] = [];
  for (let offset = 0; offset < ids.length; offset += 30) {
    chunks.push(ids.slice(offset, offset + 30));
  }
  return chunks;
}

async function fetchDeliveriesForStaff(
  db: FirebaseFirestore.Firestore,
  tx: FirebaseFirestore.Transaction,
  staff: Staff
): Promise<Delivery[]> {
  const year = new Date().getFullYear();
  const query = db.collection("deliveries")
    .where("date", ">=", Timestamp.fromDate(new Date(year - 1, 0, 1)))
    .where("date", "<", Timestamp.fromDate(new Date(year + 3, 0, 1)));

  const scope = schoolQueries(staff.role, staff.assignedSchoolIds);
  const queries = scope === null ? [query] : scope.map((ids) => query.where("schoolId", "in", ids));
  const snapshots = await Promise.all(queries.map((scoped) => tx.get(scoped)));
  return snapshots.flatMap((snapshot) => snapshot.docs.map((doc) => ({
    ...doc.data(),
    id: doc.id,
  } as Delivery))).sort((a, b) => a.date.toMillis() - b.date.toMillis());
}

/**
 * Generate iCal calendar from deliveries
 */
function generateICalCalendar(staff: Staff, deliveries: Delivery[]): ICalCalendar {
  const calendar = ical({
    name: "KAKA KIDS Deliveries",
    description: `Delivery schedule for ${staff.name}`,
    timezone: "Australia/Melbourne",
    ttl: 3600, // Refresh every hour (in seconds)
    prodId: {
      company: "KAKA KIDS Delivery App",
      product: "Calendar Feed",
    },
  });

  // Add each delivery as an event
  for (const delivery of deliveries) {
    const event = createEventFromDelivery(delivery);
    calendar.createEvent(event);
  }

  return calendar;
}

/**
 * Create iCal event from delivery
 */
function createEventFromDelivery(delivery: Delivery): ICalEventData {
  const TIMEZONE = "Australia/Melbourne";
  let start: Date;
  let end: Date;
  let allDay = false;

  if (delivery.time) {
    // Timed event
    // Firestore stores time in UTC. Convert it to Melbourne timezone
    // so the iCal library interprets it correctly
    const utcTime = delivery.time.toDate();
    start = toZonedTime(utcTime, TIMEZONE);
    end = new Date(start.getTime() + 60 * 60 * 1000); // 1 hour duration
  } else {
    // All-day event
    // Convert UTC date to Melbourne timezone for proper all-day event
    const utcDate = delivery.date.toDate();
    start = toZonedTime(utcDate, TIMEZONE);
    end = new Date(start.getTime() + 24 * 60 * 60 * 1000); // Next day
    allDay = true;
  }

  let description = `School: ${delivery.schoolName}\n`;

  if (delivery.staffNames && delivery.staffNames.length > 0) {
    description += `Staff: ${delivery.staffNames.join(", ")}\n`;
  }

  if (delivery.notes) {
    description += `\nNotes: ${delivery.notes}\n`;
  }

  description += "\nManaged by KAKA KIDS Delivery App";
  description += `\n[ID:${delivery.id}]`;

  return {
    start,
    end,
    summary: `Delivery: ${delivery.schoolName}`,
    description,
    location: delivery.schoolName,
    allDay,
    // Use delivery ID for consistent event identity
    id: `${delivery.id}@bts-delivery-app`,
    // Add created and last-modified timestamps
    created: delivery.createdAt.toDate(),
    lastModified: delivery.createdAt.toDate(),
  } as ICalEventData;
}

/**
 * Update calendar access metadata
 */
async function updateCalendarMetadata(
  db: FirebaseFirestore.Firestore,
  staffId: string,
  token: string
): Promise<void> {
  const metadataRef = db.collection("calendar_metadata").doc(staffId);
  try {
    await db.runTransaction(async (tx) => {
      const current = await tx.get(db.collection("calendar_tokens").doc(staffId));
      if (current.get("token") !== token) return;
      tx.set(metadataRef, {
        staffId,
        lastAccessed: FieldValue.serverTimestamp(),
        accessCount: FieldValue.increment(1),
        token: FieldValue.delete(),
      }, {merge: true});
    });
  } catch {
    functions.logger.error("Calendar access metadata update failed.");
  }
}
