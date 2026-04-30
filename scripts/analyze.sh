#!/bin/bash
set -e

ADDED=$(git diff HEAD~1 HEAD --numstat 2>/dev/null | awk '{sum += $1} END {print sum+0}')
REMOVED=$(git diff HEAD~1 HEAD --numstat 2>/dev/null | awk '{sum += $2} END {print sum+0}')
FILES=$(git diff HEAD~1 --name-only 2>/dev/null | wc -l | tr -d ' ')
[ -z "$ADDED" ]   && ADDED=0
[ -z "$REMOVED" ] && REMOVED=0
[ -z "$FILES" ]   && FILES=0

CHANGED_YAMLS=$(git diff HEAD~1 --name-only 2>/dev/null | \
  grep -E '\.ya?ml$' | \
  grep -v '\.github/' | \
  grep -v 'action\.ya?ml' | \
  grep -v 'templates/' || true)

K8S=0
if [ -n "$CHANGED_YAMLS" ]; then
  K8S=$(echo "$CHANGED_YAMLS" | xargs grep -l 'kind:' 2>/dev/null | wc -l | tr -d ' ')
fi
[ -z "$K8S" ] && K8S=0

SINGLE_REPLICA="false"
MISSING_PDB="false"
HAS_DEPLOYMENT=0
HAS_PDB=0

for f in $CHANGED_YAMLS; do
  if [ -f "$f" ]; then
    if grep -q 'kind: Deployment' "$f" 2>/dev/null; then
      HAS_DEPLOYMENT=$((HAS_DEPLOYMENT + 1))
      REPLICAS=$(grep 'replicas:' "$f" 2>/dev/null | awk '{print $2}' | head -1)
      if [ "$REPLICAS" = "1" ]; then
        SINGLE_REPLICA="true"
      fi
    fi
    if grep -q 'kind: PodDisruptionBudget' "$f" 2>/dev/null; then
      HAS_PDB=$((HAS_PDB + 1))
    fi
  fi
done

if [ "$HAS_DEPLOYMENT" -gt 0 ] && [ "$HAS_PDB" -eq 0 ]; then
  MISSING_PDB="true"
fi

HELM_VALUES=0
if [ -n "$CHANGED_YAMLS" ]; then
  HELM_VALUES=$(echo "$CHANGED_YAMLS" | \
    xargs grep -l 'image:\|tag:\|replicaCount:\|resources:' 2>/dev/null | \
    wc -l | tr -d ' ')
fi
[ -z "$HELM_VALUES" ] && HELM_VALUES=0

HELM_CHART_CHANGED=$(git diff HEAD~1 --name-only 2>/dev/null | grep -E 'Chart\.ya?ml$' | wc -l | tr -d ' ')
[ -z "$HELM_CHART_CHANGED" ] && HELM_CHART_CHANGED=0
[ "$HELM_CHART_CHANGED" -gt 0 ] && HELM_CHART_BUMPED="true" || HELM_CHART_BUMPED="false"

DEP_FILES=$(git diff HEAD~1 --name-only 2>/dev/null | \
  grep -E 'package\.json|requirements\.txt|go\.mod|pom\.xml|Gemfile|Cargo\.toml|yarn\.lock|package-lock\.json' | \
  wc -l | tr -d ' ')
[ -z "$DEP_FILES" ] && DEP_FILES=0

MAJOR_BUMPS=0

if git diff HEAD~1 --name-only 2>/dev/null | grep -q 'package\.json'; then
  PKG_MAJOR=$(git diff HEAD~1 HEAD -- package.json 2>/dev/null | \
    grep '^[+-]' | grep -v '^---\|^+++' | \
    grep -oE '"[0-9]+\.' | grep -oE '[0-9]+' | \
    sort -n | uniq -d | wc -l | tr -d ' ')
  [ -z "$PKG_MAJOR" ] && PKG_MAJOR=0
  MAJOR_BUMPS=$((MAJOR_BUMPS + PKG_MAJOR))
fi

if git diff HEAD~1 --name-only 2>/dev/null | grep -q 'requirements\.txt'; then
  REQ_MAJOR=$(git diff HEAD~1 HEAD -- requirements.txt 2>/dev/null | \
    grep '^[+-][a-zA-Z]' | grep -oE '==[0-9]+' | grep -oE '[0-9]+' | \
    sort | uniq -d | wc -l | tr -d ' ')
  [ -z "$REQ_MAJOR" ] && REQ_MAJOR=0
  MAJOR_BUMPS=$((MAJOR_BUMPS + REQ_MAJOR))
fi

if git diff HEAD~1 --name-only 2>/dev/null | grep -q 'go\.mod'; then
  GO_MAJOR=$(git diff HEAD~1 HEAD -- go.mod 2>/dev/null | \
    grep '^[+-]' | grep -v '^---\|^+++' | \
    grep -oE '/v[0-9]+' | grep -oE '[0-9]+' | \
    sort -n | uniq -d | wc -l | tr -d ' ')
  [ -z "$GO_MAJOR" ] && GO_MAJOR=0
  MAJOR_BUMPS=$((MAJOR_BUMPS + GO_MAJOR))
fi

INC7=$(echo "${INCIDENTS_7D:-0}"  | tr -d ' \n')
INC30=$(echo "${INCIDENTS_30D:-0}" | tr -d ' \n')

echo "  [guard] diff_lines_added:     ${ADDED}"
echo "  [guard] diff_lines_removed:   ${REMOVED}"
echo "  [guard] diff_files_changed:   ${FILES}"
echo "  [guard] k8s_manifests:        ${K8S}"
echo "  [guard] single_replica:       ${SINGLE_REPLICA}"
echo "  [guard] missing_pdb:          ${MISSING_PDB}"
echo "  [guard] helm_values_changed:  ${HELM_VALUES}"
echo "  [guard] helm_chart_bumped:    ${HELM_CHART_BUMPED}"
echo "  [guard] dependency_updates:   ${DEP_FILES}"
echo "  [guard] major_version_bumps:  ${MAJOR_BUMPS}"
echo "  [guard] incidents_7d:         ${INC7}"
echo "  [guard] incidents_30d:        ${INC30}"

PAYLOAD=$(cat <<EOF
{
  "repo": "${GITHUB_REPO}",
  "branch": "${GITHUB_BRANCH}",
  "commit_sha": "${GITHUB_SHA}",
  "diff_lines_added": ${ADDED},
  "diff_lines_removed": ${REMOVED},
  "diff_files_changed": ${FILES},
  "k8s_manifests_changed": ${K8S},
  "has_single_replica": ${SINGLE_REPLICA},
  "has_missing_pdb": ${MISSING_PDB},
  "helm_values_changed": ${HELM_VALUES},
  "helm_chart_bumped": ${HELM_CHART_BUMPED},
  "dependency_updates": ${DEP_FILES},
  "major_version_bumps": ${MAJOR_BUMPS},
  "incidents_last_7d": ${INC7},
  "incidents_last_30d": ${INC30}
}
EOF
)

RESPONSE=$(curl -s -w "\n%{http_code}" -X POST https://api.bluecodeit.com/analyze \
  -H "Content-Type: application/json" \
  -H "X-API-Key: ${GUARD_API_KEY}" \
  --max-time 120 \
  -d "${PAYLOAD}")

HTTP_CODE=$(echo "$RESPONSE" | tail -1)
BODY=$(echo "$RESPONSE" | sed '$d')

if [ "$HTTP_CODE" = "429" ]; then
  echo "⚠️  Deployment Guard: Analyse-Limit erreicht — Deployment wird fortgesetzt."
  exit 0
fi

if [ "$HTTP_CODE" != "200" ]; then
  echo "⚠️  Deployment Guard: API nicht erreichbar (HTTP $HTTP_CODE) — Deployment wird fortgesetzt."
  echo "Response: ${BODY}"
  exit 0
fi

SCORE=$(echo "$BODY"       | grep -o '"score":[0-9]*'           | cut -d: -f2)
STATUS=$(echo "$BODY"      | grep -o '"status":"[^"]*"'          | cut -d'"' -f4)
VERDICT=$(echo "$BODY"     | grep -o '"verdict":"[^"]*"'         | cut -d'"' -f4)
EXPLANATION=$(echo "$BODY" | grep -o '"explanation":"[^"]*"'     | cut -d'"' -f4)

echo "score=${SCORE}"               >> $GITHUB_OUTPUT
echo "status=${STATUS}"             >> $GITHUB_OUTPUT
echo "verdict=${VERDICT}"           >> $GITHUB_OUTPUT
echo "explanation=${EXPLANATION}"   >> $GITHUB_OUTPUT

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🛡️  Deployment Guard — Risk Analysis"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Repo:    ${GITHUB_REPO}"
echo "  Branch:  ${GITHUB_BRANCH}"
echo "  Commit:  ${GITHUB_SHA:0:7}"
echo "  ─────────────────────────────────────"
echo "  Score:   ${SCORE} / 100"
echo "  Verdict: ${VERDICT}"
echo "  Status:  ${STATUS}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

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
