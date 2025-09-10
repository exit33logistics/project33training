#!/usr/bin/env bash
# claude_batch_runner.sh
# ---------------------------------------------
# Batch-run a directory of text prompts against a Claude-style API endpoint.
#
# Usage:
#   Make executable: chmod +x claude_batch_runner.sh
#   Export your API variables, e.g.:
#     export CLAUDE_API_KEY="sk-XXXX"
#     export CLAUDE_API_URL="https://api.anthropic.com/v1/complete"   # or your vendor's endpoint
#     export MODEL="claude-2"                                        # set to your model name
#   Then run:
#     ./claude_batch_runner.sh -p ./prompts -o ./outputs
#
# Notes:
# - This script is intentionally generic. Some Claude-style APIs accept "prompt", "input", or "messages".
#   Use PROMPT_KEY to match your provider (default: input).
# - The script requires Python 3 for safe JSON escaping of prompt contents.
# - Retries and exponential backoff are built-in for transient errors.
# - For very large prompt files, use --chunk-lines to split by lines per request.
#
# Environment variables (defaults can be overridden via CLI flags):
#   CLAUDE_API_KEY  - required (your API key)
#   CLAUDE_API_URL  - required (your Claude provider API URL)
#   MODEL           - optional (model name string)
#   PROMPT_KEY      - which JSON key to place the prompt under: "input" | "prompt" | "messages"
#
# Example CLI:
#   ./claude_batch_runner.sh -p ./prompts_pack -o ./claude_outputs --prompt-key prompt --model "claude-2.1"
#
set -euo pipefail

# Defaults
PROMPTS_DIR="./prompts"
OUTPUT_DIR="./outputs"
CLAUDE_API_URL="${CLAUDE_API_URL:-}"
CLAUDE_API_KEY="${CLAUDE_API_KEY:-}"
MODEL="${MODEL:-claude-2}"
PROMPT_KEY="${PROMPT_KEY:-input}"   # change to "prompt" if your API expects that
TIMEOUT="${TIMEOUT:-60}"            # curl timeout (seconds)
RETRIES=3
BACKOFF_BASE=2
CHUNK_LINES=0   # if >0, will split each prompt file into chunks of N lines
VERBOSE=1

usage(){
  cat <<USAGE
Usage: $0 [options]

Options:
  -p dir      Directory with .txt prompt files (default: ${PROMPTS_DIR})
  -o dir      Output directory for responses (default: ${OUTPUT_DIR})
  -k key      API key (or set CLAUDE_API_KEY env var)
  -u url      API URL (or set CLAUDE_API_URL env var)
  -m model    Model name (default: ${MODEL})
  -q keyname  Prompt JSON key: input | prompt | messages (default: ${PROMPT_KEY})
  -t seconds  Curl timeout (default: ${TIMEOUT})
  -r n        Retries per request (default: ${RETRIES})
  -c lines    Chunk large prompt files into N-line pieces per request (default: ${CHUNK_LINES})
  -v          Verbose logging
  -h          Show this help
USAGE
  exit 1
}

while getopts "p:o:k:u:m:q:t:r:c:vh" opt; do
  case "$opt" in
    p) PROMPTS_DIR="$OPTARG" ;;
    o) OUTPUT_DIR="$OPTARG" ;;
    k) CLAUDE_API_KEY="$OPTARG" ;;
    u) CLAUDE_API_URL="$OPTARG" ;;
    m) MODEL="$OPTARG" ;;
    q) PROMPT_KEY="$OPTARG" ;;
    t) TIMEOUT="$OPTARG" ;;
    r) RETRIES="$OPTARG" ;;
    c) CHUNK_LINES="$OPTARG" ;;
    v) VERBOSE=1 ;;
    h) usage ;;
    *) usage ;;
  esac
done

if [ -z "${CLAUDE_API_KEY:-}" ] || [ -z "${CLAUDE_API_URL:-}" ]; then
  echo "ERROR: CLAUDE_API_KEY and CLAUDE_API_URL must be set (or passed with -k and -u)."
  usage
fi

mkdir -p "$OUTPUT_DIR"

log(){
  if [ "$VERBOSE" -eq 1 ]; then
    echo "$(date --iso-8601=seconds) - $*"
  fi
}

# safe_json(): produce a JSON-escaped string of file content via python3
safe_json(){
  local file="$1"
  python3 - <<PY
import sys, json
data = open(sys.argv[1], 'r', encoding='utf-8').read()
print(json.dumps(data))
PY "$file"
}

# send_request(): POST to CLAUDE_API_URL with payload built from model + prompt key
send_request(){
  local json_prompt="$1"
  local out_file="$2"
  local attempt=0
  local resp
  while [ "$attempt" -le "$RETRIES" ]; do
    attempt=$((attempt+1))
    log "Request attempt $attempt -> $out_file"
    # Construct payload (we rely on the surrounding caller to provide properly json-escaped prompt text)
    payload=$(python3 - <<PY
import json,sys,os
model = os.environ.get('MODEL', '${MODEL}')
key = os.environ.get('PROMPT_KEY', '${PROMPT_KEY}')
prompt_value = json.loads(sys.argv[1])
# Build payload depending on whether the API expects a 'model' field only
p = {'model': model}
if key == 'messages':
    # if user expects chat-style messages, convert raw text into a single user message
    p['messages'] = [{'role':'user','content': prompt_value}]
else:
    p[key] = prompt_value
print(json.dumps(p))
PY "$json_prompt")

    # Send the request with curl
    resp=$(curl -sS --max-time "$TIMEOUT" -X POST "$CLAUDE_API_URL" \
      -H "Authorization: Bearer $CLAUDE_API_KEY" \
      -H "Content-Type: application/json" \
      -d "$payload" || true)

    # Basic check: if response contains something, write and break.
    if [ -n "$resp" ]; then
      printf "%s\n" "$resp" > "$out_file"
      return 0
    fi

    # else backoff
    sleep $(( BACKOFF_BASE ** attempt ))
    log "No response or error, retrying..."
  done

  echo "ERROR: Failed to get a successful response after $RETRIES attempts." > "$out_file"
  return 1
}

process_file(){
  local file="$1"
  local base="$(basename "$file")"
  local name="${base%.*}"

  if [ "$CHUNK_LINES" -gt 0 ]; then
    # split by lines into temp files; iterate over pieces
    local tmpdir
    tmpdir=$(mktemp -d)
    split -l "$CHUNK_LINES" --numeric-suffixes=1 "$file" "$tmpdir/part_"
    local idx=1
    for part in "$tmpdir"/part_*; do
      part_json=$(safe_json "$part")
      out="$OUTPUT_DIR/${name}_part${idx}.response.json"
      send_request "$part_json" "$out" || log "Request for $part failed"
      idx=$((idx+1))
    done
    rm -rf "$tmpdir"
  else
    # single-shot
    prompt_json=$(safe_json "$file")
    out="$OUTPUT_DIR/${name}.response.json"
    send_request "$prompt_json" "$out" || log "Request for $file failed"
  fi
}

# iterate files
shopt -s nullglob
files=("$PROMPTS_DIR"/*.txt)
if [ ${#files[@]} -eq 0 ]; then
  echo "No .txt files found in $PROMPTS_DIR"
  exit 1
fi
log "Found ${#files[@]} prompt file(s) in $PROMPTS_DIR. Output -> $OUTPUT_DIR"

for f in "${files[@]}"; do
  log "Processing $f ..."
  process_file "$f"
done

log "All done. Responses written to $OUTPUT_DIR"
