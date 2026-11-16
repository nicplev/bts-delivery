const assert = require("node:assert/strict");
const {test} = require("node:test");
const {schoolQueries} = require("../lib/calendar-feed");
const {changedSchoolIds} = require("../lib/delivery-trigger");
const {sessionId} = require("../lib/timer-auto-stop");

test("calendar query chunks keep each staff assignment and fail closed", () => {
  assert.equal(schoolQueries("admin", []), null);
  assert.equal(schoolQueries("manager", undefined), null);
  assert.deepEqual(schoolQueries("unknown", ["alpha"]), []);
  assert.deepEqual(schoolQueries("staff", undefined), []);
  assert.deepEqual(schoolQueries("staff", []), []);
  const ids = Array.from({length: 65}, (_, index) => `school-${index}`);
  const chunks = schoolQueries("staff", [...ids, ids[0], 24, "invalid/path"]);
  assert.deepEqual(chunks.map((chunk) => chunk.length), [30, 30, 5]);
  assert.deepEqual(chunks.flat(), ids);
});

test("calendar updates include both sides of reassignment and deletion", () => {
  assert.deepEqual(changedSchoolIds("alpha", "beta"), ["alpha", "beta"]);
  assert.deepEqual(changedSchoolIds("alpha", null), ["alpha"]);
  assert.deepEqual(changedSchoolIds("alpha", "alpha"), ["alpha"]);
});

test("timer session keys preserve new IDs and deterministically cover legacy starts", () => {
  assert.equal(sessionId({sessionId: "existing-session"}), "existing-session");
  assert.equal(sessionId({startedAt: {seconds: 1700000000, nanoseconds: 123000}}),
    "legacy-1700000000-123000");
});
