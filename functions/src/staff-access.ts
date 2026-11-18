import * as admin from "firebase-admin";
import {FieldValue, Timestamp} from "firebase-admin/firestore";
import * as functions from "firebase-functions";
import {createHash, randomBytes} from "crypto";

type Transaction = FirebaseFirestore.Transaction;
type DocumentData = FirebaseFirestore.DocumentData;
const {HttpsError} = functions.https;
const roles = ["admin", "manager", "staff"];

export function validRole(role: unknown): role is "admin" | "manager" | "staff" {
  return typeof role === "string" && roles.includes(role);
}

function uidFor(context: functions.https.CallableContext): string {
  if (!context.auth) throw new HttpsError("unauthenticated", "Please sign in.");
  return context.auth.uid;
}

function documentId(value: unknown): string {
  if (typeof value !== "string" || !/^[A-Za-z0-9_-]{1,128}$/.test(value)) {
    throw new HttpsError("invalid-argument", "Invalid staff identifier.");
  }
  return value;
}

function hashSecret(secret: string): string {
  return createHash("sha256").update(secret).digest("hex");
}

export async function linkedStaff(
  db: FirebaseFirestore.Firestore,
  tx: Transaction,
  uid: string
): Promise<DocumentData | undefined> {
  const mapping = await tx.get(db.collection("staff_access").doc(uid));
  const staffId = mapping.get("staffId");
  if (typeof staffId !== "string" || !staffId || staffId.includes("/")) return undefined;
  const staff = (await tx.get(db.collection("staff").doc(staffId))).data();
  return staff?.uid === uid && validRole(staff.role) ? staff : undefined;
}

async function hasReciprocalLink(
  db: FirebaseFirestore.Firestore,
  tx: Transaction,
  staffId: string,
  staff: DocumentData
): Promise<boolean> {
  if (typeof staff.uid !== "string" || !staff.uid || staff.uid.includes("/")) return false;
  const link = await tx.get(db.collection("staff_access").doc(staff.uid));
  return link.get("staffId") === staffId;
}

export const issueStaffInvite = functions.https.onCall(async (data, context) => {
  const uid = uidFor(context);
  const staffId = documentId(data?.staffId);
  const db = admin.firestore();
  const secret = randomBytes(24).toString("base64url");
  const expiresAt = Timestamp.fromMillis(Date.now() + 24 * 60 * 60 * 1000);

  await db.runTransaction(async (tx) => {
    const caller = await linkedStaff(db, tx, uid);
    const callerLink = await tx.get(db.collection("staff_access").doc(uid));
    if (caller?.role !== "admin" || callerLink.get("superAdmin") !== true) {
      throw new HttpsError("permission-denied", "Only a super admin can issue an invite.");
    }
    const staff = (await tx.get(db.collection("staff").doc(staffId))).data();
    if (!staff || !validRole(staff.role)) {
      throw new HttpsError("not-found", "Staff member not found.");
    }
    if (await hasReciprocalLink(db, tx, staffId, staff)) {
      throw new HttpsError("already-exists", "This staff member already has a linked account.");
    }
    tx.set(db.collection("staff_invites").doc(staffId), {
      secretHash: hashSecret(secret),
      role: staff.role,
      expiresAt,
    });
  });

  return {code: `${staffId}.${secret}`};
});

export const redeemStaffInvite = functions.https.onCall(async (data, context) => {
  const uid = uidFor(context);
  const code = data?.code;
  const match = typeof code === "string" && /^([A-Za-z0-9_-]{1,128})\.([A-Za-z0-9_-]{32})$/.exec(code);
  if (!match) throw new HttpsError("invalid-argument", "Enter the complete invitation code.");
  const [, staffId, secret] = match;
  const db = admin.firestore();
  const staffRef = db.collection("staff").doc(staffId);
  const inviteRef = db.collection("staff_invites").doc(staffId);

  await db.runTransaction(async (tx) => {
    const invite = (await tx.get(inviteRef)).data();
    const staff = (await tx.get(staffRef)).data();
    if (!staff || !validRole(staff.role) || !invite || invite.role !== staff.role ||
        invite.secretHash !== hashSecret(secret) || invite.expiresAt.toMillis() <= Date.now()) {
      throw new HttpsError("failed-precondition", "This invitation is invalid or expired. Ask your administrator for a new code.");
    }
    if (await linkedStaff(db, tx, uid) || await hasReciprocalLink(db, tx, staffId, staff)) {
      throw new HttpsError("already-exists", "This account or staff member is already linked.");
    }

    tx.set(db.collection("staff_access").doc(uid), {staffId});
    tx.update(staffRef, {
      uid,
      linkPin: FieldValue.delete(),
      calendarToken: FieldValue.delete(),
    });
    tx.delete(inviteRef);
  });

  return {staffId};
});

export const listStaffDirectory = functions.https.onCall(async (_data, context) => {
  const uid = uidFor(context);
  const db = admin.firestore();
  return db.runTransaction(async (tx) => {
    const caller = await linkedStaff(db, tx, uid);
    if (caller?.role !== "admin" && caller?.role !== "manager") {
      throw new HttpsError("permission-denied", "Only managers can view the staff directory.");
    }
    const snapshot = await tx.get(db.collection("staff").orderBy("name"));
    const mappings = caller.role === "admin"
      ? new Map((await tx.get(db.collection("staff_access"))).docs
        .map((doc) => [doc.id, doc.get("staffId")]))
      : null;
    return {
      staff: snapshot.docs.map((doc) => {
        const staff = doc.data();
        return {
          id: doc.id,
          name: staff.name,
          role: validRole(staff.role) ? staff.role : "staff",
          assignedSchoolIds: staff.assignedSchoolIds ?? [],
          createdAt: staff.createdAt?.toMillis() ?? 0,
          ...(mappings ? {uid: mappings.get(staff.uid) === doc.id ? staff.uid : null} : {}),
        };
      }),
    };
  });
});

export const calendarSubscriptionToken = functions.https.onCall(async (data, context) => {
  const uid = uidFor(context);
  const staffId = documentId(data?.staffId);
  const rotate = data?.rotate === true;
  const db = admin.firestore();
  const tokens = db.collection("calendar_tokens").doc(staffId);
  const metadata = db.collection("calendar_metadata").doc(staffId);
  const staffRef = db.collection("staff").doc(staffId);

  return db.runTransaction(async (tx) => {
    const caller = await linkedStaff(db, tx, uid);
    const staff = (await tx.get(staffRef)).data();
    if (!staff || !caller || (caller.role !== "admin" && staff.uid !== uid) ||
        !validRole(staff.role) || !await hasReciprocalLink(db, tx, staffId, staff)) {
      throw new HttpsError("permission-denied", "Calendar subscriptions require a linked staff account.");
    }
    const currentToken = (await tx.get(tokens)).data();
    if (!rotate && currentToken && currentToken.uid === staff.uid && typeof currentToken.token === "string") {
      return {token: currentToken.token};
    }

    if (data?.existingOnly === true) return {token: null};

    const token = randomBytes(24).toString("base64url");
    tx.set(tokens, {uid: staff.uid, token});
    tx.set(metadata, {
      staffId,
      accessCount: 0,
      subscriptionActive: true,
      createdAt: FieldValue.serverTimestamp(),
      token: FieldValue.delete(),
      lastAccessed: FieldValue.delete(),
    }, {merge: true});
    return {token};
  });
});
