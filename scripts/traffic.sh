#!/usr/bin/env bash
# Sends a steady mix of accepted and rejected requests through the gateway, so the
# Konnect dashboards have something to show in a demo. Not a test: use verify.sh for that.
#
# Each round sends:
#   /a2a  with a valid token (expect 200), without a token and with a bad token (expect 401)
#   /mcp  a tools/call with a valid token (expect 200), and one without a token (expect 401)
#   /v1   a chat call to MODEL with a valid token (expect 200) and one without (expect 401)
#
# Needs these exported: AWS_DOMAIN, ISSUER_URL, CLIENT_ID, CLIENT_SECRET
# Optional:
#   KONG_HOST  the gateway (default ai-dp.$AWS_DOMAIN)
#   KONG_IP    pins KONG_HOST to one address, if your local DNS can't resolve it yet
#   MODEL      the model to call (default nova-micro; each call costs a fraction of a cent).
#              Set MODEL= to leave the model out.
#   ROUNDS     how many rounds (default 20)
#   PAUSE      seconds between rounds (default 2)
#
# Usage:  ROUNDS=20 ./scripts/traffic.sh

for tool in curl jq; do
  command -v "$tool" >/dev/null 2>&1 || { echo "Missing tool: $tool"; exit 2; }
done
for v in AWS_DOMAIN ISSUER_URL CLIENT_ID CLIENT_SECRET; do
  if [ -z "${!v:-}" ]; then echo "Missing $v (export it first)"; exit 2; fi
done

HOST="${KONG_HOST:-ai-dp.${AWS_DOMAIN}}"
MODEL="${MODEL-nova-micro}"
ROUNDS="${ROUNDS:-20}"
PAUSE="${PAUSE:-2}"

RESOLVE=()
if ! curl -s -o /dev/null --max-time 8 "https://${HOST}/"; then
  if [ -z "${KONG_IP:-}" ] && command -v dig >/dev/null 2>&1; then
    KONG_IP=$(dig +short "$HOST" @8.8.8.8 | head -1)
  fi
  if [ -n "${KONG_IP:-}" ]; then
    RESOLVE=(--resolve "${HOST}:443:${KONG_IP}")
    echo "Note: ${HOST} did not resolve locally; pinning it to ${KONG_IP}"
  fi
fi

code() { curl -s -o /dev/null -w '%{http_code}' "${RESOLVE[@]}" "$@"; }

get_token() {
  curl -s -X POST "${ISSUER_URL}/oauth/token" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "grant_type=client_credentials" -d "client_id=${CLIENT_ID}" \
    -d "client_secret=${CLIENT_SECRET}" -d "scope=scope1" | jq -r '.access_token // empty'
}

A2A='{"jsonrpc":"2.0","id":"1","method":"message/send","params":{"message":{"kind":"message","messageId":"msg-001","role":"user","parts":[{"kind":"text","text":"hi"}]}}}'
MCP_HDRS=(-H "Content-Type: application/json" -H "Accept: application/json, text/event-stream")
MCP_INIT='{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"traffic","version":"1.0"}}}'
MCP_CALL='{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"check_inventory","arguments":{"query_sku":"KONG-123"}}}'
PROMPTS=("Give me one fun fact about APIs." "What is an AI gateway, in one sentence?" "Name one benefit of OAuth2 client credentials." "Explain rate limiting in ten words.")

total=0; ok=0; rejected=0; other=0
tally() {
  total=$((total + 1))
  case "$1" in
    2??) ok=$((ok + 1)) ;;
    401|403) rejected=$((rejected + 1)) ;;
    *) other=$((other + 1)) ;;
  esac
}

echo "Sending ${ROUNDS} rounds to https://${HOST}${MODEL:+ (with model ${MODEL})}"
for i in $(seq 1 "$ROUNDS"); do
  TOKEN=$(get_token)
  if [ -z "$TOKEN" ]; then echo "Could not get a token from ${ISSUER_URL}"; exit 1; fi
  AUTH=(-H "Authorization: Bearer ${TOKEN}")

  a_ok=$(code -X POST "https://${HOST}/a2a" "${AUTH[@]}" --json "$A2A");                       tally "$a_ok"
  a_none=$(code -X POST "https://${HOST}/a2a" --json "$A2A");                                   tally "$a_none"
  a_bad=$(code -X POST "https://${HOST}/a2a" -H "Authorization: Bearer not-a-real-token" --json "$A2A"); tally "$a_bad"

  hdrs=$(mktemp)
  curl -s -o /dev/null -D "$hdrs" "${RESOLVE[@]}" -X POST "https://${HOST}/mcp" "${MCP_HDRS[@]}" "${AUTH[@]}" --data "$MCP_INIT"
  SID=$(grep -i '^mcp-session-id:' "$hdrs" | awk '{print $2}' | tr -d '\r'); rm -f "$hdrs"
  m_ok=$(code -X POST "https://${HOST}/mcp" "${MCP_HDRS[@]}" "${AUTH[@]}" -H "Mcp-Session-Id: ${SID}" --data "$MCP_CALL"); tally "$m_ok"
  m_none=$(code -X POST "https://${HOST}/mcp" "${MCP_HDRS[@]}" --data "$MCP_INIT");             tally "$m_none"

  line="round ${i}/${ROUNDS}  a2a: ${a_ok} ${a_none} ${a_bad}  mcp: ${m_ok} ${m_none}"
  if [ -n "$MODEL" ]; then
    prompt=${PROMPTS[$(( (i - 1) % ${#PROMPTS[@]} ))]}
    body=$(jq -nc --arg m "$MODEL" --arg p "$prompt" '{model:$m, messages:[{role:"user", content:$p}]}')
    v_ok=$(code "https://${HOST}/v1/chat/completions" "${AUTH[@]}" --json "$body");             tally "$v_ok"
    v_none=$(code "https://${HOST}/v1/chat/completions" --json "$body");                        tally "$v_none"
    line="${line}  model: ${v_ok} ${v_none}"
  fi
  echo "$line"
  [ "$i" -lt "$ROUNDS" ] && sleep "$PAUSE"
done

echo
echo "${total} requests: ${ok} accepted (2xx), ${rejected} rejected (401/403), ${other} other"
echo "Konnect analytics usually show them within a few minutes."
