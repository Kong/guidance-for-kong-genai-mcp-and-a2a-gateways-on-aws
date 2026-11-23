#!/usr/bin/env bash
# Verifies the finished walkthrough end to end on the AI Gateway: the agent (/a2a),
# the MCP server (/mcp) and the Bedrock model (/v1), with and without a Kong Identity token.
#
# Needs these exported in your shell (the values from Steps 1 and 5):
#   AWS_DOMAIN, ISSUER_URL, CLIENT_ID, CLIENT_SECRET
# Optional:
#   KONG_HOST  the gateway to test (default ai-dp.$AWS_DOMAIN).
#   KONG_IP    pins KONG_HOST to one address, if your local DNS can't resolve it yet.
#   MODEL      the model name to test (default nova-micro). Set MODEL= to skip the model checks.
#   MCP_AUTH   set MCP_AUTH=0 if /mcp doesn't require a token (before Step 5).
#
# Usage:  ./scripts/verify.sh
# Exit code is 0 only if every check passes.

for tool in curl jq; do
  command -v "$tool" >/dev/null 2>&1 || { echo "Missing tool: $tool"; exit 2; }
done
for v in AWS_DOMAIN ISSUER_URL CLIENT_ID CLIENT_SECRET; do
  if [ -z "${!v:-}" ]; then echo "Missing $v (export it first)"; exit 2; fi
done

HOST="${KONG_HOST:-ai-dp.${AWS_DOMAIN}}"
MODEL="${MODEL-nova-micro}"
MCP_AUTH="${MCP_AUTH:-1}"
pass=0
fail=0

# If the name doesn't resolve from this machine, pin it to the address public DNS returns.
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

kc() { curl -s "${RESOLVE[@]}" "$@"; }

check() {
  local name=$1
  shift
  if "$@"; then
    echo "PASS  ${name}"
    pass=$((pass + 1))
  else
    echo "FAIL  ${name}"
    fail=$((fail + 1))
  fi
}

A2A_BODY='{"jsonrpc":"2.0","id":"1","method":"message/send","params":{"message":{"kind":"message","messageId":"msg-001","role":"user","parts":[{"kind":"text","text":"hi"}]}}}'
MCP_HDRS=(-H "Content-Type: application/json" -H "Accept: application/json, text/event-stream")
MCP_INIT='{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"verify","version":"1.0"}}}'

get_token() {
  curl -s -X POST "${ISSUER_URL}/oauth/token" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "grant_type=client_credentials" -d "client_id=${CLIENT_ID}" \
    -d "client_secret=${CLIENT_SECRET}" -d "scope=scope1" | jq -r '.access_token // empty'
}

# A 401 that Kong itself produced has no x-kong-upstream-latency header.
# A 401 that came back from AgentCore would have one.
rejected_by_kong() {
  local out=$1
  echo "$out" | head -1 | grep -q " 401" && ! echo "$out" | grep -qi '^x-kong-upstream-latency'
}

t_gateway_up() {
  local code
  code=$(kc -o /dev/null -w '%{http_code}' "https://${HOST}/")
  [ "$code" = "404" ]
}

t_a2a_no_token() {
  rejected_by_kong "$(kc -i -X POST "https://${HOST}/a2a" --json "$A2A_BODY")"
}

t_a2a_bad_token() {
  rejected_by_kong "$(kc -i -X POST "https://${HOST}/a2a" -H "Authorization: Bearer not-a-real-token" --json "$A2A_BODY")"
}

t_a2a_good_token() {
  kc -X POST "https://${HOST}/a2a" -H "Authorization: Bearer ${TOKEN}" --json "$A2A_BODY" | grep -q '"artifacts"'
}

t_mcp_initialize() {
  local hdrs body
  hdrs=$(mktemp)
  body=$(kc -D "$hdrs" -X POST "https://${HOST}/mcp" "${MCP_HDRS[@]}" -H "Authorization: Bearer ${TOKEN}" \
    --data "$MCP_INIT")
  SID=$(grep -i '^mcp-session-id:' "$hdrs" | awk '{print $2}' | tr -d '\r')
  rm -f "$hdrs"
  echo "$body" | grep -q "serverInfo"
}

t_mcp_list() {
  local out
  out=$(kc -X POST "https://${HOST}/mcp" "${MCP_HDRS[@]}" -H "Authorization: Bearer ${TOKEN}" -H "Mcp-Session-Id: ${SID}" \
    --data '{"jsonrpc":"2.0","id":2,"method":"tools/list"}')
  echo "$out" | grep -q "check-inventory" && echo "$out" | grep -q "list-orders"
}

t_mcp_call() {
  local out
  out=$(kc -X POST "https://${HOST}/mcp" "${MCP_HDRS[@]}" -H "Authorization: Bearer ${TOKEN}" -H "Mcp-Session-Id: ${SID}" \
    --data '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"check-inventory","arguments":{"query_sku":"KONG-123"}}}')
  echo "$out" | grep -q "KONG-123" && ! echo "$out" | grep -q '"isError":true'
}

t_mcp_no_token() {
  local code
  code=$(kc -o /dev/null -w '%{http_code}' -X POST "https://${HOST}/mcp" "${MCP_HDRS[@]}" --data "$MCP_INIT")
  [ "$code" = "401" ]
}

t_model_no_token() {
  local code
  code=$(kc -o /dev/null -w '%{http_code}' "https://${HOST}/v1/chat/completions" \
    --json "{\"model\":\"${MODEL}\",\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}]}")
  [ "$code" = "401" ]
}

t_model_good_token() {
  kc "https://${HOST}/v1/chat/completions" -H "Authorization: Bearer ${TOKEN}" \
    --json "{\"model\":\"${MODEL}\",\"messages\":[{\"role\":\"user\",\"content\":\"Say hi\"}]}" \
    | jq -e '.choices[0].message.content and .usage.total_tokens > 0' >/dev/null
}

echo "Checking https://${HOST}"
TOKEN=$(get_token)
if [ -z "$TOKEN" ]; then
  echo "FAIL  could not get a token from ${ISSUER_URL} (check CLIENT_ID and CLIENT_SECRET)"
  exit 1
fi

check "gateway answers (404 on /, no route there)" t_gateway_up
check "/a2a without a token is rejected by Kong" t_a2a_no_token
check "/a2a with a bad token is rejected by Kong" t_a2a_bad_token
check "/a2a with a valid token reaches the agent" t_a2a_good_token
if [ "$MCP_AUTH" != "0" ]; then
  check "/mcp without a token is rejected" t_mcp_no_token
fi
check "/mcp initialize returns server info" t_mcp_initialize
check "/mcp lists check-inventory and list-orders" t_mcp_list
check "/mcp tool call reaches the REST backend" t_mcp_call
if [ -n "$MODEL" ]; then
  check "/v1 model ${MODEL} without a token is rejected" t_model_no_token
  check "/v1 model ${MODEL} with a valid token answers" t_model_good_token
fi

echo
echo "${pass} passed, ${fail} failed"
[ "$fail" -eq 0 ]
