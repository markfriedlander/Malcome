# Malcome

A cultural signal detection system for people with taste who no longer have the bandwidth to maintain it manually.

Malcome watches a curated network of early, selective, scene-embedded sources across music, art, film, fashion, and design, then detects emergence patterns before they become obvious. The target user is someone who used to live deep inside culture but now has a career and less time.

## What It Does

- **Ingests** observations from 30+ curated sources via WordPress, RSS, Ghost, and Bandcamp adapters
- **Resolves** observations into canonical entities with alias merging and merge confidence
- **Scores** emergence signals using cross-source corroboration, progression pathways, and lifecycle modeling
- **Writes** a daily brief in Malcome's voice using Apple Foundation Models on-device
- **Responds** to follow-up questions in a chat thread grounded in signal evidence and Wikipedia context

## Platform

- iOS 26+ / macOS Catalyst 26+
- Apple Intelligence-capable hardware only
- Apple Foundation Models on-device, no cloud AI services
- SQLite for all persistence
- Swift / SwiftUI throughout

## How to Build

```bash
# Build for device
xcodebuild -project Malcome.xcodeproj -scheme Malcome \
  -destination 'id=<DEVICE_UDID>' \
  -derivedDataPath /tmp/MalcomeDeviceDerived build

# Deploy to device
xcrun devicectl device install app \
  --device <DEVICE_UDID> \
  /tmp/MalcomeDeviceDerived/Build/Products/Debug-iphoneos/Malcome.app

# Launch
xcrun devicectl device process launch \
  --device <DEVICE_UDID> com.MarkFriedlander.Malcome
```

Find your device UDID with `xcrun devicectl list devices`.

## Scripts

- `Scripts/run-pipeline-check.sh` — production data engine harness, no UI required
- `Scripts/run-device-smoke.sh` — real device build, install, launch, and runtime verification

## Key Documents

Read these in order before working on the project:

| File | Purpose |
|------|---------|
| `CLAUDE.md` | Operational reference. Read first every session. |
| `MALCOME.md` | Product constitution. Immutable product rules. |
| `NEXT.md` | Current priorities. Work stays within this list. |
| `ARCHITECTURE.md` | Full system architecture. Update before structural changes. |
| `DECISIONS.md` | Why things are the way they are. Read before proposing changes. |
| `HISTORY.md` | Development log. Append completed phases. |
| `REQUIREMENTS.md` | Non-negotiable technical constraints. |
| `SOURCE_DOCTRINE.md` | Source selection philosophy. |
| `SOURCE_CANDIDATES.md` | Future source directions. |

## Architecture Overview

```
Registry → Fetch → Parse → Persist → Score → Brief
```

No step is skipped. No mock pipelines. No fake implementations in the live path.

### Key Files

| File | Purpose |
|------|---------|
| `Malcome/Engine/MalcomeBriefGenerator.swift` | DraftComposer + AFM polish for brief generation |
| `Malcome/Engine/ChatEngine.swift` | Chat context assembly and grounded responses |
| `Malcome/Engine/BriefComposer.swift` | Signal/watchlist data assembly for the voice layer |
| `Malcome/Engine/SignalEngine.swift` | Signal scoring, entity resolution, lifecycle modeling |
| `Malcome/Domain/Models.swift` | All value types and enums |
| `Malcome/Data/AppRepository.swift` | SQLite persistence layer |
| `Malcome/Services/SourcePipeline.swift` | Source fetch, parse, politeness |
| `Malcome/Services/SourceRegistry.swift` | Source pack definitions |
| `Malcome/Features/Home/TodayView.swift` | Today screen — brief + chat |
| `Malcome/Features/Radar/RadarView.swift` | Signal and watchlist cards |
| `Malcome/Features/Settings/SettingsView.swift` | Source management and preferences |
| `Malcome/Developer/MalcomeAPIServer.swift` | Local HTTP API for dev iteration |

### Developer API (Debug Builds)

MalcomeAPIServer runs on port 8766 in debug builds. Endpoints:

- `GET /state` — AFM availability, prompt fingerprints, brief status
- `GET /brief` — current brief text and citations
- `GET /pipeline` — per-source health, observation counts, signal counts
- `POST /brief` — send handcrafted signal data to AFM, get brief + diagnostics
- `POST /chat` — send a chat message, get grounded response + full prompt
- `POST /command` — voice prompt overrides, politeness mode, identity resets

## Collaboration

- **Mark Friedlander** — creator, product vision, final decision-maker
- **Claude (Anthropic, via claude.ai)** — architectural collaborator, design partner
- **Claude Code** — technical implementation partner
- **Paul** — contributor, Seattle-based, source expansion and other areas
