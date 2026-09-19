// Load test for a Galedra node (Stage 26).
//
// The mix is what a public node actually sees: mostly people reading a claim
// someone linked them to, a trickle of assistants recording an investigation,
// and a connector working open tasks. Reads dominate because sharing a link is
// the point of the thing; writes are rare but serialise on the append lock, so
// a small number of them is what decides the ceiling.
//
// Run it with script/loadtest.sh, which needs no local k6. Point it at a
// staging node, never at one holding a record people rely on: the write
// scenario appends real contributions.
import http from "k6/http";
import { check, sleep } from "k6";
import { Trend } from "k6/metrics";

const BASE = __ENV.BASE_URL;
const TOKEN = __ENV.ASSISTANT_TOKEN || "";
const claimPage = new Trend("claim_page_ms", true);
const weaknesses = new Trend("weaknesses_ms", true);
const write = new Trend("write_ms", true);

export const options = {
  scenarios: {
    // Someone opened a link. This is the shape of almost all real traffic.
    readers: {
      executor: "ramping-vus",
      exec: "read",
      startVUs: 1,
      stages: [
        { duration: "1m", target: Number(__ENV.READERS || 20) },
        { duration: "8m", target: Number(__ENV.READERS || 20) },
        { duration: "1m", target: 0 },
      ],
    },
    // The page that scans the whole graph, asked for rarely but by anyone.
    scanners: {
      executor: "constant-arrival-rate",
      exec: "scan",
      rate: Number(__ENV.SCANS_PER_MIN || 4),
      timeUnit: "1m",
      duration: "10m",
      preAllocatedVUs: 4,
    },
    // Writes, only when a token is supplied.
    writers: {
      executor: "constant-arrival-rate",
      exec: "record",
      rate: Number(__ENV.WRITES_PER_MIN || 6),
      timeUnit: "1m",
      duration: "10m",
      preAllocatedVUs: 4,
    },
  },
  thresholds: {
    // The stage's acceptance, stated where it fails the run rather than in a
    // document nobody reruns.
    "claim_page_ms": ["p(95)<200"],
    "weaknesses_ms": ["p(95)<500"],
    "http_req_failed": ["rate<0.01"],
  },
};

// One claim id per virtual user, picked once, so the test measures the page
// rather than the search that found it.
function someClaimId() {
  const res = http.get(`${BASE}/api/v1/claims?limit=50`);
  const claims = res.json("claims") || [];
  if (claims.length === 0) return null;
  return claims[Math.floor(Math.random() * claims.length)].id;
}

export function setup() {
  const id = someClaimId();
  if (!id) throw new Error("no claims on this node; seed a corpus first (bench:seed)");
  return { claimId: id };
}

export function read(data) {
  const res = http.get(`${BASE}/claims/${data.claimId}`, { tags: { name: "claim page" } });
  claimPage.add(res.timings.duration);
  check(res, { "claim page is 200": (r) => r.status === 200 });
  sleep(Math.random() * 3 + 1);
}

export function scan() {
  const res = http.get(`${BASE}/api/v1/weaknesses?limit=25`, { tags: { name: "weaknesses" } });
  weaknesses.add(res.timings.duration);
  check(res, { "weaknesses is 200": (r) => r.status === 200 });
}

export function record() {
  if (!TOKEN) return;
  const body = JSON.stringify({
    action_type: "CREATE_CLAIM",
    payload: {
      canonical_text: `Load test claim ${__VU}-${__ITER}-${Date.now()}.`,
      claim_type: "OBSERVATIONAL",
      affirms_not_private_individual: true,
    },
  });
  const res = http.post(`${BASE}/api/v1/custodied/contributions`, body, {
    headers: { "Content-Type": "application/json", Authorization: `Bearer ${TOKEN}` },
    tags: { name: "custodied write" },
  });
  write.add(res.timings.duration);
  check(res, { "write is 201 or rate limited": (r) => r.status === 201 || r.status === 429 });
}
