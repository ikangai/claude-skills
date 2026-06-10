#!/usr/bin/env bash
#
# Test harness for ../scripts/detect-synth.sh.
#
# Runs detection against the mock LM Studio server (tests/mock-lm-server.py)
# with different served-model lists and asserts on the decision line and
# the persisted .synth-config.
#
# Run from anywhere:
#   bash /path/to/diary/tests/test-detect-synth.sh
#
# Exit code: 0 if all cases pass, 1 otherwise.

set -u

# Isolate from the machine's diary configuration — settings.json env blocks
# leak into test runs and would change detection outcomes.
unset DIARY_SYNTH DIARY_LM_URL DIARY_LM_MODEL DIARY_SUITABLE_MODELS \
  DIARY_CLAUDE_BIN DIARY_CLAUDE_MODEL DIARY_LM_TIMEOUT 2>/dev/null || true

HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/../scripts/detect-synth.sh"
MOCK="$HERE/mock-lm-server.py"
SANDBOX="$(mktemp -d -t diary-detect-test.XXXXXX)"
SERVER_PID=""
cleanup() {
  [[ -n "$SERVER_PID" ]] && kill "$SERVER_PID" 2>/dev/null
  rm -rf "$SANDBOX"
}
trap cleanup EXIT

PASS=0
FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1 — $2"; FAIL=$((FAIL+1)); }

CONFIG="$SANDBOX/.dev-diary/.synth-config"

# launch <mock_models> — (re)start the mock server with a served-model list.
launch() {
  [[ -n "$SERVER_PID" ]] && { kill "$SERVER_PID" 2>/dev/null; wait "$SERVER_PID" 2>/dev/null; SERVER_PID=""; }
  : > "$SANDBOX/port.txt"
  MOCK_MODELS="$1" python3 "$MOCK" > "$SANDBOX/port.txt" &
  SERVER_PID=$!
  for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
    PORT="$(head -1 "$SANDBOX/port.txt" 2>/dev/null)"
    [[ -n "$PORT" ]] && break
    sleep 0.1
  done
  [[ -n "$PORT" ]] || { echo "could not start mock server" >&2; exit 1; }
  BASE_URL="http://127.0.0.1:$PORT/v1"
}

# --- 1: suitable model served (not first in the list) → local ---------------
rm -f "$CONFIG"
launch "text-embedding-nomic-embed-text-v1.5,mock-chat-model,google/gemma-4-26b-a4b"
out="$("$SCRIPT" --config "$CONFIG" --url "$BASE_URL")"
if [[ "$out" == "backend=local model=google/gemma-4-26b-a4b" ]] \
  && [[ "$(jq -r '.backend' "$CONFIG")" == "local" ]] \
  && [[ "$(jq -r '.model' "$CONFIG")" == "google/gemma-4-26b-a4b" ]]; then
  ok "suitable model served → local"
else
  bad "suitable model served → local" "out=$out config=$(cat "$CONFIG" 2>/dev/null)"
fi

# --- 2: only unsuitable models served → sonnet -------------------------------
rm -f "$CONFIG"
launch "text-embedding-nomic-embed-text-v1.5,mock-chat-model"
out="$("$SCRIPT" --config "$CONFIG" --url "$BASE_URL")"
if [[ "$out" == "backend=sonnet" ]] \
  && [[ "$(jq -r '.backend' "$CONFIG")" == "sonnet" ]] \
  && [[ "$(jq -r '.model // "absent"' "$CONFIG")" == "absent" ]]; then
  ok "only unsuitable models → sonnet"
else
  bad "only unsuitable models → sonnet" "out=$out config=$(cat "$CONFIG" 2>/dev/null)"
fi

# --- 3: server unreachable → sonnet ------------------------------------------
rm -f "$CONFIG"
out="$("$SCRIPT" --config "$CONFIG" --url "http://127.0.0.1:1/v1")"
if [[ "$out" == "backend=sonnet" ]] \
  && [[ "$(jq -r '.backend' "$CONFIG")" == "sonnet" ]]; then
  ok "server unreachable → sonnet"
else
  bad "server unreachable → sonnet" "out=$out config=$(cat "$CONFIG" 2>/dev/null)"
fi

# --- 4: existing config wins without --force (no re-probe) -------------------
rm -f "$CONFIG"
launch "google/gemma-4-26b-a4b"
"$SCRIPT" --config "$CONFIG" --url "$BASE_URL" >/dev/null
out="$("$SCRIPT" --config "$CONFIG" --url "http://127.0.0.1:1/v1")"
if printf '%s' "$out" | grep -q "backend=local model=google/gemma-4-26b-a4b" \
  && [[ "$(jq -r '.backend' "$CONFIG")" == "local" ]]; then
  ok "existing config honored without --force"
else
  bad "existing config honored without --force" "out=$out config=$(cat "$CONFIG" 2>/dev/null)"
fi

# --- 5: --force re-probes and can flip the decision ---------------------------
out="$("$SCRIPT" --config "$CONFIG" --url "http://127.0.0.1:1/v1" --force)"
if [[ "$out" == "backend=sonnet" ]] \
  && [[ "$(jq -r '.backend' "$CONFIG")" == "sonnet" ]]; then
  ok "--force re-probes (local → sonnet)"
else
  bad "--force re-probes (local → sonnet)" "out=$out config=$(cat "$CONFIG" 2>/dev/null)"
fi

# --- 6: DIARY_LM_MODEL pin is tried first, even if not in the suitable list --
rm -f "$CONFIG"
launch "text-embedding-nomic-embed-text-v1.5,mock-chat-model"
out="$(DIARY_LM_MODEL=mock-chat-model "$SCRIPT" --config "$CONFIG" --url "$BASE_URL")"
if [[ "$out" == "backend=local model=mock-chat-model" ]]; then
  ok "DIARY_LM_MODEL pin accepted when served"
else
  bad "DIARY_LM_MODEL pin accepted when served" "out=$out"
fi

# --- 7: DIARY_SUITABLE_MODELS overrides the built-in list --------------------
rm -f "$CONFIG"
launch "weird-local-model"
out="$(DIARY_SUITABLE_MODELS=weird-local-model "$SCRIPT" --config "$CONFIG" --url "$BASE_URL")"
if [[ "$out" == "backend=local model=weird-local-model" ]]; then
  ok "DIARY_SUITABLE_MODELS override"
else
  bad "DIARY_SUITABLE_MODELS override" "out=$out"
fi

# --- 8: corrupt config is re-detected even without --force -------------------
printf 'not json\n' > "$CONFIG"
launch "google/gemma-4-26b-a4b"
out="$("$SCRIPT" --config "$CONFIG" --url "$BASE_URL")"
if [[ "$out" == "backend=local model=google/gemma-4-26b-a4b" ]] \
  && jq -e . "$CONFIG" >/dev/null 2>&1; then
  ok "corrupt config re-detected"
else
  bad "corrupt config re-detected" "out=$out config=$(cat "$CONFIG" 2>/dev/null)"
fi

echo
echo "----"
echo "Results: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
