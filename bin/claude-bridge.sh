#!/usr/bin/env bash
# JSON-RPC ↔ claude bridge for Symphony's Codex App Server protocol.
#
# Symphony spawns this via `bash -lc "<codex.command>"` with cwd = per-card
# workspace (a git checkout of the repo). It then writes newline-delimited
# JSON-RPC requests to our stdin and reads NDJSON responses + notifications
# from our stdout. We translate the minimal handshake to/from `claude -p`.
#
# Protocol surface (see elixir/lib/symphony_elixir/codex/app_server.ex):
#   <- initialize           id=1       -> {"id":1,"result":{...}}
#   <- initialized          (notification, no response)
#   <- thread/start         id=2       -> {"id":2,"result":{"thread":{"id":...}}}
#   <- turn/start           id=3       -> {"id":3,"result":{"turn":{"id":...}}}
#                                       -> {"method":"turn/completed",...}  (after claude returns)
#                                       -> {"method":"turn/failed",...}     (on non-zero exit)

set -uo pipefail

emit() {
  printf '%s\n' "$1"
}

log() {
  printf 'claude-bridge: %s\n' "$1" >&2
}

log "started cwd=$(pwd)"

while IFS= read -r line; do
  [ -z "$line" ] && continue

  method=$(jq -r '.method // ""' <<< "$line")
  id=$(jq -r '.id // ""' <<< "$line")

  case "$method" in
    initialize)
      emit "$(jq -nc --arg id "$id" \
        '{id: ($id | tonumber), result: {serverInfo: {name: "claude-bridge", version: "0.1.0"}, capabilities: {experimentalApi: true}}}')"
      log "initialize ack id=$id"
      ;;

    initialized)
      log "initialized notification (no response)"
      ;;

    thread/start)
      tid="thread-$$-$(date +%s%N)"
      emit "$(jq -nc --arg id "$id" --arg tid "$tid" \
        '{id: ($id | tonumber), result: {thread: {id: $tid}}}')"
      log "thread/start ack id=$id thread_id=$tid"
      ;;

    turn/start)
      turn_id="turn-$$-$(date +%s%N)"
      thread_id=$(jq -r '.params.threadId // ""' <<< "$line")
      prompt=$(jq -r '.params.input[0].text // ""' <<< "$line")
      title=$(jq -r '.params.title // ""' <<< "$line")

      emit "$(jq -nc --arg id "$id" --arg tid "$turn_id" \
        '{id: ($id | tonumber), result: {turn: {id: $tid}}}')"
      log "turn/start ack id=$id turn_id=$turn_id thread=$thread_id title=$title"

      log "invoking claude -p"
      if claude_output=$(claude -p --dangerously-skip-permissions <<< "$prompt" 2>&1); then
        log "claude exited 0 output_bytes=${#claude_output}"
        emit "$(jq -nc --arg tid "$turn_id" --arg out "$claude_output" \
          '{method: "turn/completed", params: {turnId: $tid, output: $out, status: "success"}}')"
      else
        rc=$?
        log "claude exited $rc output_bytes=${#claude_output}"
        emit "$(jq -nc --arg tid "$turn_id" --arg err "$claude_output" --argjson rc "$rc" \
          '{method: "turn/failed", params: {turnId: $tid, error: $err, exitCode: $rc}}')"
      fi
      ;;

    "")
      log "empty/non-method line ignored: $(echo "$line" | head -c 80)"
      ;;

    *)
      log "unhandled method=$method id=$id (silently ignored)"
      ;;
  esac
done

log "stdin closed, exiting"
