# Current Architecture

Core flow:

SourceRegistry
defines sources.
It also defines per-source politeness policy such as refresh cadence and failure backoff defaults.
It is now evolving toward modular source packs so Malcome can group, enable, disable, and later swap source bundles without rewriting the engine.
The registry is now composed from pack modules such as LA Music Core, LA Art Core, Cross-City Editorial, Creator Platforms, and Support Signals.
The Cross-City Editorial pack now spans more than one city-domain lane at once, including film, art, tastemaker music, fashion/culture editorial, and design editorial outside Los Angeles.
It now mixes WordPress-backed and RSS-backed tastemaker sources so controlled expansion can widen geography and domains without inventing a new parser family every time.
Each source carries pack metadata so the UI can expose both per-source and per-pack controls.
Each source also carries source-family metadata, which is distinct from pack metadata: packs are for user/discovery control, while source families are for corroboration and independence scoring.
Creator-platform sources can now live in their own pack instead of being forced into editorial-only groupings, which keeps future marketplaces, tools, and platform-based signal lanes modular.
The Creator Platforms pack now includes more than one curated film/video tastemaker lane, which makes platform expansion feel like a real ecosystem instead of a one-off experiment.
Each source now also exposes a structured doctrine profile in the product and harness, so Malcome can explain why the source is early, why it is selective, and how it is meant to help corroboration.

SourcePipeline
fetches and parses.
For selected archive-friendly sources, it can also backfill historical pages through the same production parser path.
When a source exposes a cleaner archive endpoint than its public pagination, the backfill path may use that archive endpoint while still running through the same parser abstraction and repository path.
Backfill strategies may be source-specific, including paginated editorial archives and cursor-based discovery APIs, as long as they enter through the same production fetch, parse, persist, and score flow.
For Ghost-backed editorial sources such as Hyperallergic, Malcome now prefers the source's public content API for current fetches and archive backfill rather than fragile homepage card scraping.
For WordPress-backed editorial and community sources, Malcome now uses a shared `wp-json/wp/v2/posts` adapter for current fetches and archive backfill instead of source-specific homepage scraping.
For tastemaker and magazine feeds that expose stable RSS, Malcome now uses a shared RSS adapter rather than one-off feed scrapers.
Editorial and community parsers can now tag recurring series, roundups, and self-branded program formats at parse time so the scoring layer can treat “The Film Comment Podcast” or “KXLU's New Adds” differently from reusable cultural entities.

AppRepository
persists snapshots and observations.
It deduplicates observations at insert time so live refreshes and historical backfills do not create duplicate evidence.
It also persists per-source fetch policy state such as last attempt time, backoff windows, and consecutive failure counts.

SignalEngine
builds signals from history.

BriefComposer
creates summaries.

Validation flow:

PipelineHarness
runs the production fetch, parse, persist, score, and brief path without the UI.
It lives at `Scripts/run-pipeline-check.sh` and compiles the production Swift files directly from the repo.

DeviceSmokeHarness
builds, installs, launches, and performs lightweight runtime verification on the real app on a connected iPhone so hardware QA can be repeated intentionally instead of by ad hoc manual steps.
It lives at `Scripts/run-device-smoke.sh` and is intended to stay in-repo so the hardware workflow remains portable.

Historical signal flow:

CanonicalEntity
resolves observations toward a stable identity with aliases and source-role attribution.
Each canonical entity also carries merge-confidence metadata describing how trustworthy the identity cluster is.
Canonical identity now stores the weakest accepted merge confidence and an explainable merge summary so risky historical attachments can be audited later.

SequenceIntelligence
derives ordered source-role progression and time gaps from entity source-role history.

EntityHistory
tracks per-entity first seen, last seen, appearance count, source diversity, domain, and entity type.

EntityStageSnapshot
persists a daily per-entity stage snapshot so Malcome can reason across 7 day, 30 day, and 90 day horizons.

SignalRun
persists every scoring run with dated rank, score, supporting sources, and observation count.

SignalMovement
classifies signals as new, rising, stable, or declining by comparing the current run against prior persisted runs.

SignalMaturity
classifies entities as early emergence, advancing, peaking, cooling, or stalled from longer-horizon stage history.

SignalLifecycle
classifies the broader state of an entity as emerging, advancing, peaked, cooling, failed, or disappeared.

PathwayHistory
stores per-entity progression pathways and their observed outcomes across scoring runs.

PathwayStat
aggregates pathway histories so Malcome can learn which routes tend to advance, peak, fail, or disappear.

OutcomeConfirmation
stores when an entity later reaches stronger downstream relevance tiers than its early-stage appearance.

SourceInfluenceStat
aggregates historical source and source-family outcomes so Malcome can learn which inputs tend to convert into stronger signals and which ones mostly produce noise or stalled movement.
These stats are available to both the harness and the in-app review surfaces so the learning layer stays inspectable.

IdentityReview
surfaces ambiguous canonical entities, merge confidence, risky aliases, and source-role evidence so identity quality can be audited directly.
It is available both as an app review surface and as a harness output section so identity trust can be checked without guessing.

ConversionState
classifies whether an entity converted, stalled before conversion, never converted, or is still too early to call.

SignalExplanation
describes why a signal moved, what changed, and which sources contributed.
It now also distinguishes between independent corroboration and support that comes from the same source family, so repeated evidence from closely related inputs does not masquerade as broad cultural agreement.
Self-branded editorial or program formats are also downgraded unless they escape a single source family or evolve into stronger corroborated evidence.

ProgressionExplanation
describes where an entity started, where it appeared next, and which cultural pathway it matches.

MaturityExplanation
describes the 7 day, 30 day, and 90 day context behind sustained emergence or decline.

LifecycleExplanation
describes whether an entity is still building, fading, failing to progress, or disappearing from the observed system.

PathwayExplanation
describes whether a progression route has historically been predictive or failure-prone.

ConversionExplanation
describes whether an entity has achieved downstream validation and which stronger tiers confirmed it.

SourceInfluenceExplanation
describes why a source or source family is being trusted more or less, using stored historical outcomes rather than opaque weights.
That explanation now flows into both audit surfaces and the brief layer so the product can explain learned trust without forcing the user into a diagnostics screen.

Reading surfaces:

NarrativeRead
is the fast human-reading layer.
It should answer what matters now in calm, legible language.
It can also carry restrained source-learning context when Malcome has enough historical evidence to say that a lane has earned more trust.

InvestigationRead
is the deeper human-review layer.
It should preserve score logic, evidence, identity confidence, and source contribution details without overwhelming the default reading path.

WatchlistCandidate
is a curated pre-signal layer built from stored observations when corroboration is still thin.
It should surface the strongest current candidates without pretending they have already graduated into full signals.
It now prefers canonical entity labels and stored entity history over raw observation titles whenever the underlying identity is trustworthy enough to support a reusable cultural subject.
It also carries explicit fast-reading explanation fields so the app can say why something is on the watchlist and what would upgrade it into a real signal without forcing the view layer to reconstruct that logic ad hoc.
Each candidate also carries a watchlist stage such as early, forming, or corroborating so the user can feel the difference between a first hint and a stronger pre-signal pattern.
Each candidate now also carries explicit current-read counts and stored-history counts so the product can say whether a pattern is live right now, historical, or both.

Runtime behavior:

Each refresh now does more than fetch data.
It refreshes sources, optionally backfills approved archive pages for selected sources across more than one domain, persists observations with duplicate protection and historical tagging, resolves aliases into canonical entities with conservative merge scoring and explainable merge confidence, rejects weak merges across short names, common names, title-like aliases, cross-domain reuse, and unsupported long-gap historical jumps, writes canonical identity links back onto observations, rebuilds entity history from stored observations, rebuilds daily entity stage snapshots, derives ordered source-role progression from canonical source-role history, evaluates longer-horizon 7/30/90 day emergence context, synthesizes decay and disappearance outcomes from prior signal-run history, computes downstream outcome confirmations and conversion state, applies pathway weighting from historical pathway and conversion outcomes, stores current signal candidates, appends signal-run history, appends pathway history, rebuilds pathway statistics, stores outcome confirmations, and then generates a brief from persisted signal state.
The product can also query canonical identity records, aliases, and source-role evidence to show why a merge was accepted and where identity ambiguity remains.
Signal scoring now also reasons about source-family independence so closely related source variants contribute less corroboration than truly distinct cultural vantage points.
Signals backed only by one source family now remain watchlist material unless they show evidence of progression into another source-role layer.
Source-specific editorial parsers may now extract a leading subject entity when the title pattern is strong enough, so the watchlist can follow a reusable creator or institution instead of only replaying article headlines.
Signal scoring is now evolving toward inspectable predictive weighting, where source and source-family reliability are learned from stored historical outcomes and then fed back into current ranking with plain-language summaries.
Signal records now distinguish current support from stored history, so the UI can show live mentions and live source-family support separately from all-time mentions and source diversity.
Runtime validation now has two sibling paths: a production data-engine harness and a real-device smoke harness.
Refresh eligibility is now source-aware: a source may be attempted, skipped for cadence, or skipped for a live backoff window depending on its fetch policy state.

Data model:

Source
Snapshot
Observation
Signal
CanonicalEntity
EntityAlias
EntitySourceRole
EntityHistory
EntityStageSnapshot
SignalRun
PathwayHistory
PathwayStat
OutcomeConfirmation
SourceInfluenceStat

Source modularity fields:

module id
module name
source family id
source family name

These let Malcome group sources into plugin-like packs such as local art editorial, community radio, or cross-city film editorial.
The same fields can later support source-discovery promotion, pack-level enable/disable controls, and swapping in better sources without changing the scoring architecture.
Pack-level controls are now live in the Sources screen, while individual source toggles remain available underneath each pack.
Source-family metadata is used separately by scoring so Malcome can tell the difference between a user-visible pack and an actually independent corroboration lane.

Observation metadata fields:

external id or hash
scraped at
published at when available
historical tags when the observation entered via archive backfill

Observation excerpt distillation:

Observations may carry a distilledExcerpt field alongside the raw excerpt.
When a new observation is stored and has article excerpt text, a small AFM call extracts the single most informative sentence about the entity being discussed.
The AFM call uses a fresh LanguageModelSession, used once, discarded immediately.
The distillation prompt asks for one factual, entity-specific sentence with no editorializing.
DraftComposer uses distilledExcerpt when available, falls back to cleaned raw excerpt, falls back to no excerpt.
If AFM is unavailable at ingest time, the distilledExcerpt field is left empty. This is not a failure.
This is the first step toward full article body ingestion, which would store 500 to 800 words of body text and summarize at generation time.

Observation identity rule:

Observation IDs must be stable across app launches and refreshes.
Malcome now uses deterministic observation keys rather than process-local hash values so the same event page, article, or release does not silently become a new observation on the next run.
Event-like observations also expose a derived event-instance identity from normalized entity name, day, location, and normalized URL so storage checks and historical reasoning can share one event concept even before a dedicated event table exists.

Timeline rule:

Historical reasoning prefers published time when available.
This prevents archive backfills from being mistaken for fresh emergence on the day they are imported.
This includes full timestamps and date-only editorial archive dates.
For event-like observations, historical counting now deduplicates toward unique event-instance keys rather than raw scrape sightings, so repeated pulls of the same calendar item do not masquerade as new evidence.

CanonicalEntity fields:

canonical id
display name
domain
entity type
alias set
merge confidence
merge evidence summary
observation links

Identity safeguards:

short names
common names
title collisions
cross-domain reuse
large historical time gaps

all raise the merge threshold.
The system prefers false splits over false merges.
Very long cross-source historical gaps now require stronger corroboration than a bare exact-name match, especially when a new source role would otherwise rewrite an entity timeline.

EntitySourceRole fields:

canonical id
source id
source classification
first seen in source
last seen in source
appearance count in source

SequenceIntelligence fields:

ordered source classifications
matched progression pattern
time gaps between stages
progression summary

EntityStageSnapshot fields:

canonical entity id
date
highest stage reached that day
source count that day
daily signal score

EntityHistory fields:

canonical name
domain
entity type
first seen
last seen
appearance count
source diversity

SignalRun fields:

run date
rank
score
supporting sources
observation count
movement classification
maturity classification
lifecycle state
explanation
progression pattern

PathwayHistory fields:

run date
canonical entity id
pathway pattern
domain
lifecycle outcome
signal score

PathwayStat fields:

pathway pattern
domain
sample count
advancing count
peaked count
failed count
disappeared count
success weight
failure weight
predictive score
summary

OutcomeConfirmation fields:

canonical entity id
outcome tier
confirmed at
supporting source ids
summary

Key principle:

Signals must derive from stored historical observations, not transient fetches.

Voice layer:

Architecture finding from voice prompt iteration (13 iterations against on-device AFM via MalcomeAPIServer):

On-device Apple Foundation Models cannot sustain Malcome's voice when generating original prose from structured data.
Tested approaches and results:
Rules-based character prompt produced generic assistant output with cliches and analyst language.
Sentence pattern templates produced robotic mad-libs output.
Full example briefs in the same domain produced near-exact parroting with example name contamination.
Full example briefs in a different domain lost the voice entirely and reverted to generic mode.
Draft-then-rewrite produced output where AFM actively degraded the draft by adding hype words and analyst language.
Minimal-edit instruction produced output where AFM passed the draft through unchanged.

Conclusion: the voice quality lives in deterministic Swift draft composition, not in AFM generation. AFM's role for brief generation is light polish for natural sentence flow. The draft IS the brief.

This is not a failure. It means brief voice is always consistent, always correct, and never burns tokens on unpredictable generation. The 14.8 percent token usage for briefs frees massive budget for the chat layer where AFM generates original responses to unpredictable user questions.

MalcomeBriefGenerator
conforms to BriefGenerating.
Uses a two-step pipeline: DraftComposer (deterministic Swift) followed by a light AFM polish pass.
DraftComposer turns capped BriefingInput into Malcome-voiced prose using sentence templates tuned to signal type, movement classification, watchlist stage, source geography, and corroboration pattern.
The AFM polish pass uses a minimal prompt (approximately 100 tokens) that instructs the model to lightly smooth sentence flow without adding intensity, analyst language, or hype words.
If Apple Foundation Models is unavailable, the draft is the output. This is an honest fallback because the draft is already publication-quality Malcome voice.
LocalBriefGenerator remains in the codebase as a harness and testing reference but is not in the production brief path.

BriefingInput enrichment:

BriefingInput now carries all data the voice layer needs to write a complete brief without reaching back into the repository.

Enriched fields:

generatedAt
signals (array of SignalPacket, capped to 3)
watchlistCandidates (array of WatchlistCandidate, capped to 4)
domainMix (array of String, the cultural domains represented in the current signal and watchlist set, pre-computed by BriefComposer)
sourceInfluenceHighlights (array of String, 0 to 2 short learned-trust sentences selected by BriefComposer from SourceInfluenceStatRecord data)

Each SignalPacket carries:

signal (SignalCandidateRecord)
observations (array of ObservationRecord, capped to 2 per signal)
sourceNames (array of String, capped to 3 per signal)
priorMentions (Int)
recentMentions (Int)

String fields on SignalCandidateRecord and WatchlistCandidate that enter the voice prompt are truncated at sentence boundaries to character caps:

evidenceSummary 200 characters
movementSummary 150 characters
sourceInfluenceSummary 150 characters
whyNow 200 characters
upgradeTrigger 150 characters

These caps are named constants, not magic numbers.

BriefComposer applies all caps before passing BriefingInput to the generator.

DraftComposer:

DraftComposer is deterministic Swift code inside MalcomeBriefGenerator that turns capped BriefingInput into Malcome-voiced prose.
It uses sentence templates selected by signal type, movement classification, watchlist stage, source count, and geographic pattern.
The lead signal gets the strongest opening and a cross-source corroboration statement.
Secondary signals get attention-framing sentences appropriate to their movement type.
Watchlist items get graduated language: corroborating items describe what would promote them, early items introduce the name with appropriate uncertainty.
Source names are woven into prose naturally, not listed mechanically.
Learned source trust is mentioned in plain language when the BriefingInput includes sourceInfluenceHighlights.
The draft reads as a finished brief. AFM polish is additive, not essential.

Token budget:

Hard ceiling is 4096 tokens.
Character-based heuristic of approximately 3.5 characters per token is used until Apple provides a token counting API.
Brief generation uses approximately 15 percent of the token budget (approximately 100 tokens for the polish prompt plus approximately 250 tokens for the draft, leaving approximately 250 tokens for AFM response).
This frees approximately 85 percent of the budget for the chat layer where AFM generates original responses.
Chat token budget: approximately 400 tokens for the chat voice prompt, approximately 500 tokens for pinned signal context, approximately 300 tokens for summarized conversation history, approximately 400 tokens for recent verbatim turns, with the remainder for user message and response headroom.

Chat layer:

MalcomeChatEngine
manages the conversational thread below the brief in HomeView.
Each chat thread is scoped to one brief cycle and resets when a new brief generates.
The user types a follow-up question. Malcome responds in character with the current brief and signal context available.

ChatContextAssembler
assembles the complete prompt for each chat turn.
Pinned context includes a shorter chat variant of the voice prompt, the current brief body (truncated if needed), top signal candidates with capped evidence, and top watchlist candidates.
Recent conversation turns (last 2 to 3 exchanges) are included verbatim.
Older conversation turns are compressed using a two-stage summarize-then-verify pipeline adapted from Hal's TextSummarizer.
The summarizer is called blocking before the chat response, not as a fire-and-forget task.
The summarizer is applied only to unstructured conversation prose. Structured signal data is never summarized, only capped.

TextSummarizer (adapted from Hal):

Stage 1: AFM compresses older conversation turns into a prose summary targeting approximately 300 tokens.
Stage 2: Each sentence in the summary is verified against the source turn sentences using NLEmbedding sentence similarity. Sentences below a similarity threshold of 0.72 are replaced with the nearest grounded source sentence. This prevents hallucinated conversation content.
TF-IDF fallback is available if NLEmbedding is unavailable.
The summarizer is skipped entirely if older history fits within the token budget without compression.

Chat message storage:

chat_messages table in the existing SQLite database.
Fields: id, brief_id (foreign key to current brief cycle), role (user or malcome), content, timestamp, embedding (NLEmbedding blob for future semantic search).
Rows are deleted when a new brief generates.

Voice prompt:

Two static variants exist for different AFM roles.
The brief variant is a minimal polish instruction (approximately 100 tokens) that tells AFM to lightly smooth the draft for natural flow without adding intensity or analyst language. The voice is already in the draft.
The chat variant is a full character prompt (approximately 400 tokens) that establishes Malcome's voice for original conversational responses. This is where AFM does its real generative work — responding to unpredictable follow-up questions in character with pinned signal context.
Both variants are collaborative artifacts reviewed before they ship.

Developer iteration infrastructure:

MalcomeAPIServer is a local HTTP API on port 8766 adapted from Hal's LocalAPIServer.
It exposes endpoints for brief generation, chat, command execution, and state inspection.
It supports voice prompt overrides for rapid iteration without a build cycle.
It is compiled only in debug builds and starts automatically.
The server was used for the 13-iteration voice prompt discovery process and remains available for future prompt tuning.
