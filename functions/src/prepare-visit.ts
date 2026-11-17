import * as admin from "firebase-admin";
import {FieldValue} from "firebase-admin/firestore";
import * as functions from "firebase-functions";
import {linkedStaff} from "./staff-access";

const {HttpsError} = functions.https;
const MAX_CHILDREN = 499;

type Database = FirebaseFirestore.Firestore;
type Transaction = FirebaseFirestore.Transaction;
type Document = FirebaseFirestore.DocumentReference;
type Fields = FirebaseFirestore.DocumentData;

function identifier(value: unknown): value is string {
  return typeof value === "string" && /^[A-Za-z0-9_-]{1,128}$/.test(value);
}

function canAccessSchool(staff: Fields | undefined, schoolId: string): boolean {
  return staff?.role === "admin" || staff?.role === "manager" ||
    (staff?.role === "staff" && Array.isArray(staff.assignedSchoolIds) &&
      staff.assignedSchoolIds.includes(schoolId));
}

function expectedConsumable(data: Fields): Fields {
  return {
    itemName: data.itemName,
    quantity: data.quantity,
    unit: data.unit,
    createdAt: data.createdAt,
    actualQuantityDelivered: null,
  };
}

type Copy = {
  ref: Document;
  data: Fields;
};

async function classroomTemplate(
  tx: Transaction,
  source: FirebaseFirestore.QueryDocumentSnapshot,
  destination: Document
): Promise<Copy[]> {
  const data = source.data();
  const [packs, consumables, breakdowns] = await Promise.all([
    tx.get(source.ref.collection("packTotals").orderBy("createdAt", "desc").limit(1)),
    tx.get(source.ref.collection("consumables")),
    tx.get(source.ref.collection("yearLevelBreakdowns")),
  ]);

  return [
    {
      ref: destination,
      data: {
        name: data.name,
        createdAt: data.createdAt,
        completionStatus: "notAttended",
        actualPacksDelivered: null,
      },
    },
    ...packs.docs.map((doc) => ({
      ref: destination.collection("packTotals").doc(doc.id),
      data: {total: doc.get("total"), createdAt: doc.get("createdAt")},
    })),
    ...consumables.docs.map((doc) => ({
      ref: destination.collection("consumables").doc(doc.id),
      data: expectedConsumable(doc.data()),
    })),
    ...breakdowns.docs.map((doc) => ({
      ref: destination.collection("yearLevelBreakdowns").doc(doc.id),
      data: {
        yearLevelId: doc.get("yearLevelId"),
        yearLevelLabel: doc.get("yearLevelLabel"),
        studentCount: doc.get("studentCount"),
        packAllocation: doc.get("packAllocation") ?? null,
        createdAt: doc.get("createdAt"),
      },
    })),
  ];
}

async function readTemplate(tx: Transaction, template: Document, workspace: Document): Promise<Copy[]> {
  const [years, supplies] = await Promise.all([
    tx.get(template.collection("yearLevels")),
    tx.get(template.collection("consumables")),
  ]);
  const levelCopies = await Promise.all(years.docs.map(async (year) => {
    const yearRef = workspace.collection("yearLevels").doc(year.id);
    const classrooms = await tx.get(year.ref.collection("classrooms"));
    const roomCopies = await Promise.all(classrooms.docs.map((room) =>
      classroomTemplate(tx, room, yearRef.collection("classrooms").doc(room.id))));
    return [
      {
        ref: yearRef,
        data: {label: year.get("label") ?? year.get("name"), createdAt: year.get("createdAt")},
      },
      ...roomCopies.flat(),
    ];
  }));
  return [
    ...levelCopies.flat(),
    ...supplies.docs.map((doc) => ({
      ref: workspace.collection("consumables").doc(doc.id),
      data: expectedConsumable(doc.data()),
    })),
  ];
}

export async function prepareVisitWorkspace(
  db: Database,
  uid: string,
  deliveryId: string,
  schoolId: string
): Promise<{status: "ready"; alreadyPrepared: boolean}> {
  const delivery = db.collection("deliveries").doc(deliveryId);
  const workspace = delivery.collection("workspace").doc(schoolId);
  const school = db.collection("schools").doc(schoolId);

  return db.runTransaction(async (tx) => {
    const staff = await linkedStaff(db, tx, uid);
    const deliveryDoc = await tx.get(delivery);
    if (!canAccessSchool(staff, schoolId) || deliveryDoc.get("schoolId") !== schoolId) {
      throw new HttpsError("permission-denied", "You do not have access to this visit.");
    }

    const manifest = await tx.get(workspace);
    if (manifest.exists) {
      if (manifest.get("status") === "ready" && manifest.get("schoolId") === schoolId &&
          manifest.get("deliveryId") === deliveryId) {
        return {status: "ready", alreadyPrepared: true};
      }
      throw new HttpsError("failed-precondition", "The saved visit workspace needs administrator review.");
    }

    const template = await tx.get(school);
    if (!template.exists) {
      throw new HttpsError("failed-precondition", "The school template is unavailable.");
    }

    const children = await readTemplate(tx, school, workspace);
    if (children.length > MAX_CHILDREN) {
      throw new HttpsError("failed-precondition", "This school template is too large to prepare in one step.");
    }

    const inventory = children.reduce<Record<string, number>>((counts, {ref}) => {
      const collection = ref.parent.path.slice(workspace.path.length + 1);
      counts[collection] = (counts[collection] ?? 0) + 1;
      return counts;
    }, {});
    for (const {ref, data} of children) tx.create(ref, data);
    tx.create(workspace, {
      schoolId,
      deliveryId,
      status: "ready",
      name: template.get("name"),
      address: template.get("address") ?? null,
      createdAt: template.get("createdAt"),
      preparedAt: FieldValue.serverTimestamp(),
      inventory,
    });
    return {status: "ready", alreadyPrepared: false};
  });
}

export const prepareVisit = functions.https.onCall(async (data, context) => {
  if (!context.auth) throw new HttpsError("unauthenticated", "Please sign in.");
  if (!identifier(data?.deliveryId) || !identifier(data?.schoolId)) {
    throw new HttpsError("invalid-argument", "Invalid delivery or school identifier.");
  }
  try {
    return await prepareVisitWorkspace(admin.firestore(), context.auth.uid, data.deliveryId, data.schoolId);
  } catch (error) {
    if (error instanceof HttpsError) throw error;
    functions.logger.error("Visit workspace preparation failed.");
    throw new HttpsError("failed-precondition", "Could not prepare the visit. Review the school template and try again.");
  }
});
