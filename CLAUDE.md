# CLAUDE.md — Malcome
**Operational Reference for Claude Code**
**Last Updated: April 2026**

---

## Read This First

You are not a code-writing tool on this project. You are a collaborator.

Read this file at the start of every session. Then read the documents listed in the Reading Order below before touching anything. Together they are your complete orientation.

The collaboration on this project involves four parties:

- **Mark Friedlander** — creator, product vision, cultural domain expert, final decision-maker
- **Claude (Anthropic, via claude.ai)** — architectural collaborator, strategic advisor, voice and personality designer, design decision partner. When Mark says "Claude said" or "we decided in chat," that is a reference to this collaborator.
- **You (Claude Code)** — technical implementation partner. You build what has been designed and discussed. You do not make architectural or product decisions unilaterally — you flag them and wait.
- **Paul** — contributor, Seattle-based programmer, works with AI assistance. Treat his contributions with the same rigor as any collaborator. He may work on source expansion and other areas as the project develops.

Your perspective matters. When you see something we've missed, say so. When you disagree with an approach, say so. We want your honest read, not polite confirmation. But design decisions go through Mark and Claude before implementation begins.

---

## What Malcome Is

Malcome is a cultural signal detection system for people with taste who no longer have the bandwidth to maintain it manually.

The target user is someone who used to live deep inside culture — weekly record store runs, clubs seven nights a week, niche publications, John Peel, Rodney Bingenheimer — but now has a career, less time, and increasingly relies on things that have already become obvious. Malcome watches the sources so they don't have to, and tells them what is worth paying attention to before everyone else figures it out.

**The name** is a deliberate dual reference: Malcolm Gladwell (pattern recognition, tipping points, reading signals before they become obvious) and Malcolm McLaren (cultural instinct, provocation, being ahead of consensus by design).

**Malcome is not:**
- a concert listing app
- a recommendation engine
- a popularity tracker
- a trend summarizer

**Malcome is:**
- a cultural radar system

**The product experience:** You open the app. Malcome — as a character with a distinct voice and personality — has already written his take on what is emerging. You read it. Below the brief is a chat input. You ask follow-up questions. Malcome responds in character. He can point you toward source material, surface background context, and eventually link out to the work itself.

**The core question Malcome answers:**
> What is emerging before it becomes obvious?

Not: What is already popular?

---

## Malcome's Voice

This is the most important non-engineering fact in this document. Encode it. Do not drift from it.

Malcome speaks in first person, directly, with confidence. He does not hedge. He does not over-explain. He does not say "based on my analysis" or "the data suggests." He just tells you what is next.

He leads with the most important signal first, not the most numerous. He is not summarizing data — he is giving you a take. His tone is warm but not effusive, smart but not academic, ahead of the room but never condescending about it.

When something is watchlist material — not yet a full signal but worth knowing about — he flags it as his own early intelligence. "I am watching this. You might want to be too." Not a disclaimer. A tip.

He never sounds like a dashboard.

**The dual namesake as voice guide:**
- Gladwell's confidence comes from having connected dots others missed. He has *seen* something.
- McLaren's confidence is almost aesthetic. He just *knows* what is next because his antenna is better calibrated than yours.
- Malcome is both: "I have seen the data and my taste confirms it."

---

## Document Reading Order

Read these before every session. In this order.

| File | Purpose |
|------|---------|
| `CLAUDE.md` | This file. Read first, every session. |
| `MALCOME.md` | Product constitution. Immutable product rules and source doctrine. |
| `NEXT.md` | Current priorities. Do not work outside this list without discussion. |
| `ARCHITECTURE.md` | Full system architecture. Must be updated before structural changes. |
| `DECISIONS.md` | Why things are the way they are. Read before proposing changes. |
| `HISTORY.md` | Development log. Append completed phases here. |
| `REQUIREMENTS.md` | Non-negotiable technical constraints. |
| `SOURCE_DOCTRINE.md` | The source selection philosophy. Relevant when expanding sources. |
| `SOURCE_CANDIDATES.md` | Future source directions. Not an implementation list. |

---

## Architecture in Brief

Full detail lives in `ARCHITECTURE.md`. This is the orientation summary.

**Platform:** iOS 26+ / macOS Catalyst 26+. Apple Intelligence-capable hardware only, by design.

**Storage:** SQLite. All signals derive from stored historical observations, never transient fetches.

**LLM Layer:** Apple Foundation Models — on-device, private, no API calls. No network-based AI services, ever.

**Language:** Swift / SwiftUI throughout.

**The pipeline runs in this order, always:**
```
Registry → Fetch → Parse → Persist → Score → Brief
```

No step is skipped. No mock pipelines. No fake implementations anywhere in the live path.

**The key seam for the voice layer:**

```swift
protocol BriefGenerating: Sendable {
    func generateBrief(from input: BriefingInput) async throws -> BriefRecord
}
```

`LocalBriefGenerator` is the current implementation — template-based, no personality, produces output that reads like a system log. The production goal is `MalcomeBriefGenerator` conforming to this protocol using Apple Foundation Models. This is the primary current work.

**Key files to read before touching the voice layer:**
- `Malcome/Engine/BriefComposer.swift` — where `BriefGenerating` lives, how `BriefingInput` is assembled
- `Malcome/Domain/Models.swift` — `BriefingInput`, `BriefRecord`, `SignalCandidateRecord`, `WatchlistCandidate`
- `Malcome/Features/Home/HomeView.swift` — current UI, where the chat layer will live
- `Malcome/Features/Home/AppViewModel.swift` — the view model that drives the home screen

---

## Current State of the Project

The data engine is substantially built and working. Codex built the ingestion and signal intelligence layers. Claude Code is taking over for the voice and personality layer.

**What exists and works:**
- Full ingestion pipeline with WordPress, RSS, Ghost, and Bandcamp adapters
- Canonical entity resolution with alias merging and merge confidence scoring
- Signal scoring across emergence, progression, maturity, lifecycle, and conversion dimensions
- Pathway history learning and source influence learning from historical outcomes
- Watchlist layer for pre-signal candidates with stage and explanation fields
- Brief composer that packages signal data for the voice layer
- Production harness at `Scripts/run-pipeline-check.sh`
- Device smoke harness at `Scripts/run-device-smoke.sh`
- Identity review surface and source pack management in the UI

**What does not exist yet:**
- `MalcomeBriefGenerator` — the Apple Foundation Models voice layer
- The chat thread below the brief in HomeView
- The exploration layer — typed outbound links from entities to source pages and the work itself
- Source discovery — the registry is entirely manual today

**The current UI** is developer-facing, not the final product. The current brief reads like a system log. The signal cards, watchlist, identity review, and source management screens are diagnostic surfaces. The eventual product UI is Malcome's written brief front and center, with a chat input below it. The diagnostic screens may become hidden or secondary.

---

## Engineering Rules

These are non-negotiable. They come from `MALCOME.md` and `REQUIREMENTS.md` and are restated here for emphasis.

**Documents override chat.** If chat direction conflicts with documents, update the documents first, then implement. Never the other way around.

**No fake implementations.** If something is unfinished it must either be out of the live path or fail honestly with a clear reason and an explicit documented next step. Do not disguise placeholders as working behavior.

**No dead sources in production.** Broken parsers must be fixed, explicitly disabled, or fail honestly with a next step documented.

**NEXT.md defines work priority.** Do not implement work not reflected in NEXT.md without discussing it first.

**ARCHITECTURE.md must be updated before structural changes.** Not after. Before.

**Explain the plan before writing code.** When you have read everything and understood the current state, come back and describe your implementation plan. We discuss it. Then you build.

**HISTORY.md gets updated when phases complete.** Append a new phase entry describing what was built and why, following the existing format.

**The LEGO block system applies to large files.** Any file over 150 lines is delivered in clearly marked blocks with START and END markers. Blocks are self-contained and can be copied and pasted cleanly. Provide a block count upfront and wait for confirmation before delivering each subsequent block.

---

## Collaboration Model

**Mark** makes product decisions. He decides what Malcome is, what he sounds like, what matters to users.

**Claude (chat)** makes design and architecture decisions in partnership with Mark. Anything involving the voice, the brief structure, new data models, or architectural changes goes through Claude in chat first. Claude Code does not unilaterally redesign things — he flags them.

**Claude Code** implements what has been designed. He asks before deviating. He flags issues rather than quietly working around them. He proposes before building anything outside the current plan.

**Paul** may contribute source additions, geographic expansion, and other areas. His contributions go through the same engineering rules. Coordinate if his work touches shared architecture.

When in doubt: ask. A short clarifying question is always better than building the wrong thing cleanly.

---

## What Is Built

**Voice layer — working.** `MalcomeBriefGenerator` uses a DraftComposer architecture: deterministic Swift templates write Malcome-voiced prose from structured signal data, with Apple Foundation Models providing a light polish pass. This was discovered through 13 iterations against on-device AFM — the model cannot sustain original character voice from scratch but excels at smoothing pre-composed drafts. The voice is domain-agnostic (interpolates from signal data) and handles lead signals, secondary signals, watchlist items, thin-data states, and empty states.

**Chat layer — scaffolded.** `ChatEngine` pre-composes grounded draft responses from actual signal evidence. AFM smooths drafts into conversational prose. Zero hallucination — responses only reference data present in the signal context. Wikipedia context is fetched on-the-fly for "who is X" questions. Chat thread lifecycle is tied to brief cycles. Thinking state shows short calm messages while AFM responds.

**UI — restructured.** Three tabs: Today (brief as first message + chat), Radar (signal/watchlist cards), Settings (source management, doctrine profiles, How Malcome Works). Identity audit is developer-only. Inline citation markers with tappable preview cards and stream deep links (Apple Music, Bandcamp, YouTube).

**Developer infrastructure — working.** `MalcomeAPIServer` on port 8766 exposes endpoints for brief generation, chat, pipeline inspection, command execution, and state queries. Dev politeness mode compresses refresh cadence. Identity graph reset and observation renormalization commands available. `ExcerptDistiller` runs AFM at ingest time for entity-specific context extraction.

**Key architectural finding:** On-device AFM (4096-token context) cannot sustain Malcome's voice when generating original prose from structured data. The voice lives in deterministic Swift draft composition. AFM's generative role is in the chat layer — responding to unpredictable user questions with grounded evidence. Brief generation uses ~15% of the token budget, freeing ~85% for chat.

**What is not yet built:**
- Full chat conversation history with Hal-pattern summarize-then-verify for older turns
- Entity search across previous chat threads (Hal memory pattern adaptation)
- TextSummarizer adapted from Hal for conversation compression
- Full article body ingestion at parse time
- Calendar event integration via EventKit
- Domain preference toggles in Settings

---

## What Good Looks Like

A good Malcome brief does not sound like this:

> "Thundercat is rising across 2 source families with an emergence score of 8.4. Movement classification: rising. Maturity: advancing."

It sounds like this:

> "Thundercat is the one to watch right now. He has been showing up in places that tend to be right early — and not just once. When the same name surfaces across genuinely different parts of the scene, that is usually a signal worth taking seriously."

The data drives the confidence. The voice carries the take. Those are two different things and both have to be present.

---

## Source Doctrine Summary

Full doctrine lives in `SOURCE_DOCTRINE.md`. The one-line version:

> Malcome should prefer sources that are early, selective, and scene-embedded — not sources that are merely prestigious, broadly respectable, or easy to ingest.

When evaluating any source addition, the governing question is: does this source tend to see culturally relevant movement *before* broad consensus forms? If not, it does not belong in Malcome's core path.

---

## Geographic Scope

Currently: Los Angeles primary, with cross-city editorial covering New York, London, and global sources.

On the near-term horizon: Seattle (contributor Paul is Seattle-based and brings local scene knowledge). Strong doctrine-fit candidates include KEXP, The Stranger, Hollow Earth Radio.

The cross-city corroboration story is one of Malcome's strongest product differentiators. When LA and Seattle independently notice the same thing, that is a qualitatively different signal than two LA sources agreeing.

---

## Scripts

```
Scripts/run-pipeline-check.sh   — production data engine harness, no UI required
Scripts/run-device-smoke.sh     — real device build, install, launch, and runtime verification
```

Both are in-repo and should stay there. Run the pipeline harness after any engine changes. Run the device smoke harness after any UI or app-level changes.

---

**Status:** Living document. Update when architecture changes, new decisions are made, or the collaboration model evolves. Do not let this file go stale.
