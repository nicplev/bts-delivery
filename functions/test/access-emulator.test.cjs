const assert = require("node:assert/strict");
const {test, after} = require("node:test");
const admin = require("firebase-admin");
const visitSignaturePayload = require("../../test/fixtures/visit_signature_payload.json");

const projectId = process.env.BTS_EMULATOR_TEST_PROJECT ?? "demo-bts-delivery";
const dbHost = process.env.FIRESTORE_EMULATOR_HOST;
const authHost = process.env.FIREBASE_AUTH_EMULATOR_HOST;
const storageHost = process.env.FIREBASE_STORAGE_EMULATOR_HOST;
const functionsHost = process.env.BTS_EMULATOR_TEST_FUNCTIONS_HOST ?? "127.0.0.1:5001";
const local = (value) => /^(?:localhost|127\.0\.0\.1):\d+$/.test(value ?? "");
if (!["demo-bts-delivery", "demo-bts-delivery-rules"].includes(projectId) ||
    ![dbHost, authHost, storageHost, functionsHost].every(local)) {
  throw new Error("Run this suite with the demo Firebase emulators.");
}
const app = admin.initializeApp({projectId});
const db = app.firestore();
const root = `projects/${projectId}/databases/(default)/documents`;
const documents = `http://${dbHost}/v1/${root}`;
const functions = `http://${functionsHost}/${projectId}/us-central1`;
const bucket = `${projectId}.appspot.com`;
const storage = `http://${storageHost}/v0/b/${bucket}/o`;

after(() => app.delete());

function value(data) {
  if (data === null) return {nullValue: null};
  if (Array.isArray(data)) return {arrayValue: {values: data.map(value)}};
  if (data instanceof admin.firestore.Timestamp) return {timestampValue: data.toDate().toISOString()};
  if (typeof data === "string") return {stringValue: data};
  if (typeof data === "boolean") return {booleanValue: data};
  if (Number.isInteger(data)) return {integerValue: String(data)};
  return {mapValue: {fields: fields(data)}};
}

function fields(data) {
  return Object.fromEntries(Object.entries(data).map(([key, item]) => [key, value(item)]));
}

async function request(url, user, options = {}) {
  const headers = {
    ...(options.body ? {"Content-Type": "application/json"} : {}),
    ...(user ? {Authorization: `Bearer ${user.idToken}`} : {}),
    ...options.headers,
  };
  return fetch(url, {...options, headers});
}

const get = (path, user) => request(`${documents}/${path}`, user);

function write(path, user, data) {
  return request(`${documents}/${path}`, user, {
    method: "PATCH", body: JSON.stringify({fields: fields(data)}),
  });
}

function remove(path, user) {
  return request(`${documents}/${path}`, user, {method: "DELETE"});
}

function commit(user, writes) {
  return request(`${documents}:commit`, user, {method: "POST", body: JSON.stringify({writes})});
}

function runQuery(user, collection, filter) {
  return request(`${documents}:runQuery`, user, {
    method: "POST",
    body: JSON.stringify({
      structuredQuery: {
        from: [{collectionId: collection}],
        ...(filter ? {where: filter} : {}),
      },
    }),
  });
}

function inFilter(fieldPath, values) {
  return {fieldFilter: {field: {fieldPath}, op: "IN", value: {arrayValue: {values}}}};
}

async function status(response, expected) {
  assert.equal(response.status, expected, await response.text());
}

async function signUp(name) {
  const email = `${name}@example.test`;
  const resp = await request(
    `http://${authHost}/identitytoolkit.googleapis.com/v1/accounts:signUp?key=demo-api-key`,
    null,
    {method: "POST", body: JSON.stringify({email, password: "demo-test-secret", returnSecureToken: true})},
  );
  const data = await resp.json();
  assert.equal(resp.status, 200, JSON.stringify(data));
  return {uid: data.localId, idToken: data.idToken, email};
}

async function call(functionName, user, data, expected = 200) {
  const response = await request(`${functions}/${functionName}`, user, {
    method: "POST", body: JSON.stringify({data}),
  });
  const body = await response.json();
  assert.equal(response.status, expected, JSON.stringify(body));
  return body.result;
}

function upload(path, user, uid, contentType = "image/png", content = "test-bytes") {
  const boundary = "bts-test-boundary";
  const metadata = JSON.stringify({
    contentType, metadata: {uploadedBy: uid, sha256: "a".repeat(64)},
  });
  const body = [
    `--${boundary}\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n${metadata}\r\n`,
    `--${boundary}\r\nContent-Type: ${contentType}\r\n\r\n${content}\r\n`,
    `--${boundary}--\r\n`,
  ].join("");
  return request(`${storage}?name=${encodeURIComponent(path)}&uploadType=multipart`, user, {
    method: "POST",
    headers: {
      "Content-Type": `multipart/related; boundary=${boundary}`,
      "X-Goog-Upload-Protocol": "multipart",
    },
    body,
  });
}

const now = admin.firestore.Timestamp.now();
const staffData = (name, role, assignedSchoolIds = [], uid = null) => ({
  name, role, assignedSchoolIds, uid, createdAt: now,
});

async function link(user, id, role, schools) {
  await db.doc(`staff/${id}`).set(staffData(id, role, schools, user.uid));
  await db.doc(`staff_access/${user.uid}`).set({staffId: id});
}

function delivery(schoolId) {
  return {schoolId, schoolName: `School ${schoolId}`, date: now, createdAt: now, staffIds: [], staffNames: []};
}

test("roles, scoped queries, evidence and timers enforce the same boundary", async (t) => {
  const adminUser = await signUp("administrator");
  const manager = await signUp("manager");
  const field = await signUp("field");
  const outsider = await signUp("outside");
  const newUser = await signUp("invite");
  const duplicate = await signUp("duplicate");
  await link(adminUser, "admin", "admin");
  await link(manager, "manager", "manager");
  await link(field, "field", "staff", ["alpha", "charlie"]);
  await link(outsider, "outside", "staff", []);
  await db.doc("staff/new").set(staffData("New", "staff"));
  await db.doc("staff/dup").set(staffData("Duplicate", "staff"));
  await db.doc("staff/field").update({linkPin: "test-pin", calendarToken: "old-secret"});
  await db.doc("calendar_metadata/field").set({token: "old-secret"});
  await db.doc("schools/alpha").set({name: "Alpha", createdAt: now});
  await db.doc("schools/beta").set({name: "Beta", createdAt: now});
  await db.doc("schools/alpha/yearLevels/year/classrooms/base").set({name: "Room", createdAt: now});
  await db.doc("schools/beta/yearLevels/year/classrooms/base").set({name: "Room", createdAt: now});
  await db.doc("deliveries/alpha").set(delivery("alpha"));
  await db.doc("deliveries/beta").set(delivery("beta"));
  await db.doc("signed_school_summaries/beta").set({schoolId: "beta"});
  await db.doc("deliveries/alpha/preDeliveryChecklist/task").set({isCompleted: false});
  await db.doc("deliveries/beta/preDeliveryChecklist/task").set({isCompleted: false});

  await t.test("legacy fields and forged links give no privileges", async () => {
    await db.doc(`users/${outsider.uid}`).set({role: "admin", staffId: "admin"});
    await status(await write(`users/${newUser.uid}`, newUser, {role: "admin", uid: newUser.uid}), 403);
    await status(await write(`users/${field.uid}`, field, {role: "admin", uid: field.uid}), 403);
    await status(await write(`staff_access/${field.uid}`, field, {staffId: "admin"}), 403);
    await status(await write("staff/new", outsider, staffData("New", "admin", ["beta"], outsider.uid)), 403);
    await status(await write("staff/outside", outsider, staffData("Outside", "admin", ["beta"], outsider.uid)), 403);
    await status(await get("staff/field", manager), 403);
    await status(await get("calendar_metadata/field", outsider), 403);
    await status(await get("staff/field", field), 200);
    await status(await get("staff/field", adminUser), 200);
    await status(await get("schools/beta", outsider), 403);
    await status(await get("schools/alpha", newUser), 403);

    const userPath = `${root}/users/${newUser.uid}`;
    await status(await commit(newUser, [{
      update: {name: userPath, fields: fields({uid: newUser.uid, email: newUser.email})},
      updateTransforms: ["createdAt", "lastLoginAt"].map((fieldPath) =>
        ({fieldPath, setToServerValue: "REQUEST_TIME"})),
    }]), 200);
  });

  await t.test("invites are authorized, single-use and role-bound", async () => {
    await call("issueStaffInvite", manager, {staffId: "new"}, 403);
    await call("listStaffDirectory", field, {}, 403);
    const directory = await call("listStaffDirectory", manager, {});
    assert.ok(directory.staff.some(({id}) => id === "field"));
    assert.ok(directory.staff.every((row) => !("uid" in row) && !("calendarToken" in row) && !("linkPin" in row)));

    const {code: replaced} = await call("issueStaffInvite", adminUser, {staffId: "new"});
    const {code} = await call("issueStaffInvite", adminUser, {staffId: "new"});
    await call("redeemStaffInvite", newUser, {code: replaced}, 400);
    assert.deepEqual(await call("redeemStaffInvite", newUser, {code}), {staffId: "new"});
    await call("redeemStaffInvite", duplicate, {code}, 400);
    await status(await get("staff/new", newUser), 200);
    await status(await get("schools/beta", newUser), 403);

    const {code: staleRole} = await call("issueStaffInvite", adminUser, {staffId: "dup"});
    await db.doc("staff/dup").update({role: "manager"});
    await call("redeemStaffInvite", duplicate, {code: staleRole}, 400);
  });

  await t.test("assigned-school list queries and descendants work", async () => {
    const refs = (ids) => ids.map((id) => ({referenceValue: `${root}/schools/${id}`}));
    await status(await runQuery(field, "schools", inFilter("__name__", refs(["alpha", "charlie"]))), 200);
    await status(await runQuery(field, "schools", inFilter("__name__", refs(["alpha", "beta"]))), 403);
    await status(await runQuery(field, "schools"), 403);
    await status(await runQuery(manager, "schools"), 200);
    await status(await runQuery(field, "deliveries", inFilter("schoolId", ["alpha", "charlie"].map(value))), 200);
    await status(await runQuery(field, "deliveries"), 403);
    await status(await get("schools/alpha/yearLevels/year/classrooms/base", field), 200);
    await status(await get("schools/beta/yearLevels/year/classrooms/base", field), 403);
    await status(await get("signed_school_summaries/beta", field), 403);
    await status(await get("deliveries/beta/preDeliveryChecklist/task", field), 403);
    await status(await get("deliveries/alpha/preDeliveryChecklist/task", field), 200);
    await status(await write("deliveries/alpha/preDeliveryChecklist/task", field, {
      isCompleted: false, completedBy: null, completedAt: null,
    }), 200);
    await status(await write("deliveries/alpha", field, delivery("beta")), 403);
  });

  await t.test("prepareVisit publishes complete, isolated workspaces exactly once", async () => {
    const year = "schools/alpha/yearLevels/year";
    const template = year + "/classrooms/base";
    const workspace = "deliveries/alpha/workspace/alpha";
    const room = workspace + "/yearLevels/year/classrooms/base";
    const later = "deliveries/alpha-later/workspace/alpha/yearLevels/year/classrooms/base";
    await db.doc("deliveries/alpha-later").set(delivery("alpha"));
    await db.doc(year).set({label: "Year 1", createdAt: now});
    await db.doc(template).set({
      name: "Room", completionStatus: "complete", actualPacksDelivered: 9, createdAt: now,
    });
    await db.doc(template + "/packTotals/old").set({
      total: 1, createdAt: admin.firestore.Timestamp.fromMillis(now.toMillis() - 1000),
    });
    await db.doc(template + "/packTotals/current").set({total: 12, createdAt: now});
    await db.doc(template + "/consumables/pens").set({
      itemName: "Pens", quantity: 6, actualQuantityDelivered: 4, unit: "box", createdAt: now,
    });
    await db.doc(template + "/notes/legacy").set({content: "Previous visit", createdAt: now});

    await status(await write(template, field, {
      name: "Changed template", completionStatus: "complete", actualPacksDelivered: 9, createdAt: now,
    }), 403);
    await status(await write(template + "/packTotals/current", field, {total: 1000, createdAt: now}), 403);
    await status(await write(template + "/packTotals/current", manager, {total: 12, createdAt: now}), 200);
    await status(await remove(template, field), 403);
    await status(await get(workspace, field), 404);
    await status(await get(room, field), 403);
    await call("prepareVisit", outsider, {deliveryId: "alpha", schoolId: "alpha"}, 403);
    await call("prepareVisit", field, {deliveryId: "alpha", schoolId: "beta"}, 403);
    const preparations = await Promise.all([
      call("prepareVisit", field, {deliveryId: "alpha", schoolId: "alpha"}),
      call("prepareVisit", manager, {deliveryId: "alpha", schoolId: "alpha"}),
    ]);
    assert.deepEqual(preparations.map(({alreadyPrepared}) => alreadyPrepared).sort(), [false, true]);
    await status(await get(workspace, field), 200);
    await status(await get(room, outsider), 403);
    await status(await get(room + "/notes/legacy", field), 404);
    await status(await get(room + "/packTotals/old", field), 404);
    await status(await get(room + "/packTotals/current", field), 200);
    assert.equal((await db.doc(room).get()).get("completionStatus"), "notAttended");
    assert.equal((await db.doc(room + "/consumables/pens").get()).get("actualQuantityDelivered"), null);
    await status(await write(room, field, {
      name: "Room", completionStatus: "incomplete", actualPacksDelivered: 3, createdAt: now,
    }), 200);
    await status(await write(room, field, {
      name: "Room", completionStatus: "incomplete", actualPacksDelivered: -1, createdAt: now,
    }), 403);
    await status(await write(room + "/consumables/pens", field, {
      itemName: "Pens", quantity: 6, actualQuantityDelivered: 3, unit: "box", createdAt: now,
    }), 200);
    assert.equal((await call("prepareVisit", field, {deliveryId: "alpha", schoolId: "alpha"})).alreadyPrepared, true);
    assert.equal((await db.doc(room).get()).get("actualPacksDelivered"), 3);
    await call("prepareVisit", field, {deliveryId: "alpha-later", schoolId: "alpha"});
    assert.equal((await db.doc(later).get()).get("actualPacksDelivered"), null);
    await status(await write("deliveries/alpha", manager, delivery("beta")), 403);
    await status(await remove("deliveries/alpha", adminUser), 403);
  });

  await t.test("ordinary classroom changes and classroom audit commit atomically", async () => {
    const classroom = "deliveries/alpha/workspace/alpha/yearLevels/year/classrooms/base";
    const note = `${classroom}/notes/00000000-0000-4000-8000-000000000011`;
    const noteFields = {content: "Leave boxes by the door", author: "Field worker", createdAt: now};
    const noteWrite = {update: {name: `${root}/${note}`, fields: fields(noteFields)}};
    const audit = {
      update: {name: `${root}/${classroom}`, fields: fields({lastUpdatedBy: "Field worker"})},
      updateMask: {fieldPaths: ["lastUpdatedBy"]},
      updateTransforms: [{fieldPath: "lastUpdatedAt", setToServerValue: "REQUEST_TIME"}],
    };

    // An invalid audit change rejects the entire batch, including the valid note.
    const forbiddenAudit = {
      ...audit,
      update: {
        ...audit.update,
        fields: fields({lastUpdatedBy: "Field worker", createdAt: null}),
      },
      updateMask: {fieldPaths: ["lastUpdatedBy", "createdAt"]},
    };
    await status(await commit(field, [noteWrite, forbiddenAudit]), 403);
    await status(await get(note, field), 404);

    await status(await commit(field, [noteWrite, audit]), 200);
    assert.equal((await db.doc(note).get()).get("content"), noteFields.content);
    const updated = (await db.doc(classroom).get()).data();
    assert.equal(updated.lastUpdatedBy, "Field worker");
    assert.ok(updated.lastUpdatedAt instanceof admin.firestore.Timestamp);

    const consumable = `${classroom}/consumables/pens`;
    await db.doc(consumable).update({quantity: 18});
    await status(await commit(field, [
      {
        update: {name: `${root}/${consumable}`, fields: fields({actualQuantityDelivered: 9})},
        updateMask: {fieldPaths: ["actualQuantityDelivered"]},
      },
      audit,
    ]), 200);
    const supply = (await db.doc(consumable).get()).data();
    assert.equal(supply.quantity, 18);
    assert.equal(supply.actualQuantityDelivered, 9);

    await status(await commit(field, [{delete: `${root}/${note}`}, audit]), 200);
    await status(await get(note, field), 404);
  });

  await t.test("signoffs are visit-bound, append-only and scoped to the signing account", async () => {
    const operation = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa";
    const capture = {
      id: operation,
      schoolId: "alpha",
      deliveryId: "alpha",
      ownerUid: field.uid,
      signaturePath: `schools/alpha/signoffs/${operation}.png`,
      capturedAt: now,
      reviewStatus: "cached",
      ...visitSignaturePayload,
    };
    const path = `schools/alpha/signoffs/${operation}`;
    const pointer = "schools/alpha/signoffPointers/visit-alpha";
    await status(await write(path, outsider, {...capture, ownerUid: outsider.uid}), 403);
    await status(await write(path, field, {...capture, reviewStatus: "serverReviewed"}), 403);
    await status(await write(path, field, {...capture, deliveryId: "beta"}), 403);
    const snapshot = capture.snapshot;
    const {reviewChecklist, ...legacySummary} = snapshot.summary;
    assert.equal(reviewChecklist.length, 1);
    for (const summary of [
      {...snapshot.summary, reviewChecklist: {id: "invalid"}},
      {...snapshot.summary, reviewChecklist: Array(501).fill(reviewChecklist[0])},
      {...snapshot.summary, unsupportedMetadata: []},
    ]) {
      await status(await write(path, field, {...capture, snapshot: {...snapshot, summary}}), 403);
    }

    for (const [id, summary] of [
      ["aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaab", legacySummary],
      ["aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaac", {...legacySummary, reviewChecklist: []}],
    ]) {
      await status(await write(`schools/alpha/signoffs/${id}`, field, {
        ...capture,
        id,
        signaturePath: `schools/alpha/signoffs/${id}.png`,
        snapshot: {...snapshot, summary},
      }), 200);
    }

    const pointerData = {evidenceId: operation, deliveryId: "alpha", capturedAt: now};
    await status(await commit(field, [
      {update: {name: `${root}/${path}`, fields: fields(capture)}},
      {update: {name: `${root}/${pointer}`, fields: fields(pointerData)}},
    ]), 200);
    await status(await get(pointer, field), 200);
    const savedCapture = (await db.doc(path).get()).data();
    assert.equal(savedCapture.typedName, visitSignaturePayload.typedName);
    assert.deepEqual(savedCapture.snapshot, visitSignaturePayload.snapshot);
    await status(await get(path, outsider), 403);
    await status(await write(path, field, {...capture, typedName: "Changed"}), 403);
    await status(await remove(path, adminUser), 403);
    await status(await write("schools/alpha/signoffPointers/visit-alpha-later", field, pointerData), 403);
    await status(await write("schools/alpha/meta/signoff", manager, {typedName: "Old"}), 403);
  });

  await t.test("school Storage objects enforce scope and immutability", async () => {
    const path = "schools/alpha/signoffs/aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa.png";
    const probe = "schools/alpha/maps/example.txt";
    await status(await upload(probe, {idToken: "owner"}, field.uid), 200);
    await status(await request(`${storage}/${encodeURIComponent(probe)}`, field), 200);
    await status(await request(`${storage}/${encodeURIComponent(probe)}`, outsider), 403);
    await status(await upload(path, field, outsider.uid), 403);
    await status(await upload(path, outsider, outsider.uid), 403);
    await status(await upload(path, field, field.uid, "text/html"), 403);
    await status(await upload(path, field, field.uid), 200);
    await status(await upload(path, field, field.uid), 403);
    await status(await request(`${storage}/${encodeURIComponent(path)}`, field), 200);
    await status(await request(`${storage}/${encodeURIComponent(path)}`, outsider), 403);
    await status(await request(`${storage}/${encodeURIComponent(path)}`, field, {method: "DELETE"}), 403);
    const photo = "deliveries/alpha/workspace/alpha/yearLevels/year/classrooms/base/photos/bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb.jpg";
    await status(await upload(photo, field, field.uid, "image/jpeg"), 200);
    await status(await upload(photo, field, field.uid, "image/jpeg"), 403);
    await status(await request(`${storage}/${encodeURIComponent(photo)}`, field, {method: "DELETE"}), 403);
    await status(await request(`${storage}/${encodeURIComponent(photo)}`, adminUser, {method: "DELETE"}), 403);
    await status(await request(`${storage}/${encodeURIComponent(photo)}`, outsider), 403);
    const photoDoc = photo.slice(0, -4);
    const classroom = photoDoc.split("/photos/")[0];
    await status(await write(photoDoc, field, {storagePath: photo, uploadedBy: field.uid, uploadedAt: now}), 200);
    await status(await commit(field, [
      {delete: `${root}/${photoDoc}`},
      {
        update: {name: `${root}/${classroom}`, fields: fields({lastUpdatedBy: "Field worker"})},
        updateMask: {fieldPaths: ["lastUpdatedBy"]},
        updateTransforms: [{fieldPath: "lastUpdatedAt", setToServerValue: "REQUEST_TIME"}],
      },
    ]), 200);
    await status(await get(photoDoc, field), 404);
    await status(await request(`${storage}/${encodeURIComponent(photo)}`, field), 200);
    await status(await upload(photo, field, field.uid, "image/jpeg"), 403);

  });

  await t.test("photo records accept only the optional subject tags", async () => {
    let next = 0;
    const photoAt = (base) => {
      const id = `dddddddd-dddd-dddd-dddd-${String(++next).padStart(12, "0")}`;
      const doc = `${base}/photos/${id}`;
      return {doc, data: {id, storagePath: `${doc}.jpg`, uploadedBy: field.uid, uploadedAt: now}};
    };
    const school = "schools/alpha/yearLevels/year/classrooms/base";
    const visit = "deliveries/alpha/workspace/alpha/yearLevels/year/classrooms/base";
    const accepts = async (base, extra) => {
      const {doc, data} = photoAt(base);
      await status(await write(doc, field, {...data, ...extra}), 200);
      return {doc, data: {...data, ...extra}};
    };
    const rejects = async (extra) => {
      const {doc, data} = photoAt(school);
      await status(await write(doc, field, {...data, ...extra}), 403);
    };
    const tissues = {subjectType: "consumable", subjectId: "Xk3pQ9aB7cD1eF2gH4iJ", subjectLabel: "Tissues"};

    // Untagged photos keep the original document shape on both paths.
    const general = await accepts(school, {});
    await accepts(visit, {});
    // Packs and consumable photos on both paths.
    await accepts(school, {subjectType: "packs"});
    await accepts(visit, {subjectType: "packs"});
    const tagged = await accepts(school, tissues);
    await accepts(visit, tissues);
    await accepts(visit, {...tissues, subjectId: "paper"});
    await accepts(school, {...tissues, subjectLabel: "x".repeat(100)});
    assert.deepEqual((await db.doc(tagged.doc).get()).data().subjectLabel, "Tissues");

    await rejects({subjectType: "headphones"});
    await rejects({subjectType: null});
    await rejects({subjectType: "packs", subjectId: "Xk3pQ9aB7cD1eF2gH4iJ"});
    await rejects({subjectType: "packs", subjectLabel: "Packs"});
    await rejects({subjectType: "consumable", subjectLabel: "Tissues"});
    await rejects({subjectType: "consumable", subjectId: "", subjectLabel: "Tissues"});
    await rejects({...tissues, subjectId: "../other"});
    await rejects({...tissues, subjectId: "x".repeat(129)});
    await rejects({subjectType: "consumable", subjectId: "Xk3pQ9aB7cD1eF2gH4iJ"});
    await rejects({...tissues, subjectLabel: "x".repeat(101)});
    await rejects({...tissues, subjectLabel: 7});
    await rejects({subjectId: "Xk3pQ9aB7cD1eF2gH4iJ"});
    await rejects({subjectLabel: "Tissues"});
    await rejects({subjectId: "Xk3pQ9aB7cD1eF2gH4iJ", subjectLabel: "Tissues"});
    await rejects({...tissues, caption: "Tissues"});
    await rejects({caption: "General"});

    // Photo records stay create/delete only: no retagging or untagging.
    await status(await write(general.doc, field, {...general.data, subjectType: "packs"}), 403);
    await status(await write(tagged.doc, field, {...tagged.data, subjectLabel: "Headphones"}), 403);
    const untagged = {...tagged.data};
    for (const key of ["subjectType", "subjectId", "subjectLabel"]) delete untagged[key];
    await status(await write(tagged.doc, field, untagged), 403);
    await status(await write(tagged.doc, field, tagged.data), 403);
  });

  await t.test("school logos are small JPEGs managed by admins and managers", async () => {
    const logo = "schools/alpha/logo/cccccccc-cccc-cccc-cccc-cccccccccccc.jpg";
    const logoUrl = `${storage}/${encodeURIComponent(logo)}`;
    // Assigned field staff and outsiders cannot write a logo.
    await status(await upload(logo, field, field.uid, "image/jpeg"), 403);
    await status(await upload(logo, outsider, outsider.uid, "image/jpeg"), 403);
    // Wrong content type, bad file name, oversize and empty files are rejected.
    await status(await upload(logo, manager, manager.uid, "image/png"), 403);
    await status(await upload(logo, manager, manager.uid, "text/html"), 403);
    await status(await upload("schools/alpha/logo/logo.jpg", manager, manager.uid, "image/jpeg"), 403);
    await status(await upload(
        "schools/alpha/logo/cccccccc-cccc-cccc-cccc-cccccccccccc.png", manager, manager.uid, "image/jpeg"), 403);
    await status(await upload(logo, manager, manager.uid, "image/jpeg", "x".repeat(2 * 1024 * 1024 + 1)), 403);
    await status(await upload(logo, manager, manager.uid, "image/jpeg", ""), 403);
    // A manager can add one and an admin can replace it.
    await status(await upload(logo, manager, manager.uid, "image/jpeg"), 200);
    await status(await upload(logo, adminUser, adminUser.uid, "image/jpeg"), 200);
    // Staff with access to the school can read it; others cannot.
    await status(await request(logoUrl, field), 200);
    await status(await request(logoUrl, outsider), 403);
    const betaLogo = "schools/beta/logo/dddddddd-dddd-dddd-dddd-dddddddddddd.jpg";
    await status(await upload(betaLogo, adminUser, adminUser.uid, "image/jpeg"), 200);
    await status(await request(`${storage}/${encodeURIComponent(betaLogo)}`, field), 403);
    // Only management can delete it.
    await status(await request(logoUrl, field, {method: "DELETE"}), 403);
    await status(await request(logoUrl, outsider, {method: "DELETE"}), 403);
    await status(await request(logoUrl, manager, {method: "DELETE"}), 204);
    await status(await request(logoUrl, field), 404);
  });

  await t.test("manager timer stop is atomic and history is immutable to managers", async () => {
    const active = `${root}/schools/alpha/timers/active`;
    const sessionId = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa";
    const timer = {
      schoolId: "alpha",
      startedByUid: "manager",
      startedByName: "Manager",
      isActive: true,
      sessionId,
    };
    const start = [{
      update: {name: active, fields: fields(timer)},
      updateTransforms: ["startedAt", "createdAt"].map((fieldPath) =>
        ({fieldPath, setToServerValue: "REQUEST_TIME"})),
    }];
    await status(await commit(field, start), 403);
    await status(await commit(manager, start), 200);
    await status(await commit(manager, start), 403);
    const activeDoc = (await db.doc("schools/alpha/timers/active").get()).data();
    const stopped = {isActive: false, stoppedByUid: "manager", stoppedByName: "Manager"};
    const history = `${active}/history/${sessionId}`;
    const stop = [
      {
        update: {name: active, fields: fields(stopped)},
        updateMask: {fieldPaths: Object.keys(stopped)},
        updateTransforms: [{fieldPath: "stoppedAt", setToServerValue: "REQUEST_TIME"}],
      },
      {
        update: {name: history, fields: (await (await get("schools/alpha/timers/active", manager)).json()).fields},
        updateTransforms: [{fieldPath: "stoppedAt", setToServerValue: "REQUEST_TIME"}],
      },
    ];
    Object.assign(stop[1].update.fields, fields(stopped));
    await status(await commit(manager, [stop[0]]), 403);
    await status(await commit(manager, [stop[1]]), 403);
    await status(await commit(manager, stop), 200);
    await status(await commit(manager, stop), 403);
    assert.equal((await db.collection("schools/alpha/timers/active/history").get()).size, 1);
    await status(await remove(`schools/alpha/timers/active/history/${sessionId}`, manager), 403);
    await status(await write(`schools/alpha/timers/active/history/${sessionId}`, adminUser, {
      ...activeDoc, ...stopped, stoppedAt: admin.firestore.Timestamp.now(),
    }), 200);
  });

  await t.test("auto-stop only archives the expected expired timer once", async () => {
    const {sessionId, stopExpiredTimer} = require("../lib/timer-auto-stop");
    const ref = db.doc("deliveries/alpha/workspace/alpha/timers/active");
    const startedAt = admin.firestore.Timestamp.fromMillis(now.toMillis() - 6 * 60 * 60 * 1000);
    const legacy = {
      schoolId: "alpha", isActive: true, startedAt, createdAt: startedAt,
      startedByUid: "manager", startedByName: "Manager",
    };
    await ref.set(legacy);
    assert.equal(await stopExpiredTimer(db, ref, "a-different-timer", now), false);
    const id = sessionId(legacy);
    const stopped = await Promise.all([
      stopExpiredTimer(db, ref, id, now),
      stopExpiredTimer(db, ref, id, now),
    ]);
    assert.deepEqual(stopped.sort(), [false, true]);
    assert.equal((await ref.collection("history").get()).size, 1);
    assert.equal((await ref.collection("history").doc(id).get()).get("stoppedByUid"), "system");
    await ref.set({...legacy, sessionId: "new-session"});
    assert.equal(await stopExpiredTimer(db, ref, id, now), false);
    assert.equal((await ref.get()).get("isActive"), true);
  });

  await t.test("calendar tokens and feed honor live assignments and rotation", async () => {
    await call("calendarSubscriptionToken", field, {staffId: "outside"}, 403);
    await status(await get("calendar_tokens/field", field), 403);
    const {token: empty} = await call("calendarSubscriptionToken", outsider, {staffId: "outside"});
    const emptyFeed = await request(`${functions}/calendar/${empty}.ics`);
    assert.equal(emptyFeed.status, 200);
    assert.doesNotMatch(await emptyFeed.text(), /BEGIN:VEVENT/);

    const {token} = await call("calendarSubscriptionToken", field, {staffId: "field"});
    const feed = await request(`${functions}/calendar/${token}.ics`);
    assert.equal(feed.status, 200);
    const calendar = await feed.text();
    assert.match(calendar, /School alpha/);
    assert.doesNotMatch(calendar, /School beta/);
    await db.doc("staff/field").update({assignedSchoolIds: ["beta"]});
    const revised = await request(`${functions}/calendar/${token}.ics`);
    assert.match(await revised.text(), /School beta/);

    await db.doc("deliveries/beta").delete();
    const deadline = Date.now() + 10_000;
    let updated = false;
    do {
      const metadata = await db.doc("calendar_metadata/field").get();
      updated = metadata.get("lastDeliveryChange") != null;
      if (!updated) await new Promise((resolve) => setTimeout(resolve, 200));
    } while (!updated && Date.now() < deadline);
    assert.ok(updated, "deleted delivery updated its affected subscription metadata");

    const {token: replaced} = await call("calendarSubscriptionToken", field, {staffId: "field", rotate: true});
    assert.notEqual(token, replaced);
    await status(await request(`${functions}/calendar/${token}.ics`), 404);
    await db.doc("staff_access/" + field.uid).delete();
    await status(await request(`${functions}/calendar/${replaced}.ics`), 404);
    await status(await get("schools/beta", field), 403);
  });
});
