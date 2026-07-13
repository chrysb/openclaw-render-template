# Tests

This template is mostly infrastructure (a Dockerfile, a boot script, a fallback
HTTP server, and Render config), so the tests are split by how much they cost to
run. All test files live here and are excluded from the image via `.dockerignore`.

| Layer        | What it checks                                                                 | Needs            | Command               |
|--------------|--------------------------------------------------------------------------------|------------------|-----------------------|
| **unit**     | `failure-server.js` routing + the "no secret leaks" property                   | node             | `npm run test:unit`   |
| **contract** | Static invariants in `start.sh` / `debug-start.sh` / `Dockerfile` / `render.yaml` / `package.json` | bash, `shellcheck`, `bats` | `npm run test:contract` |
| **e2e**      | Builds the image and boots it Render-style — both fresh (empty `/data`) and onboarded (gateway must reach ready) | docker, `bats`, curl | `npm run test:e2e`    |

```sh
npm test          # unit + contract (fast, no docker)
npm run test:e2e  # full image build + run (slow; ~minutes)
npm run test:all  # everything
```

## Why these layers

- **Unit** exercises the real `failure-server.js` artifact in a subprocess (no
  mocks). The security test plants sentinel secrets in the env and asserts they
  never appear in any HTTP response — the failure page is publicly reachable on
  the service URL, so it must never render logs or env values.
- **Contract** locks in the load-bearing config that, if removed, restart-loops
  the container: the `PATH` prepend (alphaclaw spawns `openclaw` by bare name),
  the `TMPDIR=/data/tmp` routing, the sticky-bit `mkdir` on boot, the tini/CMD
  wiring, the "never touch bare `/tmp`" rule, and the exact-version alphaclaw
  pin (a drifting spec never changes `package.json`, so the Docker npm-install
  layer cache silently keeps shipping a stale alphaclaw).
- **e2e** has two suites:
  - `docker.bats` mounts a **tmpfs over `/data`** so the dir starts empty at
    runtime, reproducing how Render's disk mount shadows the Dockerfile's
    build-time `mkdir`. If `/data/tmp` exists with its sticky bit afterwards,
    `start.sh` recreated it on boot — load-bearing, since the disk mount hides
    anything created at build time.
  - `gateway-ready.bats` seeds a realistic **onboarded** `/data`
    (`onboarded.json` + `gateway.mode=local`, as `openclaw onboard` writes) and
    asserts OpenClaw reaches a **working state**: Render marks a service Live
    as soon as `/health` answers — which even the failure server satisfies — so
    "Live" alone proves nothing about the gateway. This suite waits for
    **`[gateway] ready`** in the logs, checks the usage-tracker plugin actually
    initialized, and fails on any invalid-config or gateway-startup error.

## Local prerequisites

```sh
brew install bats-core shellcheck   # macOS
```

Node's built-in test runner (`node --test`) needs no extra packages.
