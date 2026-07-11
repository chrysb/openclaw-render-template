#!/usr/bin/env bats
#
# Contract tests for the shell scripts. These lock in the load-bearing
# invariants that CLAUDE.md / AGENTS.md call out under "don't remove" and
# "What NOT to do" — the things that, if dropped, restart-loop the container.
# They are static (no container needed) so they run fast in `npm test`.

setup() {
  REPO="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
}

@test "start.sh: valid bash syntax" {
  bash -n "$REPO/start.sh"
}

@test "debug-start.sh: valid bash syntax" {
  bash -n "$REPO/debug-start.sh"
}

@test "start.sh: passes shellcheck" {
  command -v shellcheck >/dev/null || skip "shellcheck not installed"
  shellcheck "$REPO/start.sh"
}

@test "debug-start.sh: passes shellcheck" {
  command -v shellcheck >/dev/null || skip "shellcheck not installed"
  shellcheck "$REPO/debug-start.sh"
}

# --- PATH fix (load-bearing: alphaclaw spawns openclaw by bare name) ----------

@test "start.sh: prepends /app/node_modules/.bin to PATH" {
  grep -Eq 'export PATH="/app/node_modules/\.bin:' "$REPO/start.sh"
}

# --- TMPDIR onto the persistent disk ------------------------------------------

@test "start.sh: exports the TMPDIR/TEMP/TMP trio to /data/tmp" {
  grep -q 'TMPDIR=/data/tmp' "$REPO/start.sh"
  grep -q 'TEMP=/data/tmp'   "$REPO/start.sh"
  grep -q 'TMP=/data/tmp'    "$REPO/start.sh"
}

@test "start.sh: creates /data/tmp with the sticky bit on boot" {
  # /data is a runtime-mounted disk, so the dir must be (re)created at boot.
  grep -Eq 'mkdir -p "\$TMPDIR"' "$REPO/start.sh"
  grep -q 'chmod 1777 "\$TMPDIR"' "$REPO/start.sh"
}

@test "start.sh: never operates on bare /tmp (mentions only in comments)" {
  # CLAUDE.md rule: leave /tmp alone — no symlink, bind-mount, or move. We allow
  # /tmp to appear in explanatory comments, but every such line must be a comment.
  while IFS= read -r line; do
    [[ "$line" =~ ^[0-9]+:[[:space:]]*# ]] || { echo "non-comment /tmp use: $line"; false; }
  done < <(grep -nw '/tmp' "$REPO/start.sh")
}

# --- Resilience: fall back to the failure server, don't crash-loop ------------

@test "start.sh: runs 'alphaclaw start' as the primary process" {
  grep -q 'alphaclaw start' "$REPO/start.sh"
}

@test "start.sh: execs the failure server when alphaclaw exits" {
  grep -q 'exec node /failure-server.js' "$REPO/start.sh"
}
