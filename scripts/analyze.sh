#!/bin/bash
set +e

ADDED=$(git diff HEAD~1 --numstat 2>/dev/null | awk '{sum += $1} END {print sum+0}')
REMOVED=$(git diff HEAD~1 --numstat 2>/dev/null | awk '{sum += $2} END {print sum+0}')
FILES=$(git diff HEAD~1 --name-only 2>/dev/null | wc -l | tr -d ' ')
K8S=$(git diff HEAD~1 --name-only 2>/dev/null | grep -c '\.ya\?ml$' || echo 0)
DEPS=$(git diff HEAD~1 --name-only 2>/dev/null | grep -cE 'package\.json|requirements\.txt|go\.mod|pom\.xml|Gemfile|Cargo\.toml' || echo 0)

[ -z "$ADDED" ] && ADDED=0
[ -z "$REMOVED" ] && REMOVED=0
[ -z "$FILES" ] && FILES=0
[ -z "$K8S" ] && K8S=0
[ -z "$DEPS" ] && DEPS=0

ADDED=$(echo "${ADDED:-0}" | tr -d ' \n')
REMOVED=$(echo "${REMOVED:-0}" | tr -d ' \n')
FILES=$(echo "${FILES:-0}" | tr -d ' \n')
K8S=$(echo "${K8S:-0}" | tr -d ' \n')
DEPS=$(echo "${DEPS:-0}" | tr -d ' \n')
INC7=$(echo "${INCIDENTS_7D:-0}" | tr -d ' \n')
INC30=$(echo "${INCIDENTS_30D:-0}" | tr -d ' \n')

echo "DEBUG: $(echo "{\"repo\":\"${GITHUB_REPO}\",\"branch\":\"${GITHUB_BRANCH}\",\"commit_sha\":\"${GITHUB_SHA}\",\"diff_lines_added\":${ADDED},\"diff_lines_removed\":${REMOVED},\"diff_files_changed\":${FILES},\"k8s_manifests_changed\":${K8S},\"dependency_updates\":${DEPS},\"major_version_bumps\":0,\"incidents_last_7d\":${INC7},\"incidents_last_30d\":${INC30}}")"

RESPONSE=$(curl -s -w "\n%{http_code}" -X POST https://api.bluecodeit.com/analyze \
  -H "Content-Type: application/json" \
  -H "X-API-Key: ${GUARD_API_KEY}" \
  --max-time 60 \
  -d "{\"repo\":\"${GITHUB_REPO}\",\"branch\":\"${GITHUB_BRANCH}\",\"commit_sha\":\"${GITHUB_SHA}\",\"diff_lines_added\":${ADDED},\"diff_lines_removed\":${REMOVED},\"diff_files_changed\":${FILES},\"k8s_manifests_changed\":${K8S},\"dependency_updates\":${DEPS},\"major_version_bumps\":0,\"incidents_last_7d\":${INC7},\"incidents_last_30d\":${INC30}}")

HTTP_CODE=$(echo "$RESPONSE" | tail -1)
BODY=$(echo "$RESPONSE" | sed '$d')

if [ "$HTTP_CODE" = "429" ]; then
  echo "⚠️  Deployment Guard: Analyse-Limit erreicht (Free Plan: 50/Monat)"
  exit 0
fi

if [ "$HTTP_CODE" != "200" ]; then
  echo "⚠️  Deployment Guard: API nicht erreichbar (HTTP $HTTP_CODE) — Deployment wird fortgesetzt."
  exit 0
fi

SCORE=$(echo "$BODY" | grep -o '"score":[0-9]*' | cut -d: -f2)
STATUS=$(echo "$BODY" | grep -o '"status":"[^"]*"' | cut -d'"' -f4)
VERDICT=$(echo "$BODY" | grep -o '"verdict":"[^"]*"' | cut -d'"' -f4)
EXPLANATION=$(echo "$BODY" | grep -o '"explanation":"[^"]*"' | cut -d'"' -f4)

echo "score=${SCORE}" >> $GITHUB_OUTPUT
echo "status=${STATUS}" >> $GITHUB_OUTPUT
echo "verdict=${VERDICT}" >> $GITHUB_OUTPUT
echo "explanation=${EXPLANATION}" >> $GITHUB_OUTPUT

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🛡️  Deployment Guard — Risk Analysis"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Repo:    ${GITHUB_REPO}"
echo "  Branch:  ${GITHUB_BRANCH}"
echo "  Commit:  ${GITHUB_SHA:0:7}"
echo "  ─────────────────────────────────────"
echo "  Score:   ${SCORE} / 100"
echo "  Verdict: ${VERDICT}"
echo "  Status:  ${STATUS}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [ -n "$EXPLANATION" ]; then
  echo ""
  echo "📋 KI-Analyse:"
  echo "   ${EXPLANATION}"
  echo ""
fi

if [ "$STATUS" = "BLOCKED" ] && [ "$FAIL_ON_BLOCKED" = "true" ]; then
  echo "❌ Deployment blockiert — Risk Score zu hoch (${SCORE}/100)."
  exit 1
fi

if [ "$STATUS" = "WARN" ]; then
  echo "⚠️  Warnung — erhöhtes Risiko (${SCORE}/100). Deployment wird fortgesetzt."
fi

if [ "$STATUS" = "PASS" ]; then
  echo "✅ Deployment freigegeben (${SCORE}/100)."
fi