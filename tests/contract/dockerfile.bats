#!/usr/bin/env bats
#
# Contract tests for the Dockerfile + render.yaml. Static assertions that the
# image-layer invariants documented in CLAUDE.md / AGENTS.md stay in place.

setup() {
  REPO="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
}

# --- PATH fix (primary + belt-and-suspenders shims) ---------------------------

@test "Dockerfile: sets PATH so /app/node_modules/.bin wins" {
  grep -Eq 'ENV PATH="/app/node_modules/\.bin:\$PATH"' "$REPO/Dockerfile"
}

@test "Dockerfile: installs openclaw + alphaclaw shims into /usr/bin" {
  grep -q '/usr/bin/openclaw' "$REPO/Dockerfile"
  grep -q '/usr/bin/alphaclaw' "$REPO/Dockerfile"
}

# --- TMPDIR onto the persistent disk ------------------------------------------

@test "Dockerfile: sets TMPDIR/TEMP/TMP env to /data/tmp" {
  grep -q 'ENV TMPDIR=/data/tmp' "$REPO/Dockerfile"
  grep -q 'ENV TEMP=/data/tmp'   "$REPO/Dockerfile"
  grep -q 'ENV TMP=/data/tmp'    "$REPO/Dockerfile"
}

@test "Dockerfile: creates /data/tmp with the sticky bit" {
  grep -Eq 'mkdir -p /data/tmp && chmod 1777 /data/tmp' "$REPO/Dockerfile"
}

@test "Dockerfile: never redirects bare /tmp (mentions only in comments)" {
  # Only /data/tmp is added; bare /tmp must never be a build instruction target.
  while IFS= read -r line; do
    [[ "$line" =~ ^[0-9]+:[[:space:]]*# ]] || { echo "non-comment /tmp use: $line"; false; }
  done < <(grep -nw '/tmp' "$REPO/Dockerfile")
}

# --- Init + entrypoint --------------------------------------------------------

@test "Dockerfile: uses tini as PID 1" {
  grep -Eq 'ENTRYPOINT \["/usr/bin/tini", "--"\]' "$REPO/Dockerfile"
}

@test "Dockerfile: CMD boots via start.sh" {
  grep -Eq 'CMD \["/start.sh"\]' "$REPO/Dockerfile"
}

@test "Dockerfile: exposes port 3000" {
  grep -q 'EXPOSE 3000' "$REPO/Dockerfile"
}

@test "Dockerfile: points ALPHACLAW_ROOT_DIR at the persistent disk" {
  grep -q 'ENV ALPHACLAW_ROOT_DIR=/data' "$REPO/Dockerfile"
}

# --- Render blueprint ---------------------------------------------------------

@test "render.yaml: health check is /health" {
  grep -q 'healthCheckPath: /health' "$REPO/render.yaml"
}

@test "render.yaml: mounts a persistent disk at /data" {
  grep -q 'mountPath: /data' "$REPO/render.yaml"
}
