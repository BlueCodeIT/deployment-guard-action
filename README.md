# 🛡️ Deployment Guard Action

KI-gestützter Risk Score vor jedem Deployment. Analysiert Code-Änderungen automatisch und blockiert riskante Deployments.

**Von [BlueCodeIT](https://www.bluecodeit.com)**

---

## Schnellstart

```yaml
- uses: actions/checkout@v4
  with:
    fetch-depth: 2

- name: Deployment Guard
  uses: BlueCodeIT/deployment-guard-action@v1
  with:
    api-key: ${{ secrets.GUARD_API_KEY }}
```

> ⚠️ `fetch-depth: 2` ist erforderlich — ohne den vorherigen Commit kann kein Diff berechnet werden.

---

## Vollständiges Beispiel

```yaml
name: Deploy

on:
  push:
    branches: [ main ]

jobs:
  risk-check:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 2

      - name: Deployment Guard
        id: guard
        uses: BlueCodeIT/deployment-guard-action@v1
        with:
          api-key: ${{ secrets.GUARD_API_KEY }}
          fail-on-blocked: 'true'
          incidents-last-7d: '0'
          incidents-last-30d: '0'

      - name: Score anzeigen
        run: |
          echo "Score:   ${{ steps.guard.outputs.score }}"
          echo "Status:  ${{ steps.guard.outputs.status }}"
          echo "Verdict: ${{ steps.guard.outputs.verdict }}"

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
| `fail-on-blocked` | Pipeline bei BLOCKED fehlschlagen lassen | ❌ | `true` |
| `incidents-last-7d` | Produktionsvorfälle letzte 7 Tage (manuell angeben) | ❌ | `0` |
| `incidents-last-30d` | Produktionsvorfälle letzte 30 Tage (manuell angeben) | ❌ | `0` |

---

## Outputs

| Output | Beschreibung |
|---|---|
| `score` | Risk Score (0–100) |
| `verdict` | LOW RISK / MEDIUM RISK / HIGH RISK / CRITICAL RISK |
| `status` | PASS / WARN / BLOCKED |
| `explanation` | KI-Erklärung des Scores auf Deutsch |

---

## Was wird automatisch erkannt?

Die Action erkennt folgende Faktoren automatisch aus dem Git-Diff:

### Diff-Komplexität
- Anzahl geänderter Zeilen (hinzugefügt + entfernt)
- Anzahl geänderter Dateien

### Kubernetes-Risiko
Erkennt echte K8s-Manifeste anhand des `kind:` Feldes. Ausgeschlossen werden:
- GitHub Actions Workflows (`.github/`)
- `action.yml` / `action.yaml`
- Helm Templates (`templates/`)

Erkannte Risiken:
- Anzahl geänderter K8s-Manifeste
- `replicas: 1` in einem Deployment → Single Replica Flag
- Deployment vorhanden aber kein `PodDisruptionBudget` → Missing PDB Flag

### Helm-Parameter
- `helm_values_changed` — YAML-Dateien mit `image:`, `tag:`, `replicaCount:` oder `resources:`
- `helm_chart_bumped` — `Chart.yaml` oder `Chart.yml` geändert

### Dependency-Risiko
Erkennt Änderungen an:
`package.json`, `requirements.txt`, `go.mod`, `pom.xml`, `Gemfile`, `Cargo.toml`, `yarn.lock`, `package-lock.json`

### Major Version Bumps
Erkennt Major-Upgrades automatisch in:
- `package.json` — Hauptversionsnummern verglichen
- `requirements.txt` — `==X.y.z` Versionsnummern verglichen
- `go.mod` — `/vX` Module-Pfade verglichen

### Fehlerhistorie
Wird **nicht** automatisch erkannt — muss manuell übergeben werden:

```yaml
- name: Deployment Guard
  uses: BlueCodeIT/deployment-guard-action@v1
  with:
    api-key: ${{ secrets.GUARD_API_KEY }}
    incidents-last-7d: '2'
    incidents-last-30d: '5'
```

---

## Score-Logik

| Score | Verdict | Status |
|---|---|---|
| 0–49 | LOW RISK | ✅ PASS |
| 50–74 | MEDIUM RISK | ⚠️ WARN |
| 75–84 | HIGH RISK | ❌ BLOCKED |
| 85–100 | CRITICAL RISK | ❌ BLOCKED |

### Gewichtung der Faktoren

| Faktor | Gewicht* | Beschreibung |
|---|---|---|
| Diff-Komplexität | 30% | Zeilen + Dateien (logarithmische Skala) |
| Kubernetes-Risiko | 30% | Manifeste, Helm, ArgoCD, Single Replica, PDB |
| Dependency-Risiko | 20% | Updates, Major Version Bumps |
| Fehlerhistorie | 20% | Vorfälle letzte 7 und 30 Tage |

*Adaptive Gewichtung: Bei Repos ohne K8s-Kontext wird das K8s-Gewicht automatisch auf die anderen Faktoren verteilt.

Thresholds (Standard: WARN ab 50, BLOCK ab 75) sind für Team-Nutzer im Dashboard konfigurierbar.

---

## Häufige Probleme

### K8s-Score ist 0 obwohl Manifeste geändert wurden

Die Action erkennt K8s-Manifeste anhand des `kind:` Feldes. Prüfe:
- Enthält deine YAML-Datei `kind: Deployment` / `kind: Service` etc.?
- Liegt die Datei nicht in `.github/` oder `templates/`?
- Ist `fetch-depth: 2` gesetzt?

### Score ist immer LOW obwohl viel geändert wurde

Fehlerhistorie (`incidents-last-7d`, `incidents-last-30d`) ist standardmäßig 0. Wenn dein Team Produktionsvorfälle hat, übergib diese manuell.

### Pipeline schlägt nicht fehl bei BLOCKED

Stelle sicher dass `fail-on-blocked: 'true'` gesetzt ist (Standardwert). Und `continue-on-error: true` darf nicht gesetzt sein wenn der Gate greifen soll.

---

## Debug-Output

Die Action gibt alle erkannten Werte vor dem API-Call aus:

```
  [guard] diff_lines_added:     245
  [guard] diff_lines_removed:   88
  [guard] diff_files_changed:   12
  [guard] k8s_manifests:        3
  [guard] single_replica:       true
  [guard] missing_pdb:          true
  [guard] helm_values_changed:  1
  [guard] helm_chart_bumped:    false
  [guard] dependency_updates:   2
  [guard] major_version_bumps:  1
  [guard] incidents_7d:         0
  [guard] incidents_30d:        0
```

---

## API Key holen

1. [bluecodeit.com/signup](https://www.bluecodeit.com/signup) → Free Plan (kostenlos, keine Kreditkarte)
2. API Key als GitHub Secret anlegen: **Settings → Secrets and variables → Actions → New repository secret → `GUARD_API_KEY`**
3. Action einbinden — fertig

---

## Links

- 🌐 [bluecodeit.com](https://www.bluecodeit.com)
- 📊 [Dashboard](https://www.bluecodeit.com/dashboard)
- 🚀 [API Key holen](https://www.bluecodeit.com/signup)
- 📧 [support@bluecodeit.com](mailto:support@bluecodeit.com)