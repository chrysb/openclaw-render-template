#!/usr/bin/env bats
#
# End-to-end test: build the real image, run it the way Render does, and assert
# the container actually stays Live and satisfies every documented invariant.
#
# Key trick: we mount a tmpfs over /data so it starts EMPTY, exactly like
# Render's runtime disk mount — which shadows the Dockerfile's build-time
# `mkdir /data/tmp`. If /data/tmp still exists afterwards, start.sh recreated it
# on boot (the load-bearing behavior).
#
# Slow (builds an image, pulls alphaclaw). Not part of `npm test`; run via
# `npm run test:e2e`. Skips cleanly when docker is unavailable.

IMAGE="openclaw-render-test:latest"
CONTAINER="openclaw-render-e2e"
HOST_PORT=13000
SENTINEL="SENTINEL-SECRET-DO-NOT-LEAK-9f3a2b"

setup_file() {
  REPO="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  export REPO IMAGE CONTAINER HOST_PORT SENTINEL

  command -v docker >/dev/null || skip "docker not installed"
  docker info >/dev/null 2>&1 || skip "docker daemon not running"

  docker build -t "$IMAGE" "$REPO" >&2
  docker rm -f "$CONTAINER" >/dev/null 2>&1 || true

  # --tmpfs /data => empty /data at runtime, mimicking Render's disk mount.
  docker run -d --name "$CONTAINER" \
    --tmpfs /data \
    -p "${HOST_PORT}:3000" \
    -e PORT=3000 \
    -e SETUP_PASSWORD="$SENTINEL" \
    -e OPENCLAW_GATEWAY_TOKEN="$SENTINEL" \
    -e WEBHOOK_TOKEN="$SENTINEL" \
    "$IMAGE" >&2

  # Wait up to ~120s for /health to answer 200 (alphaclaw OR the failure server).
  for _ in $(seq 1 60); do
    if curl -fsS "http://127.0.0.1:${HOST_PORT}/health" >/dev/null 2>&1; then
      return 0
    fi
    sleep 2
  done

  echo "container never became healthy; logs follow:" >&2
  docker logs "$CONTAINER" >&2 || true
  return 1
}

teardown_file() {
  docker rm -f "$CONTAINER" >/dev/null 2>&1 || true
}

# Helper: run a command inside the running container. Non-login shell on
# purpose — a login shell re-sources /etc/profile and resets PATH, which would
# mask the image's ENV PATH (the very thing alphaclaw inherits and we test).
in_container() {
  docker exec "$CONTAINER" sh -c "$1"
}

@test "container stays Live: /health returns 200" {
  run curl -fsS "http://127.0.0.1:${HOST_PORT}/health"
  [ "$status" -eq 0 ]
}

@test "openclaw resolves on PATH and runs" {
  in_container 'command -v openclaw && openclaw --version'
}

@test "alphaclaw resolves on PATH" {
  in_container 'command -v alphaclaw'
}

@test "PATH includes /app/node_modules/.bin" {
  in_container 'echo "$PATH"' | grep -q '/app/node_modules/.bin'
}

@test "TMPDIR env points at /data/tmp" {
  run in_container 'printenv TMPDIR'
  [ "$status" -eq 0 ]
  [ "$output" = "/data/tmp" ]
}

@test "start.sh recreated /data/tmp (sticky bit) despite empty disk mount" {
  in_container 'test -d /data/tmp'
  in_container 'test -k /data/tmp'
}

@test "tini is PID 1" {
  in_container 'cat /proc/1/comm' | grep -q tini
}

@test "SECURITY: failure/landing page does not leak env secrets" {
  run curl -fsS "http://127.0.0.1:${HOST_PORT}/"
  [ "$status" -eq 0 ]
  ! grep -q "$SENTINEL" <<<"$output"
}
