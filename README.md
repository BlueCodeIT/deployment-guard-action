# 🛡️ Deployment Guard Action

KI-gestützter Risk Score vor jedem Deployment. Analysiert Code-Änderungen und blockiert riskante Deployments automatisch.

**Von [BlueCodeIT](https://www.bluecodeit.com)**

---

## Schnellstart

```yaml
- name: Deployment Guard
  uses: BlueCodeIT/deployment-guard-action@v1
  with:
    api-key: ${{ secrets.GUARD_API_KEY }}
```

Das war's. Kein Setup, keine Konfiguration.

---

## Vollständiges Beispiel

```yaml
name: Deploy

on:
  push:
    branches: [ main, master ]

jobs:
  risk-check:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 2

      - name: Deployment Guard
        id: guard
        uses: BlueCodeIT/deployment-guard-action@v1.5
        with:
          api-key: ${{ secrets.GUARD_API_KEY }}
          fail-on-blocked: 'true'

      - name: Score anzeigen
        run: |
          echo "Score: ${{ steps.guard.outputs.score }}"
          echo "Status: ${{ steps.guard.outputs.status }}"

  deploy:
    needs: risk-check
    runs-on: ubuntu-latest
    steps:
      - name: Deploy
        run: echo "Dein Deploy-Schritt hier"
```

---

## Inputs

| Input | Beschreibung | Pflicht | Standard |
|---|---|---|---|
| `api-key` | Deployment Guard API Key | ✅ | — |
| `fail-on-blocked` | Pipeline bei BLOCKED fehlschlagen | ❌ | `true` |
| `incidents-last-7d` | Incidents letzte 7 Tage | ❌ | `0` |
| `incidents-last-30d` | Incidents letzte 30 Tage | ❌ | `0` |

## Outputs

| Output | Beschreibung |
|---|---|
| `score` | Risk Score (0–100) |
| `verdict` | LOW / MEDIUM / HIGH / CRITICAL RISK |
| `status` | PASS / WARN / BLOCKED |
| `explanation` | KI-Erklärung auf Deutsch |

---

## Score-Logik

| Score | Verdict | Status |
|---|---|---|
| 0–49 | LOW RISK | ✅ PASS |
| 50–74 | MEDIUM RISK | ⚠️ WARN |
| 75–84 | HIGH RISK | ❌ BLOCKED |
| 85–100 | CRITICAL RISK | ❌ BLOCKED |

---

## API Key holen

1. [bluecodeit.com/signup](https://www.bluecodeit.com/signup) → Free Plan (kostenlos)
2. API Key als GitHub Secret anlegen: **Settings → Secrets → New → `GUARD_API_KEY`**
3. Action einbinden — fertig

---

## Links

- 🌐 [bluecodeit.com](https://www.bluecodeit.com)
- 📊 [Dashboard](https://www.bluecodeit.com/dashboard)
- 📖 [API Docs](https://api.bluecodeit.com/docs)
- 📧 [support@bluecodeit.com](mailto:support@bluecodeit.com)
