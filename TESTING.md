# Testing Philosophy

Malcome uses three testing harnesses that validate different layers of the system.

## 1. Production Pipeline Harness

**Script:** `Scripts/run-pipeline-check.sh`

Runs the full fetch → parse → persist → score → brief pipeline without the UI. Validates that the data engine produces correct output from real source data. This is the primary harness for engine changes — parser updates, scoring adjustments, entity resolution fixes.

## 2. Device Smoke Harness

**Script:** `Scripts/run-device-smoke.sh`

Builds, installs, launches, and performs runtime verification on a connected iPhone. Copies the on-device SQLite database and reports table counts. Validates that the app creates and maintains runtime state on actual hardware. Run after any UI or app-level changes.

## 3. Developer API Harness

**Server:** `MalcomeAPIServer` on port 8766 (debug builds only)

Local HTTP API for rapid iteration without a build cycle. Endpoints for brief generation, chat, pipeline inspection, command execution, and state queries. Used for voice prompt iteration, signal inspection, and data debugging.

### Key Commands

| Command | Purpose |
|---------|---------|
| `NEW_BRIEF_CYCLE` | Force refresh (bypasses politeness) + generate brief |
| `RELINK_OBSERVATIONS` | Re-resolve all observations into canonical entities |
| `RENORMALIZE_OBSERVATIONS` | Re-apply parser normalization to stored data |
| `RETAG_OBSERVATIONS` | Re-run editorial content tagger on all observations |
| `RESET_IDENTITY_GRAPH` | Surgical delete of identity layer, preserving observations |
| `EXTRACT_ROUNDUPS` | AFM entity extraction on existing roundup articles |
| `SET_POLITENESS_MODE:dev` | 2-minute cadence floor for testing |
| `GET_STATE` | Current app state snapshot |

### Diagnostic Endpoints

| Endpoint | Returns |
|----------|---------|
| `GET /state` | AFM availability, prompt fingerprints, brief status |
| `GET /brief` | Current brief text and citations |
| `GET /pipeline` | Per-source health, observation counts, signal counts |
| `POST /brief` | Send handcrafted signal data to AFM |
| `POST /chat` | Send chat message with full prompt diagnostics |

## Testing Workflow

1. Make engine changes → run pipeline harness
2. Make UI changes → run device smoke harness
3. Make voice/prompt changes → use developer API harness
4. After any identity or parser change → `RELINK_OBSERVATIONS` then `NEW_BRIEF_CYCLE`
5. After any tag pattern change → `RETAG_OBSERVATIONS` then `RELINK_OBSERVATIONS`
