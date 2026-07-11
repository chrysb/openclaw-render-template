#!/usr/bin/env bats
#
# Contract tests for package.json's alphaclaw dependency spec.

setup() {
  REPO="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  ALPHACLAW_SPEC="$(node -e 'console.log(require(process.argv[1]).dependencies["@chrysb/alphaclaw"])' "$REPO/package.json")"
}

@test "package.json: alphaclaw is pinned to an exact version, not a range or tag" {
  # The Dockerfile copies only package.json and runs npm install in that layer.
  # With a spec that can drift (^range, ~range, latest, a git branch ref), the
  # layer's cache key never changes, so Docker — locally and on Render — keeps
  # reusing the npm-install layer from whenever the spec was first resolved,
  # and alphaclaw updates silently never ship. An exact version makes every
  # update an explicit package.json edit that busts the cache.
  [[ "$ALPHACLAW_SPEC" =~ ^[0-9]+\.[0-9]+\.[0-9]+([-+].+)?$ ]]
}
