import * as functions from "firebase-functions";
import * as admin from "firebase-admin";
import ical, {ICalCalendar, ICalEventData} from "ical-generator";
import {toZonedTime} from "date-fns-tz";
import {Delivery, Staff} from "./types";

/**
 * HTTP Cloud Function that generates an iCal calendar feed for a staff member
 * GET /calendar/:token.ics
 */
export const generateCalendarFeed = functions.https.onRequest(async (req, res) => {
  try {
      // Only allow GET requests
      if (req.method !== "GET") {
        res.status(405).send("Method Not Allowed");
        return;
      }

      // Extract token from URL path: /calendar/:token.ics
      const pathParts = req.path.split("/");
      const tokenWithExt = pathParts[pathParts.length - 1];
      const token = tokenWithExt?.replace(".ics", "");

      if (!token || token.length < 10) {
        res.status(400).send("Invalid calendar token");
        return;
      }

      functions.logger.info(`Calendar feed requested for token: ${token.substring(0, 8)}...`);

      // Find staff member by calendar token
      const db = admin.firestore();
      const staffSnapshot = await db.collection("staff")
        .where("calendarToken", "==", token)
        .limit(1)
        .get();

      if (staffSnapshot.empty) {
        functions.logger.warn(`No staff found for token: ${token.substring(0, 8)}...`);
        res.status(404).send("Calendar not found");
        return;
      }

      const staffDoc = staffSnapshot.docs[0];
      const staff = {id: staffDoc.id, ...staffDoc.data()} as Staff;

      functions.logger.info(`Generating calendar for staff: ${staff.name} (${staff.role})`);

      // Update calendar access metadata
      await updateCalendarMetadata(db, staff.id, token);

      // Fetch deliveries based on staff role and permissions
      const deliveries = await fetchDeliveriesForStaff(db, staff);

      // Generate iCal calendar
      const calendar = generateICalCalendar(staff, deliveries);

      // Set response headers for calendar subscription
      res.setHeader("Content-Type", "text/calendar; charset=utf-8");
      res.setHeader("Cache-Control", "no-cache, must-revalidate");
      res.setHeader("X-Robots-Tag", "noindex");

      // Send calendar
      res.status(200).send(calendar.toString());

      functions.logger.info(`Calendar generated successfully with ${deliveries.length} deliveries`);
  } catch (error) {
    functions.logger.error("Error generating calendar feed:", error);
    res.status(500).send("Internal server error");
  }
});

/**
 * Fetch deliveries based on staff role and permissions
 */
async function fetchDeliveriesForStaff(
  db: FirebaseFirestore.Firestore,
  staff: Staff
): Promise<Delivery[]> {
  const now = new Date();
  // Fetch deliveries from 1 year ago to 2 years in the future
  const startDate = new Date(now.getFullYear() - 1, 0, 1);
  const endDate = new Date(now.getFullYear() + 2, 11, 31);

  let query = db.collection("deliveries")
    .where("date", ">=", admin.firestore.Timestamp.fromDate(startDate))
    .where("date", "<=", admin.firestore.Timestamp.fromDate(endDate));

  // Filter by assigned schools for non-admin/manager staff
  if (staff.role === "staff" && staff.assignedSchoolIds.length > 0) {
    // Firestore 'in' query supports up to 10 items, so we need to handle larger arrays
    if (staff.assignedSchoolIds.length <= 10) {
      query = query.where("schoolId", "in", staff.assignedSchoolIds);
    } else {
      // For more than 10 schools, we'll fetch all and filter in memory
      functions.logger.info(`Staff has ${staff.assignedSchoolIds.length} schools, filtering in memory`);
    }
  }

  const snapshot = await query.get();
  let deliveries = snapshot.docs.map((doc) => ({
    id: doc.id,
    ...doc.data(),
  })) as Delivery[];

  // Filter in memory if needed (for staff with > 10 assigned schools)
  if (staff.role === "staff" && staff.assignedSchoolIds.length > 10) {
    deliveries = deliveries.filter((d) => staff.assignedSchoolIds.includes(d.schoolId));
  }

  functions.logger.info(`Fetched ${deliveries.length} deliveries for ${staff.role} ${staff.name}`);

  return deliveries;
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
    await db.runTransaction(async (transaction) => {
      const doc = await transaction.get(metadataRef);

      if (doc.exists) {
        // Update existing metadata
        transaction.update(metadataRef, {
          lastAccessed: admin.firestore.FieldValue.serverTimestamp(),
          accessCount: admin.firestore.FieldValue.increment(1),
        });
      } else {
        // Create new metadata
        transaction.set(metadataRef, {
          staffId,
          token,
          lastAccessed: admin.firestore.FieldValue.serverTimestamp(),
          accessCount: 1,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      }
    });
  } catch (error) {
    functions.logger.error("Error updating calendar metadata:", error);
    // Don't fail the request if metadata update fails
  }
}
