# Current Priorities

1 Ship the product UI.
The Today screen shows only the brief and the chat input. Everything else moves to Radar or Settings.
Navigation is three tabs: Today (brief and chat), Radar (signals and watchlist for deeper exploration), Settings (sources, preferences, future domain toggles).
Identity audit disappears from primary navigation entirely — developer tool only.
Pull-to-refresh and auto-refresh on launch replace the big header card.
Loading messages rotate prominently during brief generation and chat thinking states show short calm pauses.
Inline citations with preview cards and stream links are the beginning of the exploration layer.
2 Build the voice and personality layer.
MalcomeBriefGenerator replaces LocalBriefGenerator as the production brief path using Apple Foundation Models on-device only.
Both signal briefs and watchlist briefs route through MalcomeBriefGenerator so the voice is consistent regardless of signal state.
BriefingInput is enriched with watchlist candidates, domain mix, and source influence highlights so the generator has everything it needs without reaching back into the repository.
A signal formatting step converts structured SignalCandidateRecord and WatchlistCandidate data into labeled text before the model call, using a compact plain-line serialization format rather than JSON or markdown.
Heuristic caps on the structured input control the token budget — cap the number of signals, watchlist items, and characters of evidence summary per item to stay within the 4096-token AFM context ceiling.
The chat layer below the brief in HomeView provides a conversational thread where users ask follow-up questions and Malcome responds in character.
Chat context includes the current brief, top signal candidates with evidence summaries, and watchlist candidates, pre-compressed to fit the context budget.
Conversation history older than the last few exchanges is compressed using a two-stage summarize-then-verify pipeline adapted from Hal's TextSummarizer, applied to unstructured conversation prose only, not to structured signal data.
Chat history resets with each new brief cycle.
If Apple Foundation Models is unavailable on the device, Malcome surfaces a clear message and stops. No silent fallback.
The voice prompt is a collaborative artifact reviewed before it ships.
3 Keep threading predictive source and source-family influence into user-facing reads so Malcome's learned trust remains legible outside the harness without turning the product into an analytics dashboard.
4 Continue controlled expansion across domains and cities, adding only a small number of high-signal sources that fit the production pipeline cleanly and strengthen cross-domain corroboration rather than just source count.
Keep source choice anchored to the source doctrine: upstream tastemakers, scene infrastructure, creator platforms, niche publications, communities, and marketplaces over general commentary.
Next likely lanes: more creator-platform, marketplace, and tastemaker sources that materially diversify the current music/art/fashion-heavy mix without duplicating an existing source family.
Near-term emphasis: broaden beyond editorial-only growth by adding creator-platform, community, or marketplace lanes that can corroborate the new cross-city tastemaker coverage.
Keep creator-platform additions curated: staff picks, featured selections, and trusted platform curation before open public feeds.
Raise corroboration quality inside the broadened network so added sources create cross-family confirmation instead of just more single-lane observations.
Prefer additions that can plausibly cross with existing lanes already in the network, especially film, design, community, and marketplace sources that could confirm names surfacing in music, art, or fashion tastemaker paths.
Use the new in-product doctrine profile as part of source review whenever adding, keeping, or retiring a source.
5 Keep tightening editorial and community subject extraction so Malcome follows reusable cultural entities instead of recurring publication-owned series, roundups, and source-branded programs.
6 Tune source-specific politeness controls so cadence and backoff windows stay respectful without making Malcome feel over-paused.
7 Expand the device smoke harness from runtime verification into a small set of repeatable product-health assertions against a connected iPhone.
8 Tune conversion detection quality so downstream outcomes are strict enough to be meaningful but broad enough to accumulate evidence.
9 Resolve every live unfinished source path explicitly: complete it, disable it, or document its honest failure reason and next step.
10 Surface source-family context more clearly in the harness and review surfaces so future discovery-engine work can audit independence assumptions directly.
11 Design a typed exploration layer so high-confidence entities can link users outward to the source, the work itself, and trusted context destinations without forcing a generic search workflow.
12 Extend the new current-vs-history evidence split into more brief and investigation surfaces so historical repetition never reads like live corroboration.
13 Keep the outbound-link affordance consistent anywhere tapping leaves Malcome, including future exploration surfaces.
14 Validate the new derived event-instance identity on-device after a fresh refresh, then decide whether the next step should be a dedicated event table or whether the derived key is sufficient for cross-source event matching in v1.

15 Add calendar event integration via EventKit so Malcome can offer to add shows, openings, and releases to the user's calendar when an entity has date information. Native Apple framework, no dependencies. The architecture should surface date-bearing observations through the entity detail and chat layers.

## Do not expand source count broadly yet.

Controlled breadth with quality guardrails.

## Definition of progress

Better signals.
Not more data.
