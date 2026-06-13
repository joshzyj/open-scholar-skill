#!/usr/bin/env bash
# Headless driver for a scholar-simulate run.
#
# Wraps `simulate_engine.py run --resume` so a large/long simulation survives session close:
# background it with nohup, and it will keep polling a managed batch (or chunking async calls)
# and checkpointing responses until the run completes — auto-resuming across transient failures.
#
#   nohup bash run-simulate.sh <run-manifest.json> > run.log 2>&1 &
#
# Idempotent: every restart calls the engine with --resume, which skips already-checkpointed
# responses. Safe to re-run after a crash, a rate-limit pause, or a machine reboot.

set -uo pipefail   # -u: error on unset vars; -o pipefail: catch failures in pipes. NOT -e: we
                   # handle non-zero exits explicitly so one transient API hiccup never aborts the loop.

MANIFEST="${1:-}"                                  # path to the run manifest (required positional arg)
if [ -z "$MANIFEST" ] || [ ! -f "$MANIFEST" ]; then  # fail loudly on a missing/empty manifest
  echo "ERROR: usage: run-simulate.sh <run-manifest.json> (file not found: '${MANIFEST}')" >&2
  exit 2
fi

# Locate this script's directory so we can find the engine regardless of the caller's cwd.
ASSETS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"  # absolute path to assets/
ENGINE="${ASSETS_DIR}/simulate_engine.py"          # the Python engine entrypoint
if [ ! -f "$ENGINE" ]; then                        # the engine must sit beside this wrapper
  echo "ERROR: engine not found at ${ENGINE}" >&2
  exit 2
fi

MAX_RETRIES="${SCHOLAR_SIM_MAX_RETRIES:-5}"        # how many times to auto-resume after a non-zero exit
BACKOFF="${SCHOLAR_SIM_BACKOFF:-30}"               # seconds to wait between retries (grows each attempt)

echo "[$(date +%H:%M:%S)] run-simulate: manifest=${MANIFEST} engine=${ENGINE}"

attempt=1                                          # retry counter
while [ "$attempt" -le "$MAX_RETRIES" ]; do        # bounded auto-resume loop
  echo "[$(date +%H:%M:%S)] attempt ${attempt}/${MAX_RETRIES} — running engine (--resume)…"
  python3 "$ENGINE" run --manifest "$MANIFEST" --resume   # resume skips completed requests
  rc=$?                                             # capture the engine exit code
  if [ "$rc" -eq 0 ]; then                          # 0 = run complete (all responses checkpointed)
    echo "[$(date +%H:%M:%S)] run-simulate: COMPLETE."
    exit 0                                          # success — stop the wrapper
  fi
  # Non-zero exit: could be a transient rate limit, a dropped batch poll, or a network blip.
  wait_s=$(( BACKOFF * attempt ))                   # linear backoff: longer wait each retry
  echo "[$(date +%H:%M:%S)] engine exited rc=${rc}; retrying in ${wait_s}s…" >&2
  sleep "$wait_s"                                   # back off before resuming
  attempt=$(( attempt + 1 ))                        # next attempt
done

echo "[$(date +%H:%M:%S)] run-simulate: gave up after ${MAX_RETRIES} attempts. Inspect the run log and re-run with --resume." >&2
exit 1                                              # exhausted retries — surface failure to the operator
