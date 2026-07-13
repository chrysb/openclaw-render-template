#!/bin/bash
# Boot script: runs alphaclaw, but if alphaclaw exits/crashes, falls back to
# a tiny HTTP failure-status server so the container stays Live and the
# Render Shell tab remains accessible for debugging.

LOGFILE=/data/start.log
mkdir -p /data

# Render's runtime container env can strip PATH down to a narrow set that
# excludes /usr/bin and /app/node_modules/.bin, which breaks alphaclaw's
# spawning of openclaw, curl, etc. Force a sensible PATH explicitly.
export PATH="/app/node_modules/.bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

# Route temp onto the persistent /data disk instead of ephemeral /tmp. The disk
# is mounted over /data at runtime, so the Dockerfile's build-time mkdir is
# hidden — (re)create /data/tmp here on every boot. Re-export the standard temp
# trio too (same belt-and-suspenders reasoning as PATH above: Render's runtime
# can munge the env even though the Dockerfile sets these via ENV).
export TMPDIR=/data/tmp TEMP=/data/tmp TMP=/data/tmp
mkdir -p "$TMPDIR" && chmod 1777 "$TMPDIR"

{
  echo "=== boot $(date -u +%FT%TZ) ==="
  echo "PATH=$PATH"
  echo "TMPDIR=$TMPDIR"
  echo "Starting alphaclaw..."
} | tee -a "$LOGFILE"

set -o pipefail
/app/node_modules/.bin/alphaclaw start 2>&1 | tee -a "$LOGFILE"
CODE=${PIPESTATUS[0]}

echo "=== alphaclaw exited with code $CODE at $(date -u +%FT%TZ) ===" | tee -a "$LOGFILE"
echo "=== falling back to failure-status server ===" | tee -a "$LOGFILE"

exec node /failure-server.js
