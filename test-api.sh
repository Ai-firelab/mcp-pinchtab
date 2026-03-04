#!/bin/bash
set -e

# ============================================================
# Pinchtab HTTP API Test Suite
# Server: http://localhost:9867
# ============================================================

BASE_URL="http://localhost:9867"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

PASS_COUNT=0
FAIL_COUNT=0
ERRORS=()

# ── helpers ────────────────────────────────────────────────

pass() {
  echo -e "  ${GREEN}PASS${RESET}  $1"
  PASS_COUNT=$((PASS_COUNT + 1))
}

fail() {
  echo -e "  ${RED}FAIL${RESET}  $1"
  ERRORS+=("$1")
  FAIL_COUNT=$((FAIL_COUNT + 1))
}

section() {
  echo ""
  echo -e "${CYAN}${BOLD}── $1 ──${RESET}"
}

# Check that a JSON response contains a given key at top level.
# Usage: has_key <json_string> <key> <test_label>
has_key() {
  local json="$1"
  local key="$2"
  local label="$3"
  if echo "$json" | python3 -c "import sys,json; d=json.load(sys.stdin); sys.exit(0 if '$key' in d else 1)" 2>/dev/null; then
    pass "$label"
  else
    fail "$label (missing key: $key)"
  fi
}

# Check that a JSON response contains an array key at top level.
# Usage: has_array <json_string> <key> <test_label>
has_array() {
  local json="$1"
  local key="$2"
  local label="$3"
  if echo "$json" | python3 -c "import sys,json; d=json.load(sys.stdin); assert isinstance(d.get('$key'), list)" 2>/dev/null; then
    pass "$label"
  else
    fail "$label (key '$key' is not an array or missing)"
  fi
}

# Make a request and store status + body in globals.
# Usage: request <METHOD> <path> [curl_extra_args...]
LAST_STATUS=""
LAST_BODY=""

request() {
  local method="$1"
  local path="$2"
  shift 2

  local tmp_body
  tmp_body=$(mktemp)

  LAST_STATUS=$(curl -s -o "$tmp_body" -w "%{http_code}" \
    -X "$method" \
    "${BASE_URL}${path}" \
    "$@") || true

  LAST_BODY=$(cat "$tmp_body")
  rm -f "$tmp_body"
}

# Assert the last request returned the expected HTTP status.
assert_status() {
  local expected="$1"
  local label="$2"
  if [ "$LAST_STATUS" = "$expected" ]; then
    pass "$label (HTTP $LAST_STATUS)"
  else
    fail "$label (expected HTTP $expected, got HTTP $LAST_STATUS)"
  fi
}

# ── pre-flight ──────────────────────────────────────────────

echo ""
echo -e "${BOLD}Pinchtab HTTP API – Test Suite${RESET}"
echo -e "Base URL: ${CYAN}${BASE_URL}${RESET}"
echo ""

echo -e "${YELLOW}Checking server availability...${RESET}"
if ! curl -sf "${BASE_URL}/health" > /dev/null 2>&1; then
  echo -e "${RED}ERROR: Pinchtab server is not reachable at ${BASE_URL}${RESET}"
  echo "Make sure the server is running and try again."
  exit 1
fi
echo -e "${GREEN}Server is up.${RESET}"

# ── 1. GET /health ──────────────────────────────────────────

section "GET /health"

request GET /health

assert_status 200 "GET /health returns 200"
has_key "$LAST_BODY" "status" "GET /health body has 'status' field"

# Verify status value is "ok"
STATUS_VAL=$(echo "$LAST_BODY" | python3 -c "import sys,json; print(json.load(sys.stdin).get('status',''))" 2>/dev/null || echo "")
if [ "$STATUS_VAL" = "ok" ]; then
  pass "GET /health status value is 'ok'"
else
  fail "GET /health status value is '$STATUS_VAL' (expected 'ok')"
fi

# ── 2. POST /navigate ───────────────────────────────────────

section "POST /navigate"

request POST /navigate \
  -H "Content-Type: application/json" \
  -d '{"url":"https://example.com"}'

assert_status 200 "POST /navigate returns 200"
has_key "$LAST_BODY" "url"   "POST /navigate body has 'url' field"
has_key "$LAST_BODY" "title" "POST /navigate body has 'title' field"

# Verify the navigated URL contains example.com
NAV_URL=$(echo "$LAST_BODY" | python3 -c "import sys,json; print(json.load(sys.stdin).get('url',''))" 2>/dev/null || echo "")
if echo "$NAV_URL" | grep -qi "example.com"; then
  pass "POST /navigate url contains 'example.com'"
else
  fail "POST /navigate url '$NAV_URL' does not contain 'example.com'"
fi

# ── 3. GET /snapshot (default) ──────────────────────────────

section "GET /snapshot"

request GET /snapshot

assert_status 200 "GET /snapshot returns 200"
has_key "$LAST_BODY" "nodes" "GET /snapshot body has 'nodes' field"

# ── 4. GET /snapshot?interactive=true ───────────────────────

section "GET /snapshot?interactive=true"

request GET "/snapshot?interactive=true"

assert_status 200 "GET /snapshot?interactive=true returns 200"
has_key "$LAST_BODY" "nodes" "GET /snapshot?interactive=true body has 'nodes' field"

# ── 5. GET /snapshot?compact=true ───────────────────────────

section "GET /snapshot?compact=true"

request GET "/snapshot?compact=true"

assert_status 200 "GET /snapshot?compact=true returns 200"
has_key "$LAST_BODY" "nodes" "GET /snapshot?compact=true body has 'nodes' field"

# ── 6. GET /snapshot?interactive=true&compact=true ──────────

section "GET /snapshot?interactive=true&compact=true"

request GET "/snapshot?interactive=true&compact=true"

assert_status 200 "GET /snapshot?interactive=true&compact=true returns 200"
has_key "$LAST_BODY" "nodes" "GET /snapshot combined params body has 'nodes' field"

# ── 7. GET /text ─────────────────────────────────────────────

section "GET /text"

request GET /text

assert_status 200 "GET /text returns 200"
has_key "$LAST_BODY" "text"  "GET /text body has 'text' field"
has_key "$LAST_BODY" "title" "GET /text body has 'title' field"
has_key "$LAST_BODY" "url"   "GET /text body has 'url' field"

TEXT_VAL=$(echo "$LAST_BODY" | python3 -c "import sys,json; print(json.load(sys.stdin).get('text',''))" 2>/dev/null || echo "")
if [ -n "$TEXT_VAL" ]; then
  pass "GET /text 'text' field is non-empty"
else
  fail "GET /text 'text' field is empty"
fi

# ── 8. GET /screenshot ──────────────────────────────────────

section "GET /screenshot"

TMP_PNG=$(mktemp /tmp/pinchtab-screenshot-XXXXXX.png)

SCREENSHOT_STATUS=$(curl -s -o "$TMP_PNG" -w "%{http_code}" \
  -X GET \
  "${BASE_URL}/screenshot") || true

if [ "$SCREENSHOT_STATUS" = "200" ]; then
  pass "GET /screenshot returns 200"
else
  fail "GET /screenshot (expected HTTP 200, got HTTP $SCREENSHOT_STATUS)"
fi

# Verify PNG magic bytes (89 50 4E 47)
if [ -f "$TMP_PNG" ] && [ -s "$TMP_PNG" ]; then
  PNG_MAGIC=$(xxd -p -l 4 "$TMP_PNG" 2>/dev/null || od -A n -t x1 -N 4 "$TMP_PNG" 2>/dev/null | tr -d ' \n')
  if echo "$PNG_MAGIC" | grep -qi "89504e47"; then
    pass "GET /screenshot response is a valid PNG file"
  else
    fail "GET /screenshot response does not have PNG magic bytes (got: $PNG_MAGIC)"
  fi
else
  fail "GET /screenshot response body is empty"
fi

rm -f "$TMP_PNG"

# ── 9. POST /action (click) ──────────────────────────────────

section "POST /action – kind: click"

# First grab a ref from the snapshot to click
SNAP_BODY=""
request GET "/snapshot?interactive=true"
SNAP_BODY="$LAST_BODY"

FIRST_REF=$(echo "$SNAP_BODY" | python3 -c "
import sys, json
d = json.load(sys.stdin)
nodes = d.get('nodes', [])
for n in nodes:
    ref = n.get('ref') or n.get('id') or ''
    if ref:
        print(ref)
        break
" 2>/dev/null || echo "")

if [ -n "$FIRST_REF" ]; then
  request POST /action \
    -H "Content-Type: application/json" \
    -d "{\"kind\":\"click\",\"ref\":\"${FIRST_REF}\"}"
  # A click on a text node may return 200 or a structured response; we accept 200.
  assert_status 200 "POST /action click ref='${FIRST_REF}' returns 200"
else
  fail "POST /action click – could not extract a ref from /snapshot (skipped)"
fi

# ── 10. POST /action (eval) ──────────────────────────────────

section "POST /action – kind: eval"

# Navigate back to example.com in case click navigated away
request POST /navigate \
  -H "Content-Type: application/json" \
  -d '{"url":"https://example.com"}' > /dev/null 2>&1 || true

request POST /action \
  -H "Content-Type: application/json" \
  -d '{"kind":"eval","script":"document.title"}'

assert_status 200 "POST /action eval returns 200"
has_key "$LAST_BODY" "result" "POST /action eval body has 'result' field"

# ── 11. POST /action (scroll) ────────────────────────────────

section "POST /action – kind: scroll"

request POST /action \
  -H "Content-Type: application/json" \
  -d '{"kind":"scroll","x":0,"y":200}'

assert_status 200 "POST /action scroll returns 200"

# ── 12. POST /action (press) ─────────────────────────────────

section "POST /action – kind: press"

request POST /action \
  -H "Content-Type: application/json" \
  -d '{"kind":"press","key":"Escape"}'

assert_status 200 "POST /action press returns 200"

# ── 13. GET /tabs ─────────────────────────────────────────────

section "GET /tabs"

request GET /tabs

assert_status 200 "GET /tabs returns 200"
has_key "$LAST_BODY" "tabs" "GET /tabs body has 'tabs' field"
has_array "$LAST_BODY" "tabs" "GET /tabs 'tabs' field is an array"

TABS_COUNT=$(echo "$LAST_BODY" | python3 -c "import sys,json; print(len(json.load(sys.stdin).get('tabs',[])))" 2>/dev/null || echo "0")
if [ "$TABS_COUNT" -ge 1 ]; then
  pass "GET /tabs has at least 1 tab (count: $TABS_COUNT)"
else
  fail "GET /tabs returned 0 tabs"
fi

# ── 14. POST /tab (new) ───────────────────────────────────────

section "POST /tab – action: new"

request POST /tab \
  -H "Content-Type: application/json" \
  -d '{"action":"new","url":"https://example.com"}'

assert_status 200 "POST /tab new returns 200"

# Capture the new tab ID for the close test
NEW_TAB_ID=$(echo "$LAST_BODY" | python3 -c "
import sys, json
d = json.load(sys.stdin)
# Accept 'tabId', 'id', or nested tab object
tid = d.get('tabId') or d.get('id') or (d.get('tab') or {}).get('id', '')
print(tid)
" 2>/dev/null || echo "")

if [ -n "$NEW_TAB_ID" ]; then
  pass "POST /tab new returned a tab ID: $NEW_TAB_ID"
else
  fail "POST /tab new – could not extract a tab ID from response"
fi

# ── 15. POST /tab (close) ────────────────────────────────────

section "POST /tab – action: close"

if [ -n "$NEW_TAB_ID" ]; then
  request POST /tab \
    -H "Content-Type: application/json" \
    -d "{\"action\":\"close\",\"tabId\":\"${NEW_TAB_ID}\"}"

  assert_status 200 "POST /tab close tabId='${NEW_TAB_ID}' returns 200"
else
  fail "POST /tab close – skipped (no tab ID from previous step)"
fi

# ── 16. GET /cookies ──────────────────────────────────────────

section "GET /cookies"

request GET /cookies

assert_status 200 "GET /cookies returns 200"
has_key "$LAST_BODY" "cookies" "GET /cookies body has 'cookies' field"
has_key "$LAST_BODY" "count"   "GET /cookies body has 'count' field"
has_key "$LAST_BODY" "url"     "GET /cookies body has 'url' field"
has_array "$LAST_BODY" "cookies" "GET /cookies 'cookies' field is an array"

# ── summary ───────────────────────────────────────────────────

TOTAL=$((PASS_COUNT + FAIL_COUNT))

echo ""
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo -e "${BOLD}  Test Summary${RESET}"
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo -e "  Total:  ${BOLD}${TOTAL}${RESET}"
echo -e "  ${GREEN}Passed: ${PASS_COUNT}${RESET}"
echo -e "  ${RED}Failed: ${FAIL_COUNT}${RESET}"

if [ ${#ERRORS[@]} -gt 0 ]; then
  echo ""
  echo -e "${RED}${BOLD}Failed tests:${RESET}"
  for err in "${ERRORS[@]}"; do
    echo -e "  ${RED}•${RESET} $err"
  done
fi

echo ""

if [ "$FAIL_COUNT" -eq 0 ]; then
  echo -e "${GREEN}${BOLD}All tests passed.${RESET}"
  exit 0
else
  echo -e "${RED}${BOLD}${FAIL_COUNT} test(s) failed.${RESET}"
  exit 1
fi
