// Synthetic fixture for exercising the iOS offline workflow against Firebase
// emulators. Start the emulators for demo-bts-delivery first, then run:
// FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 FIREBASE_AUTH_EMULATOR_HOST=127.0.0.1:9099 \
// FIREBASE_STORAGE_EMULATOR_HOST=127.0.0.1:9199 node functions/scripts/seed-offline-demo.cjs
const {createHash} = require("node:crypto");

const project = "demo-bts-delivery";
const hosts = {
  FIRESTORE_EMULATOR_HOST: 8080,
  FIREBASE_AUTH_EMULATOR_HOST: 9099,
  FIREBASE_STORAGE_EMULATOR_HOST: 9199,
};
const auth = `http://127.0.0.1:9099/identitytoolkit.googleapis.com/v1/projects/${project}/accounts`;
const documents = `projects/${project}/databases/(default)/documents`;
const firestore = `http://127.0.0.1:8080/v1/${documents}`;
const storage = `http://127.0.0.1:9199/v0/b/${project}.appspot.com/o`;
const schoolId = "refresh-demo-school";
const school = {
  name: "Demo School — North and South Campus",
  address: "Synthetic school for offline testing",
  schoolMapUrl: `schools/${schoolId}/map/offline-demo.pdf`,
};
const fixtureAccounts = [
  {uid: "refresh-demo-admin", email: "refresh-admin@example.test", name: "Demo Manager", role: "admin"},
  {uid: "refresh-demo-field", email: "refresh-field@example.test", name: "Demo Delivery Staff", role: "staff"},
];
const field = fixtureAccounts[1];
const password = "Demo-only-2026!";
const visits = [
  ["refresh-visit-1", "First visit — offline recovery checks"],
  ["refresh-visit-2", "Second visit — isolation checks"],
];
const restoreMissingMedia = process.argv[2] === "--restore-missing-media";
const createdAt = new Date();
const today = new Date(createdAt);
today.setHours(0, 0, 0, 0);

function requireDemoEnvironment() {
  if (process.argv.length !== 2 && !(process.argv.length === 3 && restoreMissingMedia)) {
    throw new Error("This seed only uses demo-bts-delivery. The only option is --restore-missing-media.");
  }
  for (const [name, port] of Object.entries(hosts)) {
    if (![`127.0.0.1:${port}`, `localhost:${port}`].includes(process.env[name])) {
      throw new Error(`Set ${name}=127.0.0.1:${port} to run this demo seed.`);
    }
  }
  for (const name of ["GCLOUD_PROJECT", "GOOGLE_CLOUD_PROJECT", "FIREBASE_PROJECT_ID"]) {
    if (process.env[name] && process.env[name] !== project) {
      throw new Error(`Use ${project} in ${name} before running this demo seed.`);
    }
  }
  if (process.env.FIREBASE_CONFIG) {
    let config;
    try {
      config = JSON.parse(process.env.FIREBASE_CONFIG);
    } catch {
      throw new Error("FIREBASE_CONFIG must be inline demo JSON or unset.");
    }
    if (config?.projectId !== project) {
      throw new Error(`FIREBASE_CONFIG must use ${project}.`);
    }
  }
}

async function request(url, options = {}) {
  // Synthetic owner sentinel understood by the local emulators. No SDK, real
  // credentials, caller-supplied endpoints, or HTTP redirects are used.
  return fetch(url, {
    ...options,
    headers: {Authorization: "Bearer owner", ...options.headers},
    redirect: "error",
    signal: AbortSignal.timeout(10_000),
  });
}

function postJson(url, body) {
  return request(url, {
    method: "POST",
    headers: {"Content-Type": "application/json"},
    body: JSON.stringify(body),
  });
}

function requireOk(response, action) {
  if (!response.ok) throw new Error(`${action} failed with HTTP ${response.status}.`);
}

async function getDocument(path) {
  const response = await request(`${firestore}/${path}`);
  if (response.status === 404) return null;
  requireOk(response, "Reading a demo document");
  return response.json();
}

function encode(value) {
  if (value == null) return {nullValue: null};
  if (value instanceof Date) return {timestampValue: value.toISOString()};
  if (Array.isArray(value)) return {arrayValue: {values: value.map(encode)}};
  if (typeof value === "string") return {stringValue: value};
  if (typeof value === "boolean") return {booleanValue: value};
  if (Number.isInteger(value)) return {integerValue: String(value)};
  if (typeof value === "object") return {mapValue: {fields: fields(value)}};
  throw new Error("A demo document contains an unsupported value.");
}

function fields(data) {
  return Object.fromEntries(Object.entries(data).map(([key, value]) => [key, encode(value)]));
}

// A workspace and all its initial rows appear in one create-only commit.
// A rerun leaves the existing subtree alone, including deletions made in-app.
async function createFixture(root, entries, beforeCreate) {
  if (await getDocument(root)) return false;
  await beforeCreate?.();
  const response = await postJson(`${firestore}:commit`, {
    writes: entries.map(([path, data]) => ({
      update: {name: `${documents}/${path}`, fields: fields(data)},
      currentDocument: {exists: false},
    })),
  });
  if ((response.status === 400 || response.status === 409 || response.status === 412) &&
      await getDocument(root)) {
    return false; // A concurrent seed created it first.
  }
  requireOk(response, "Creating demo Firestore fixtures");
  return true;
}

async function ensureAccount(account) {
  const lookup = await postJson(`${auth}:lookup`, {localId: [account.uid]});
  requireOk(lookup, "Looking up a demo Auth account");
  const current = (await lookup.json()).users?.[0];
  if (current) {
    if (current.email !== account.email) {
      throw new Error("An existing demo Auth ID has a different email.");
    }
  } else {
    const response = await postJson(auth, {
      localId: account.uid,
      email: account.email,
      password,
      displayName: account.name,
      emailVerified: true,
    });
    requireOk(response, "Creating a demo Auth account");
  }
  const staff = `staff/${account.uid}`;
  await createFixture(staff, [[staff, {
    uid: account.uid,
    name: account.name,
    role: account.role,
    assignedSchoolIds: [schoolId],
    createdAt,
  }]]);
  const mapping = `staff_access/${account.uid}`;
  // The demo administrator is also a super admin so team control can be tried.
  await createFixture(mapping, [[mapping, account.role === "admin" ?
    {staffId: account.uid, superAdmin: true} : {staffId: account.uid}]]);
  const link = await getDocument(mapping);
  if (link?.fields?.staffId?.stringValue !== account.uid) {
    throw new Error("An existing demo Auth ID has a different staff link.");
  }
  const user = `users/${account.uid}`;
  await createFixture(user, [[user, {uid: account.uid, email: account.email, createdAt, lastLoginAt: createdAt}]]);
}

function classroomRows(root) {
  const year = `${root}/yearLevels/year-1`;
  return [
    [year, {label: "Year 1", createdAt}],
    ...["a", "b"].flatMap((key) => {
      const classroom = `${year}/classrooms/room-${key}`;
      return [
        [classroom, {
          name: `Classroom ${key.toUpperCase()}`,
          completionStatus: "notAttended",
          actualPacksDelivered: null,
          createdAt,
        }],
        [`${classroom}/packTotals/expected`, {total: 24, createdAt}],
        [`${classroom}/consumables/paper`, {
          itemName: "Copy paper",
          quantity: 3,
          unit: "boxes",
          actualQuantityDelivered: null,
          createdAt,
        }],
      ];
    }),
  ];
}

async function ensureStorageObject(path, contentType, bytes) {
  const encoded = encodeURIComponent(path);
  const existing = await request(`${storage}/${encoded}`);
  if (existing.ok) return false;
  if (existing.status !== 404) requireOk(existing, "Checking demo media");

  const boundary = "offline-demo-fixture-multipart";
  const metadata = {
    contentType,
    metadata: {
      uploadedBy: field.uid,
      sha256: createHash("sha256").update(bytes).digest("hex"),
    },
  };
  const response = await request(`${storage}?name=${encoded}&ifGenerationMatch=0`, {
    method: "POST",
    headers: {
      "Content-Type": `multipart/related; boundary=${boundary}`,
      "X-Goog-Upload-Protocol": "multipart",
    },
    body: Buffer.concat([
      Buffer.from(`--${boundary}\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n${JSON.stringify(metadata)}\r\n`),
      Buffer.from(`--${boundary}\r\nContent-Type: ${contentType}\r\n\r\n`),
      bytes,
      Buffer.from(`\r\n--${boundary}--\r\n`),
    ]),
  });
  requireOk(response, "Creating demo media");
  return true;
}

function makeMapPdf() {
  const page = [
    "0.96 0.97 1 rg 25 25 450 280 re f",
    "0.1 0.2 0.4 rg BT /F1 26 Tf 50 260 Td (Offline demo school map) Tj ET",
    "0.15 0.45 0.72 RG 3 w 50 108 175 108 re S 275 108 175 108 re S",
    "0.1 0.2 0.4 rg BT /F1 18 Tf 73 160 Td (Classroom A) Tj ET",
    "BT /F1 18 Tf 298 160 Td (Classroom B) Tj ET",
    "BT /F1 12 Tf 176 63 Td (Synthetic fixture) Tj ET",
  ].join("\n");
  const objects = [
    "<< /Type /Catalog /Pages 2 0 R >>",
    "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
    "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 500 330] /Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R >>",
    "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
    `<< /Length ${Buffer.byteLength(page)} >>\nstream\n${page}\nendstream`,
  ];
  let pdf = "%PDF-1.4\n";
  const offsets = [];
  for (const [index, object] of objects.entries()) {
    offsets.push(Buffer.byteLength(pdf));
    pdf += `${index + 1} 0 obj\n${object}\nendobj\n`;
  }
  const xref = Buffer.byteLength(pdf);
  pdf += `xref\n0 ${offsets.length + 1}\n0000000000 65535 f \n`;
  for (const offset of offsets) pdf += `${String(offset).padStart(10, "0")} 00000 n \n`;
  pdf += `trailer\n<< /Size ${offsets.length + 1} /Root 1 0 R >>\nstartxref\n${xref}\n%%EOF\n`;
  return Buffer.from(pdf);
}

// JPEG of synthetic boxes/room artwork, embedded to keep the fixture portable.
const demoPhoto = Buffer.from([
  "/9j/4AAQSkZJRgABAQAASABIAAD/4QBMRXhpZgAATU0AKgAAAAgAAYdpAAQAAAABAAAAGgAAAAAAA6ABAAMAAAABAAEAAKAC",
  "AAQAAAABAAABQKADAAQAAAABAAAA1QAAAAD/wAARCADVAUADASIAAhEBAxEB/8QAHwAAAQUBAQEBAQEAAAAAAAAAAAECAwQF",
  "BgcICQoL/8QAtRAAAgEDAwIEAwUFBAQAAAF9AQIDAAQRBRIhMUEGE1FhByJxFDKBkaEII0KxwRVS0fAkM2JyggkKFhcYGRol",
  "JicoKSo0NTY3ODk6Q0RFRkdISUpTVFVWV1hZWmNkZWZnaGlqc3R1dnd4eXqDhIWGh4iJipKTlJWWl5iZmqKjpKWmp6ipqrKz",
  "tLW2t7i5usLDxMXGx8jJytLT1NXW19jZ2uHi4+Tl5ufo6erx8vP09fb3+Pn6/8QAHwEAAwEBAQEBAQEBAQAAAAAAAAECAwQF",
  "BgcICQoL/8QAtREAAgECBAQDBAcFBAQAAQJ3AAECAxEEBSExBhJBUQdhcRMiMoEIFEKRobHBCSMzUvAVYnLRChYkNOEl8RcY",
  "GRomJygpKjU2Nzg5OkNERUZHSElKU1RVVldYWVpjZGVmZ2hpanN0dXZ3eHl6goOEhYaHiImKkpOUlZaXmJmaoqOkpaanqKmq",
  "srO0tba3uLm6wsPExcbHyMnK0tPU1dbX2Nna4uPk5ebn6Onq8vP09fb3+Pn6/9sAQwAMDAwMDAwVDAwVHhUVFR4pHh4eHikz",
  "KSkpKSkzPjMzMzMzMz4+Pj4+Pj4+SkpKSkpKV1dXV1dhYWFhYWFhYWFh/9sAQwEPEBAZFxkrFxcrZkU5RWZmZmZmZmZmZmZm",
  "ZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmZm/90ABAAU/9oADAMBAAIRAxEAPwD0eiiitDIKKKKACiii",
  "gAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKAP//Q",
  "9HooorQyCiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAoo",
  "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",
  "J2//AD3f8hR/widv/wA93/IV1lFHPLuHJHscn/widv8A893/ACFH/CJ2/wDz3f8AIV1lFHPLuHJHscn/AMInb/8APd/yFH/C",
  "J2//AD3f8hXWUUc8u4ckexyf/CJ2/wDz3f8AIUf8Inb/APPd/wAhXWUUc8u4ckexyf8Awidv/wA93/IUf8Inb/8APd/yFdZR",
  "Rzy7hyR7HJ/8Inb/APPd/wAhR/widv8A893/ACFdZRRzy7hyR7HJ/wDCJ2//AD3f8hR/widv/wA93/IV1lFHPLuHJHscn/wi",
  "dv8A893/ACFH/CJ2/wDz3f8AIV1lFHPLuHJHscn/AMInb/8APd/yFH/CJ2//AD3f8hXWUUc8u4ckexyf/CJ2/wDz3f8AIUf8",
  "Inb/APPd/wAhXWUUc8u4ckexyf8Awidv/wA93/IUf8Inb/8APd/yFdZRRzy7hyR7HJ/8Inb/APPd/wAhR/widv8A893/ACFd",
  "ZRRzy7hyR7GHpuhxadcG4SRnJUrggd63KKKltvcpJLYKKKKQz//T9HooorQyCiiigAooooAKKKKACiiigAooooAKKKKACiii",
  "gAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigD//1PR6KKK0MgooooAKKKKACiiigAoo",
  "ooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooA//9k=",
].join(""), "base64");

async function ensureVisit(deliveryId, notes, includePhoto) {
  const delivery = `deliveries/${deliveryId}`;
  await createFixture(delivery, [[delivery, {
    schoolId,
    schoolName: school.name,
    date: today,
    staffIds: [field.uid],
    staffNames: [field.name],
    palletCount: 4,
    notes,
    createdAt,
  }]]);
  const existing = await getDocument(delivery);
  if (existing?.fields?.schoolId?.stringValue !== schoolId) {
    throw new Error("An existing demo delivery points to a different school.");
  }
  const workspace = `${delivery}/workspace/${schoolId}`;
  const room = `${workspace}/yearLevels/year-1/classrooms/room-a`;
  const photo = `${room}/photos/demo-photo`;
  const classroom = classroomRows(workspace);
  const collections = {};
  for (const [path] of classroom) {
    const collection = path.slice(workspace.length + 1, path.lastIndexOf("/"));
    collections[collection] = (collections[collection] ?? 0) + 1;
  }
  return createFixture(workspace, [
    [workspace, {
      schoolId,
      deliveryId,
      status: "ready",
      name: school.name,
      address: school.address,
      createdAt,
      preparedAt: createdAt,
      inventory: collections,
    }],
    ...classroom,
    ...(includePhoto ? [[photo, {
      storagePath: `${photo}.jpg`,
      uploadedBy: field.uid,
      uploadedAt: createdAt,
    }]] : []),
  ], includePhoto ? () => ensureStorageObject(`${photo}.jpg`, "image/jpeg", demoPhoto) : undefined);
}

async function restoreReferencedMedia() {
  const schoolDoc = await getDocument(`schools/${schoolId}`);
  const mapRef = schoolDoc?.fields?.schoolMapStoragePath?.stringValue ??
    schoolDoc?.fields?.schoolMapUrl?.stringValue;
  const photoDocPath =
    `deliveries/${visits[0][0]}/workspace/${schoolId}/yearLevels/year-1/classrooms/room-a/photos/demo-photo`;
  const photoDoc = await getDocument(photoDocPath);
  const photoPath = `${photoDocPath}.jpg`;
  let restored = 0;
  if (mapRef === school.schoolMapUrl &&
      await ensureStorageObject(mapRef, "application/pdf", makeMapPdf())) {
    restored++;
  }
  if (photoDoc?.fields?.storagePath?.stringValue === photoPath &&
      photoDoc?.fields?.uploadedBy?.stringValue === field.uid &&
      await ensureStorageObject(photoPath, "image/jpeg", demoPhoto)) {
    restored++;
  }
  console.log(`Restored ${restored} missing demo media files.`);
}

async function main() {
  requireDemoEnvironment();
  for (const account of fixtureAccounts) await ensureAccount(account);

  const schoolPath = `schools/${schoolId}`;
  await createFixture(schoolPath, [[schoolPath, {...school, createdAt}], ...classroomRows(schoolPath)],
    () => ensureStorageObject(school.schoolMapUrl, "application/pdf", makeMapPdf()));
  for (const [index, [deliveryId, notes]] of visits.entries()) {
    const created = await ensureVisit(deliveryId, notes, index === 0);
    console.log(`${deliveryId} ${created ? "prepared" : "preserved"}`);
  }
  if (restoreMissingMedia) await restoreReferencedMedia();

  console.log("Synthetic demo credentials for newly seeded or unchanged accounts:");
  console.log(`  Staff  ${field.email}`);
  console.log(`  Admin  ${fixtureAccounts[0].email}`);
  console.log(`  Password for both  ${password}`);
  console.log("New deliveries use today's date in the seed host's timezone. Existing delivery dates stay as recorded.");
}

main().catch((error) => {
  console.error(error instanceof Error ? error.message : "Could not seed the local demo.");
  process.exitCode = 1;
});
