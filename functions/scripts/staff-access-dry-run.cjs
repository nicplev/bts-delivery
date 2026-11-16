const admin = require("firebase-admin");

const projectId = process.argv[2];
if (process.argv.length !== 3 || !/^[a-z][a-z0-9-]+$/.test(projectId ?? "")) {
  console.error("Usage: node functions/scripts/staff-access-dry-run.cjs PROJECT_ID");
  process.exit(1);
}

function validUid(uid) {
  return typeof uid === "string" && uid.length > 0 && uid.length <= 128 && !uid.includes("/");
}

function safeRole(role) {
  return role == null ? null : ["admin", "manager", "staff"].includes(role) ? role : "invalid";
}

async function main() {
  const app = admin.initializeApp({projectId});
  try {
    const db = app.firestore();
    const [staff, users, access, schools] = await Promise.all([
      db.collection("staff").get(),
      db.collection("users").get(),
      db.collection("staff_access").get(),
      db.collection("schools").select().get(),
    ]);
    const byUid = new Map();
    for (const doc of staff.docs) {
      const uid = doc.get("uid");
      if (!validUid(uid)) continue;
      const records = byUid.get(uid) ?? [];
      records.push(doc);
      byUid.set(uid, records);
    }
    const actualAuth = new Map();
    const uids = [...new Set([...byUid.keys(), ...users.docs.map((doc) => doc.id).filter(validUid)])];
    for (let offset = 0; offset < uids.length; offset += 100) {
      const result = await app.auth().getUsers(
        uids.slice(offset, offset + 100).map((uid) => ({uid})),
      );
      for (const user of result.users) actualAuth.set(user.uid, user);
    }
    const profile = new Map(users.docs.map((doc) => [doc.id, safeRole(doc.get("role"))]));
    const trusted = new Map(access.docs.map((doc) => [doc.id, doc.get("staffId") ?? null]));
    const schoolIds = new Set(schools.docs.map((doc) => doc.id));
    const report = {
      projectId,
      mode: "read-only",
      observedCounts: {staff: staff.size, users: users.size, trustedMappings: access.size},
      staff: staff.docs.map((doc) => {
        const {uid, role, assignedSchoolIds} = doc.data();
        const auth = actualAuth.get(uid);
        const possibleDuplicate = (byUid.get(uid)?.length ?? 0) > 1;
        const problems = [];
        if (!uid) problems.push("no legacy uid");
        if (uid && !validUid(uid)) problems.push("invalid legacy uid");
        if (validUid(uid) && !auth) problems.push("no matching Firebase Auth account");
        if (auth?.disabled) problems.push("disabled Firebase Auth account");
        if (possibleDuplicate) problems.push("multiple staff documents share the uid");
        if (!["admin", "manager", "staff"].includes(role)) problems.push("unknown staff role");
        if (profile.get(uid) && profile.get(uid) !== role) problems.push("legacy roles disagree");
        if (!Array.isArray(assignedSchoolIds) || assignedSchoolIds.some((id) => !schoolIds.has(id))) {
          problems.push("invalid school assignment");
        }
        if (trusted.has(uid) && trusted.get(uid) !== doc.id) problems.push("trusted mapping is different");
        return {
          staffId: doc.id,
          legacyUid: validUid(uid) ? uid : null,
          claimedStaffRole: safeRole(role),
          claimedProfileRole: profile.get(uid) ?? null,
          trustedMappingExists: trusted.get(uid) === doc.id && !possibleDuplicate,
          manualVerificationRequired: true,
          problems,
        };
      }),
      unmatchedUserProfiles: users.docs.filter((doc) => !byUid.has(doc.id)).map((doc) => doc.id),
      brokenTrustedMappings: access.docs.filter((doc) =>
        !byUid.get(doc.id)?.some((staffDoc) => staffDoc.id === doc.get("staffId")))
        .map((doc) => doc.id),
    };
    console.log(JSON.stringify(report, null, 2));
  } finally {
    await app.delete();
  }
}

main().catch(() => {
  console.error("Could not read Firebase Auth and Firestore for the requested project.");
  process.exitCode = 1;
});
