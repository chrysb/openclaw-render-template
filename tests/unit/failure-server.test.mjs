// Unit tests for failure-server.js — the fallback HTTP server that keeps the
// Render container Live (port bound, /health 200) after `alphaclaw start` dies.
//
// Strategy: spawn the real artifact as a child process on a throwaway port with
// sentinel secrets in its env, then exercise it over HTTP. This tests the file
// exactly as it ships (no refactor, no mocks).

import { test, before, after } from "node:test";
import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { readFileSync } from "node:fs";
import path from "node:path";

const SERVER = path.resolve(import.meta.dirname, "../../failure-server.js");
const PORT = 38291;
const BASE = `http://127.0.0.1:${PORT}`;

// A value we plant in the env that MUST NEVER appear in any HTTP response.
// The failure page is publicly reachable on the service URL (see the header
// comment in failure-server.js + commit "Stop leaking /data/start.log").
const SENTINEL = "SENTINEL-SECRET-DO-NOT-LEAK-9f3a2b";

let child;

before(async () => {
  child = spawn(process.execPath, [SERVER], {
    env: {
      ...process.env,
      PORT: String(PORT),
      // Mimic the secret-bearing env the server runs under on Render.
      SETUP_PASSWORD: SENTINEL,
      OPENCLAW_GATEWAY_TOKEN: SENTINEL,
      WEBHOOK_TOKEN: SENTINEL,
    },
    stdio: ["ignore", "pipe", "pipe"],
  });

  // Resolve once the server reports it is listening.
  await new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error("server did not start in time")), 10000);
    child.stdout.on("data", (buf) => {
      if (buf.toString().includes("listening on port")) {
        clearTimeout(timer);
        resolve();
      }
    });
    child.on("exit", (code) => reject(new Error(`server exited early (code ${code})`)));
  });
});

after(() => {
  child?.kill("SIGKILL");
});

test("/health returns 200 ok as text/plain", async () => {
  const res = await fetch(`${BASE}/health`);
  assert.equal(res.status, 200);
  assert.match(res.headers.get("content-type") ?? "", /text\/plain/);
  assert.equal((await res.text()).trim(), "ok");
});

test("/healthz is also a 200 ok health alias", async () => {
  const res = await fetch(`${BASE}/healthz`);
  assert.equal(res.status, 200);
  assert.equal((await res.text()).trim(), "ok");
});

test("/ serves the human-readable failure page", async () => {
  const res = await fetch(`${BASE}/`);
  assert.equal(res.status, 200);
  assert.match(res.headers.get("content-type") ?? "", /text\/html/);
  const body = await res.text();
  assert.match(body, /AlphaClaw failed to start/);
});

test("unknown paths fall through to the failure page (catch-all)", async () => {
  const res = await fetch(`${BASE}/some/random/path`);
  assert.equal(res.status, 200);
  assert.match(await res.text(), /AlphaClaw failed to start/);
});

test("SECURITY: no response leaks env secrets", async () => {
  for (const route of ["/", "/health", "/healthz", "/anything"]) {
    const body = await (await fetch(`${BASE}${route}`)).text();
    assert.ok(
      !body.includes(SENTINEL),
      `secret from env leaked into the response body for ${route}`,
    );
  }
});

test("SECURITY: source does no filesystem IO", () => {
  // The durable invariant is that the server reads NOTHING from disk, so it
  // cannot accidentally render the boot log (which can contain env values).
  // Note: naming the path "/data/start.log" in the page as a `cat ...` hint for
  // the operator is fine — that's a static string, not file contents.
  const src = readFileSync(SERVER, "utf8");
  assert.ok(!/require\(["']fs["']\)|from\s+["']fs["']/.test(src), "failure-server.js must not import fs");
  assert.ok(!/readFile/.test(src), "failure-server.js must not read files");
});
