#!/usr/bin/env bats
#
# End-to-end test: an ONBOARDED deployment must boot OpenClaw to a genuinely
# working state — not merely bind :3000. Render marks the service Live as soon
# as /health answers, which the Express setup server (or even the failure
# server) satisfies; a deploy can look "Live" while the gateway is dead. This
# suite seeds a realistic onboarded /data, boots the real image Render-style,
# and asserts the gateway itself comes up: "[gateway] ready" in the logs, the
# usage-tracker plugin initialized, and no invalid-config failures.
#
# Slow (builds an image, boots a container). Run via `npm run test:e2e`.
# Skips cleanly when docker is unavailable.

IMAGE="openclaw-render-test:latest"
CONTAINER="openclaw-render-gateway-e2e"
HOST_PORT=13001
GATEWAY_READY_MARKER="[gateway] ready"

setup_file() {
  REPO="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  export REPO IMAGE CONTAINER HOST_PORT GATEWAY_READY_MARKER

  command -v docker >/dev/null || skip "docker not installed"
  docker info >/dev/null 2>&1 || skip "docker daemon not running"

  docker build -t "$IMAGE" "$REPO" >&2
  docker rm -f "$CONTAINER" >/dev/null 2>&1 || true

  # Seed /data as an onboarded deployment: the marker makes alphaclaw run its
  # onboarded boot sequence (which starts the gateway), and gateway.mode=local
  # is what `openclaw onboard --mode local` writes — without it the gateway
  # refuses to start.
  SEED="$(mktemp -d)"
  export SEED
  mkdir -p "$SEED/.openclaw"
  printf '{"onboarded":true}\n' >"$SEED/onboarded.json"
  cat >"$SEED/.openclaw/openclaw.json" <<'JSON'
{
  "gateway": { "mode": "local" }
}
JSON

  docker run -d --name "$CONTAINER" \
    -v "$SEED:/data" \
    -p "${HOST_PORT}:3000" \
    -e PORT=3000 \
    -e SETUP_PASSWORD="gateway-e2e-test" \
    -e OPENCLAW_GATEWAY_TOKEN="gateway-e2e-test-token" \
    -e WEBHOOK_TOKEN="gateway-e2e-test" \
    "$IMAGE" >&2

  # Express /health comes up early; the gateway takes longer. Wait for the
  # ready line rather than sleeping a fixed amount.
  for _ in $(seq 1 60); do
    if docker logs "$CONTAINER" 2>&1 | grep -qF "$GATEWAY_READY_MARKER"; then
      return 0
    fi
    sleep 2
  done
  echo "gateway never became ready; logs follow:" >&2
  docker logs "$CONTAINER" >&2 || true
  return 1
}

teardown_file() {
  docker rm -f "$CONTAINER" >/dev/null 2>&1 || true
  [ -n "$SEED" ] && rm -rf "$SEED" || true
}

@test "container stays Live: /health returns 200" {
  run curl -fsS "http://127.0.0.1:${HOST_PORT}/health"
  [ "$status" -eq 0 ]
}

@test "gateway logs '[gateway] ready' — OpenClaw started properly" {
  run docker logs "$CONTAINER"
  grep -qF "$GATEWAY_READY_MARKER" <<<"$output"
}

@test "usage-tracker plugin loaded in the gateway" {
  # Loading proves alphaclaw's managed plugin config points at a real path:
  # the gateway only initializes the plugin after resolving plugins.load.paths.
  run docker logs "$CONTAINER"
  grep -qE "\[usage-tracker\] initialized|plugin: usage-tracker" <<<"$output"
}

@test "logs contain no invalid-config or gateway-startup failures" {
  run docker logs "$CONTAINER"
  ! grep -qF "OpenClaw config is invalid" <<<"$output"
  ! grep -qiF "plugin path not found" <<<"$output"
  ! grep -qF "Gateway failed to start" <<<"$output"
}

@test "openclaw config validate accepts the boot-reconciled config" {
  run docker exec "$CONTAINER" sh -c "openclaw config validate 2>&1 || true"
  echo "validate: $output" >&2
  ! grep -qiF "plugin path not found" <<<"$output"
  ! grep -qF "config is invalid" <<<"$output"
}
