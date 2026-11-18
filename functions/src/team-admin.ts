import * as admin from "firebase-admin";
import {FieldValue} from "firebase-admin/firestore";
import * as functions from "firebase-functions";
import {validRole} from "./staff-access";

// Team control for super administrators. A super administrator is an admin
// whose server-owned staff_access/{uid} link carries superAdmin: true. Only
// these functions (and the reviewed seeding procedure) ever set that flag.

type Transaction = FirebaseFirestore.Transaction;
type DocumentData = FirebaseFirestore.DocumentData;
const {HttpsError} = functions.https;

interface Caller {
  uid: string;
  staffId: string;
}

interface Member {
  staffId: string;
  staff: DocumentData;
  // Set only when the staff record and the access link point at each other.
  uid: string | null;
  superAdmin: boolean;
}

function staffIdFrom(value: unknown): string {
  if (typeof value !== "string" || !/^[A-Za-z0-9_-]{1,128}$/.test(value)) {
    throw new HttpsError("invalid-argument", "Invalid staff identifier.");
  }
  return value;
}

function emailFrom(value: unknown): string {
  const email = typeof value === "string" ? value.trim().toLowerCase() : "";
  if (email.length > 254 || !/^[^\s@/]+@[^\s@/]+\.[^\s@/]+$/.test(email)) {
    throw new HttpsError("invalid-argument", "Enter a valid email address.");
  }
  return email;
}

function nameFrom(value: unknown): string {
  const name = typeof value === "string" ? value.trim() : "";
  if (!name || name.length > 200) {
    throw new HttpsError("invalid-argument", "Enter a name.");
  }
  return name;
}

export async function superAdminCaller(
  db: FirebaseFirestore.Firestore,
  tx: Transaction,
  context: functions.https.CallableContext,
): Promise<Caller> {
  const uid = context.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Please sign in.");
  const link = (await tx.get(db.collection("staff_access").doc(uid))).data();
  const staffId = link?.staffId;
  if (typeof staffId === "string" && staffId && !staffId.includes("/") && link?.superAdmin === true) {
    const staff = (await tx.get(db.collection("staff").doc(staffId))).data();
    if (staff?.uid === uid && staff.role === "admin") return {uid, staffId};
  }
  throw new HttpsError("permission-denied", "Only a super admin can manage the team.");
}

async function member(
  db: FirebaseFirestore.Firestore,
  tx: Transaction,
  staffId: string,
): Promise<Member> {
  const staff = (await tx.get(db.collection("staff").doc(staffId))).data();
  if (!staff || !validRole(staff.role)) {
    throw new HttpsError("not-found", "Staff member not found.");
  }
  const legacyUid = typeof staff.uid === "string" && staff.uid && !staff.uid.includes("/") ?
    staff.uid : null;
  const link = legacyUid ?
    (await tx.get(db.collection("staff_access").doc(legacyUid))).data() : undefined;
  const linked = link?.staffId === staffId;
  return {
    staffId,
    staff,
    uid: linked ? legacyUid : null,
    superAdmin: linked && link?.superAdmin === true,
  };
}

function notSelf(caller: Caller, target: Member, message: string) {
  if (target.staffId === caller.staffId) {
    throw new HttpsError("failed-precondition", message);
  }
}

/** Every staff member with their sign-in details, for super admins only. */
export const listTeamAccounts = functions.https.onCall(async (_data, context) => {
  const db = admin.firestore();
  const {members, caller} = await db.runTransaction(async (tx) => {
    const caller = await superAdminCaller(db, tx, context);
    const [staff, access] = await Promise.all([
      tx.get(db.collection("staff")),
      tx.get(db.collection("staff_access")),
    ]);
    const links = new Map(access.docs.map((doc) => [doc.id, doc.data()]));
    const members = staff.docs.map((doc) => {
      const uid = doc.get("uid");
      const link = typeof uid === "string" ? links.get(uid) : undefined;
      const linked = link?.staffId === doc.id;
      return {staffId: doc.id, uid: linked ? uid as string : null, superAdmin: linked && link?.superAdmin === true};
    });
    return {members, caller};
  });

  const users = new Map<string, admin.auth.UserRecord>();
  const uids = members.flatMap(({uid}) => uid ? [uid] : []);
  for (let offset = 0; offset < uids.length; offset += 100) {
    const result = await admin.auth().getUsers(uids.slice(offset, offset + 100).map((uid) => ({uid})));
    for (const user of result.users) users.set(user.uid, user);
  }

  return {
    callerStaffId: caller.staffId,
    accounts: members.map(({staffId, uid, superAdmin}) => {
      const user = uid ? users.get(uid) : undefined;
      const lastSignIn = user?.metadata.lastSignInTime ? Date.parse(user.metadata.lastSignInTime) : null;
      return {
        staffId,
        hasLogin: Boolean(user),
        email: user?.email ?? null,
        signInEnabled: user ? !user.disabled : false,
        superAdmin,
        lastSignInAt: Number.isFinite(lastSignIn) ? lastSignIn : null,
      };
    }),
  };
});

/**
 * Creates a sign-in for a new or existing staff member. The account has no
 * password: the app then sends the person a reset email to choose one.
 */
export const createTeamAccount = functions.https.onCall(async (data, context) => {
  const email = emailFrom(data?.email);
  const existingStaffId = data?.staffId == null ? null : staffIdFrom(data.staffId);
  const name = existingStaffId ? null : nameFrom(data?.name);
  const role = existingStaffId ? null : data?.role;
  if (!existingStaffId && !validRole(role)) {
    throw new HttpsError("invalid-argument", "Choose a role.");
  }
  const db = admin.firestore();
  // Fail before touching Auth when the caller is not allowed.
  await db.runTransaction((tx) => superAdminCaller(db, tx, context));

  let user: admin.auth.UserRecord;
  let created = false;
  try {
    user = await admin.auth().getUserByEmail(email);
  } catch (error) {
    if ((error as {code?: string}).code !== "auth/user-not-found") throw error;
    user = await admin.auth().createUser({email, emailVerified: false, disabled: false});
    created = true;
  }

  try {
    const staffId = await db.runTransaction(async (tx) => {
      await superAdminCaller(db, tx, context);
      const existingLink = await tx.get(db.collection("staff_access").doc(user.uid));
      if (existingLink.exists) {
        throw new HttpsError("already-exists", "That email already signs in as a team member.");
      }
      let target: FirebaseFirestore.DocumentReference;
      if (existingStaffId) {
        const current = await member(db, tx, existingStaffId);
        if (current.uid) {
          throw new HttpsError("already-exists", "This person already has a sign-in.");
        }
        target = db.collection("staff").doc(existingStaffId);
        tx.update(target, {
          uid: user.uid,
          linkPin: FieldValue.delete(),
          calendarToken: FieldValue.delete(),
        });
        tx.delete(db.collection("staff_invites").doc(existingStaffId));
      } else {
        target = db.collection("staff").doc();
        tx.set(target, {
          name,
          role,
          assignedSchoolIds: [],
          uid: user.uid,
          createdAt: FieldValue.serverTimestamp(),
        });
      }
      tx.set(db.collection("staff_access").doc(user.uid), {staffId: target.id});
      return target.id;
    });
    return {staffId, email};
  } catch (error) {
    if (created) await admin.auth().deleteUser(user.uid).catch(() => undefined);
    throw error;
  }
});

/** Grants or removes super admin. Nobody can change their own. */
export const setTeamSuperAdmin = functions.https.onCall(async (data, context) => {
  const staffId = staffIdFrom(data?.staffId);
  const superAdmin = data?.superAdmin;
  if (typeof superAdmin !== "boolean") {
    throw new HttpsError("invalid-argument", "Choose whether this person is a super admin.");
  }
  const db = admin.firestore();
  await db.runTransaction(async (tx) => {
    const caller = await superAdminCaller(db, tx, context);
    const target = await member(db, tx, staffId);
    notSelf(caller, target, "You can't change your own super admin access.");
    if (!target.uid) {
      throw new HttpsError("failed-precondition", "This person needs a sign-in first.");
    }
    if (superAdmin && target.staff.role !== "admin") {
      throw new HttpsError("failed-precondition", "Make this person an admin first.");
    }
    tx.update(db.collection("staff_access").doc(target.uid), {superAdmin});
  });
  return {staffId, superAdmin};
});

/** Turns a person's sign-in off or back on. */
export const setTeamSignIn = functions.https.onCall(async (data, context) => {
  const staffId = staffIdFrom(data?.staffId);
  const enabled = data?.enabled;
  if (typeof enabled !== "boolean") {
    throw new HttpsError("invalid-argument", "Choose whether sign-in is allowed.");
  }
  const db = admin.firestore();
  const uid = await db.runTransaction(async (tx) => {
    const caller = await superAdminCaller(db, tx, context);
    const target = await member(db, tx, staffId);
    notSelf(caller, target, "You can't turn off your own sign-in.");
    if (!target.uid) {
      throw new HttpsError("failed-precondition", "This person has no sign-in.");
    }
    if (!enabled && target.superAdmin) {
      throw new HttpsError("failed-precondition", "Remove super admin access first.");
    }
    return target.uid;
  });
  await admin.auth().updateUser(uid, {disabled: !enabled});
  if (!enabled) await admin.auth().revokeRefreshTokens(uid);
  return {staffId, enabled};
});

/**
 * Removes a person from the team: their staff record, access link, pending
 * invitation, calendar subscription and sign-in. Past visit records keep the
 * names they were saved with.
 */
export const deleteTeamMember = functions.https.onCall(async (data, context) => {
  const staffId = staffIdFrom(data?.staffId);
  const db = admin.firestore();
  const uid = await db.runTransaction(async (tx) => {
    const caller = await superAdminCaller(db, tx, context);
    const target = await member(db, tx, staffId);
    notSelf(caller, target, "You can't delete yourself.");
    if (target.superAdmin) {
      throw new HttpsError("failed-precondition", "Remove super admin access first.");
    }
    tx.delete(db.collection("staff").doc(staffId));
    tx.delete(db.collection("staff_invites").doc(staffId));
    tx.delete(db.collection("calendar_tokens").doc(staffId));
    tx.delete(db.collection("calendar_metadata").doc(staffId));
    if (target.uid) tx.delete(db.collection("staff_access").doc(target.uid));
    return target.uid;
  });
  // Only an account proven to belong to this person is deleted.
  if (uid) {
    await admin.auth().deleteUser(uid).catch((error) => {
      if ((error as {code?: string}).code !== "auth/user-not-found") throw error;
    });
  }
  return {staffId};
});
