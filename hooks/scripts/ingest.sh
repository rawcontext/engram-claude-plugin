#!/bin/bash
# Engram ingestion hook - forwards Claude Code events to ingestion service
# Requires OAuth authentication. This script is called by Claude Code hooks
# and should NEVER block.

set -e

# Read JSON from stdin
INPUT=$(cat)

# Extract event metadata (handle jq failures gracefully)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null || echo "")
EVENT_NAME=$(echo "$INPUT" | jq -r '.hook_event_name // empty' 2>/dev/null || echo "")
TIMESTAMP=$(date +%s%3N)

# Generate event ID from session + timestamp + random suffix
if command -v openssl &>/dev/null; then
	RANDOM_SUFFIX=$(openssl rand -hex 4)
else
	RANDOM_SUFFIX=$(head -c 8 /dev/urandom | xxd -p | head -c 8)
fi
EVENT_ID="${SESSION_ID:-unknown}-${TIMESTAMP}-${RANDOM_SUFFIX}"

# Get ingestion URL from environment or use cloud default
INGESTION_URL="${ENGRAM_INGESTION_URL:-https://api.engram.rawcontext.com}"

# Read auth token from MCP server's token cache
# The MCP server stores OAuth tokens at ~/.engram/auth.json after device flow auth
TOKEN_FILE="${HOME}/.engram/auth.json"
AUTH_TOKEN=""

if [ -f "$TOKEN_FILE" ]; then
	AUTH_TOKEN=$(jq -r '.access_token // empty' "$TOKEN_FILE" 2>/dev/null || echo "")
fi

# If no token found, exit silently (auth required)
if [ -z "$AUTH_TOKEN" ]; then
	exit 0
fi

# Construct RawStreamEvent envelope
# This matches the RawStreamEventSchema from @engram/events
PAYLOAD=$(jq -n \
	--arg event_id "$EVENT_ID" \
	--arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ 2>/dev/null || date -u +%Y-%m-%dT%H:%M:%SZ)" \
	--arg session_id "$SESSION_ID" \
	--arg event_name "$EVENT_NAME" \
	--argjson input "$INPUT" \
	'{
    event_id: $event_id,
    ingest_timestamp: $timestamp,
    provider: "claude_code",
    payload: $input,
    headers: {
      "x-session-id": $session_id,
      "x-hook-event": $event_name,
      "x-source": "hook"
    }
  }' 2>/dev/null) || exit 0

# Send to ingestion service asynchronously with auth header
# - Run in background (&)
# - Set short timeout (5s)
# - Suppress all output
# - Exit 0 always, even on curl failure
(curl -sS -X POST "${INGESTION_URL}/v1/ingest" \
	-H "Content-Type: application/json" \
	-H "Authorization: Bearer $AUTH_TOKEN" \
	-d "$PAYLOAD" \
	--max-time 5 \
	>/dev/null 2>&1 || true) &

# CRITICAL: Always exit successfully to not block Claude Code
exit 0
