// Creates reviewed staff_access links in one project. Read-only unless
// --apply is passed. The input file is the owner-reviewed list, e.g.
//   [{"uid": "...", "staffId": "...", "superAdmin": true}, ...]
// Usage:
//   node functions/scripts/seed-staff-access.cjs PROJECT_ID reviewed.json          (check only)
//   node functions/scripts/seed-staff-access.cjs PROJECT_ID reviewed.json --apply  (write)
const fs = require("node:fs");
const admin = require("firebase-admin");

const [projectId, file, flag, ...extra] = process.argv.slice(2);
if (!/^[a-z][a-z0-9-]+$/.test(projectId ?? "") || !file || extra.length ||
    (flag !== undefined && flag !== "--apply")) {
  console.error("Usage: node functions/scripts/seed-staff-access.cjs PROJECT_ID reviewed.json [--apply]");
  process.exit(1);
}
const apply = flag === "--apply";
const validId = (id) => typeof id === "string" && /^[A-Za-z0-9_-]{1,128}$/.test(id);

async function main() {
  const reviewed = JSON.parse(fs.readFileSync(file, "utf8"));
  if (!Array.isArray(reviewed) || reviewed.length === 0) throw new Error("The reviewed list is empty.");
  const app = admin.initializeApp({projectId});
  const db = app.firestore();
  const problems = [];
  const plan = [];
  const uids = new Set();
  const staffIds = new Set();
  try {
    for (const entry of reviewed) {
      const {uid, staffId, superAdmin = false} = entry ?? {};
      const label = `${staffId} / ${uid}`;
      if (!validId(uid) || !validId(staffId) || typeof superAdmin !== "boolean") {
        problems.push(`${label}: malformed entry`);
        continue;
      }
      if (uids.has(uid) || staffIds.has(staffId)) problems.push(`${label}: listed twice`);
      uids.add(uid);
      staffIds.add(staffId);
      const [staff, link] = await Promise.all([
        db.doc(`staff/${staffId}`).get(),
        db.doc(`staff_access/${uid}`).get(),
      ]);
      let user = null;
      try {
        user = await app.auth().getUser(uid);
      } catch {
        problems.push(`${label}: no Firebase Auth account`);
      }
      if (user?.disabled) problems.push(`${label}: Auth account is disabled`);
      if (!staff.exists) problems.push(`${label}: no staff record`);
      else if (staff.get("uid") !== uid) problems.push(`${label}: staff record points at another account`);
      if (!["admin", "manager", "staff"].includes(staff.get("role"))) problems.push(`${label}: unknown role`);
      if (superAdmin && staff.get("role") !== "admin") problems.push(`${label}: super admins must be admins`);
      if (link.exists) {
        const same = link.get("staffId") === staffId && (link.get("superAdmin") === true) === superAdmin;
        if (!same) problems.push(`${label}: a different access link already exists`);
        continue;
      }
      plan.push({uid, staffId, superAdmin, name: staff.get("name"), role: staff.get("role")});
    }
    if (!reviewed.some((entry) => entry?.superAdmin === true)) problems.push("No super admin is listed.");

    console.log(`Project ${projectId}: ${plan.length} link(s) to create, ${reviewed.length - plan.length} already present or refused.`);
    for (const {name, role, superAdmin} of plan) {
      console.log(`  ${name} — ${role}${superAdmin ? ", super admin" : ""}`);
    }
    if (problems.length) {
      console.error(`\nNothing written. ${problems.length} problem(s):`);
      for (const problem of problems) console.error(`  - ${problem}`);
      process.exitCode = 1;
      return;
    }
    if (!apply) {
      console.log("\nCheck only. Run again with --apply to write these links.");
      return;
    }
    // create() refuses to overwrite, so a concurrent change cannot be lost.
    const batch = db.batch();
    for (const {uid, staffId, superAdmin} of plan) {
      batch.create(db.doc(`staff_access/${uid}`), superAdmin ? {staffId, superAdmin} : {staffId});
    }
    await batch.commit();
    console.log(`\nWrote ${plan.length} access link(s).`);
  } finally {
    await app.delete();
  }
}

main().catch((error) => {
  console.error(`Stopped: ${error.message}`);
  process.exitCode = 1;
});
