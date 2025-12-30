#!/bin/bash
# Engram ingestion hook - forwards Claude Code events to ingestion service
# Requires OAuth authentication. This script is called by Claude Code hooks
# and should NEVER block.

set -e

# Debug logging (remove after testing)
DEBUG_LOG="/tmp/engram-hook-debug.log"

# Read JSON from stdin
INPUT=$(cat)

# Extract event metadata (handle jq failures gracefully)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null || echo "")
EVENT_NAME=$(echo "$INPUT" | jq -r '.hook_event_name // empty' 2>/dev/null || echo "")
TIMESTAMP=$(date +%s%3N)

# Generate a proper UUID v4 for event_id
if command -v uuidgen &>/dev/null; then
	EVENT_ID=$(uuidgen | tr '[:upper:]' '[:lower:]')
else
	# Fallback: generate UUID v4 from random bytes
	EVENT_ID=$(od -x /dev/urandom | head -1 | awk '{OFS="-"; print $2$3,$4,$5,$6,$7$8$9}' | sed 's/./4/13;s/./a/17')
fi

# Log event received
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Hook triggered: $EVENT_NAME (session: $SESSION_ID)" >> "$DEBUG_LOG"

# Get ingestion URL from environment or use cloud default
# Observatory exposes the ingest endpoint at /api/ingest
INGESTION_URL="${ENGRAM_INGESTION_URL:-https://observatory.engram.rawcontext.com}"

# Read auth token from MCP server's token cache
# The MCP server stores OAuth tokens at ~/.engram/auth.json after device flow auth
TOKEN_FILE="${HOME}/.engram/auth.json"
AUTH_TOKEN=""

if [ -f "$TOKEN_FILE" ]; then
	AUTH_TOKEN=$(jq -r '.access_token // empty' "$TOKEN_FILE" 2>/dev/null || echo "")
fi

# If no token found, exit silently (auth required)
if [ -z "$AUTH_TOKEN" ]; then
	echo "[$(date '+%Y-%m-%d %H:%M:%S')] No auth token found, skipping" >> "$DEBUG_LOG"
	exit 0
fi

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Auth token found, preparing payload" >> "$DEBUG_LOG"

# Construct RawStreamEvent envelope
# This matches the RawStreamEventSchema from @engram/events
PAYLOAD=$(jq -n \
	--arg event_id "$EVENT_ID" \
	--arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
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
# - Exit 0 always, even on curl failure
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Sending to: ${INGESTION_URL}/api/ingest" >> "$DEBUG_LOG"
(
	HTTP_CODE=$(curl -sSL -X POST "${INGESTION_URL}/api/ingest" \
		-H "Content-Type: application/json" \
		-H "Authorization: Bearer $AUTH_TOKEN" \
		-d "$PAYLOAD" \
		--max-time 5 \
		-w "%{http_code}" \
		-o /dev/null 2>&1) || HTTP_CODE="failed"
	echo "[$(date '+%Y-%m-%d %H:%M:%S')] Response: $HTTP_CODE for $EVENT_NAME" >> "$DEBUG_LOG"
) &

# CRITICAL: Always exit successfully to not block Claude Code
exit 0
