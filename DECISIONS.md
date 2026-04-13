# Design Decisions

## Multi-domain architecture

Decision:
Malcome must remain domain-agnostic.

Reason:
Product goal is cultural detection, not music detection.

## Tier A sources retained despite difficulty

Decision:
Important cultural sources remain targets even if parser work required.

Reason:
Source importance determined by signal value, not scrape difficulty.

## Production pipeline harness

Decision:
CLI harness must run production path.

Reason:
Prevent fake validation.

## Modular source packs

Decision:
The source registry should be composed from modular packs with stable pack metadata rather than treated as one flat list.

Reason:
Users need group-level control, and the future discovery engine needs a clean way to swap, promote, or retire packs without rewriting the scoring system.

## Shared WordPress ingestion path

Decision:
WordPress-backed editorial and community sources should enter Malcome through one reusable posts API adapter rather than through one-off source scrapers.

Reason:
That keeps parsing source-specific only where it must be source-specific, while making controlled expansion across cities and domains much more scalable.

## Shared RSS ingestion path

Decision:
Tastemaker and magazine feeds that expose stable RSS should enter Malcome through one reusable RSS adapter rather than through one-off feed parsers.

Reason:
This keeps controlled expansion fast and disciplined while preserving the same production-path fetch, parse, persist, and score flow as the rest of Malcome.

## Separate engine validation from device smoke validation

Decision:
Malcome should keep a production data-engine harness and a separate real-device smoke harness instead of collapsing both concerns into one script.

Reason:
The pipeline needs deterministic validation of fetch, parse, persist, score, and brief behavior, while device QA needs repeatable build, install, and launch checks on actual hardware. Keeping them separate preserves clarity without creating fake paths.

## Runtime verification in the device smoke harness

Decision:
The device smoke harness should verify live runtime state by inspecting the app data container and summarizing the on-device database after launch.

Reason:
“The app launched” is not enough. Malcome needs a repeatable hardware check that the app actually created and maintained runtime state on the phone.

## Source-specific politeness over uniform refreshing

Decision:
Malcome should store and enforce per-source politeness policy such as refresh cadence and failure backoff instead of treating every source as refreshable on every pass.

Reason:
Different sources tolerate different request patterns. Respecting those differences improves reliability, reduces avoidable rate limits, and keeps Malcome from behaving like a bad citizen of the public web.

## Prefer stable public content endpoints

Decision:
When a source exposes a stable public content or archive endpoint, Malcome should prefer that over brittle homepage-card scraping.

Reason:
This improves historical depth and parser reliability without creating a parallel fake pipeline.

## Curated watchlist before full signal graduation

Decision:
When corroboration is still too thin for promoted signals, Malcome should surface a curated watchlist built from stored observations instead of falling back to raw latest items.

Reason:
This preserves honest uncertainty while still giving the user a useful first-pass read.

## Prefer reusable entities over single-source headline energy

Decision:
Watchlist ranking should favor reusable cultural entities such as creators, events, collectives, and venues over single-source editorial concept headlines.

Reason:
Malcome is trying to detect cultural movement, not simply replay the strongest current article titles.

## Prefer canonical watchlist subjects over raw evidence titles

Decision:
When Malcome already has a trustworthy reusable subject for an observation, the watchlist should present that canonical subject instead of the raw article or release title.

Reason:
The watchlist should read like a cultural radar surface, not a feed reader. Raw evidence titles are still valuable, but they belong in supporting detail rather than as the primary unit of attention.

## Modular source packs over a monolithic registry

Decision:
Malcome should organize sources into plugin-like source packs with stable module metadata instead of treating the registry as one undifferentiated flat list.

Reason:
Users need domain and pack-level control, and the future source-discovery engine will need a clean way to add, compare, swap, and retire source bundles without destabilizing the core scoring and persistence architecture.

## Watchlist brief as radar narrative

Decision:
When full signals are still thin, the default brief should explain the watchlist as an early radar read: who is showing up, why that matters, and what would upgrade those names into real signals.

Reason:
Malcome’s fast-reading layer should feel informative and culturally literate even before corroboration is strong enough for promotion into formal signals.

## Watchlist explanations belong in the model, not just the view

Decision:
Watchlist candidates should carry an explicit stage plus short explanation fields such as why they are on the radar now and what would upgrade them into a real signal.

Reason:
The fast-reading layer should read product logic directly instead of rebuilding ad hoc explanations inside SwiftUI views. That keeps the watchlist calmer, more consistent, and easier to evolve across app, brief, and harness surfaces.

## Independent corroboration over source-family repetition

Decision:
Signals should prefer independent source families over repeated support from closely related source variants.

Reason:
Repeated appearances inside one source family can be useful watchlist evidence, but they should not masquerade as broader cultural agreement.

## Keep source packs separate from source families

Decision:
Malcome should treat source packs and source families as different concepts.

Reason:
Packs exist for user control and future discovery-engine swapping, while source families exist for corroboration logic. Conflating them would make the UX and the scoring model fight each other as the network grows.

## Downgrade recurring self-branded editorial formats

Decision:
Recurring editorial programs, roundups, and self-branded publication formats should be tagged at parse time and downgraded unless they gain stronger corroboration.

Reason:
Malcome should track reusable cultural subjects, not mistake a publication's own ongoing series format for an emergent entity just because archive depth makes it repeat.

## Structured exploration over generic search

Decision:
Malcome should eventually resolve high-confidence entities into typed outbound destinations such as source pages, official pages, listening/viewing destinations, and trusted cultural reference links instead of sending users to a generic web search.

Reason:
The product should help users move from “this seems important” to “show me the thing” without turning into an opaque recommendation engine or a loose search wrapper.

## Learned trust belongs in the brief, not only the audit layer

Decision:
Malcome should surface learned source and source-family trust in the narrative brief layer when that learning is strong enough to matter, but it should do so in calm product language rather than analytics jargon.

Reason:
If predictive weighting only appears in harness output or deep review screens, the fast-reading layer stays less trustworthy than the engine beneath it. The brief should explain when a lane has historically earned more trust, while still keeping the learning inspectable and non-black-box.

## Separate current support from stored history

Decision:
Malcome should explicitly distinguish current support from stored historical evidence anywhere it explains a watch item or signal.

Reason:
If current-pass support and stored-history repetition blur together, the product sounds more confident than the evidence actually is. Clear separation keeps the engine interpretable and prevents historical repetition from masquerading as live corroboration.

## User-facing radar requires corroboration

Decision:
Single-source or single-source-family detections may be stored and learned from internally, but they should not appear in the user-facing radar surfaces until Malcome sees independent corroboration.

Reason:
One source can be an interesting hint, but not a trustworthy cultural signal. Malcome should observe more than it shows, so the user-facing product stays aligned with corroboration rather than curiosity alone.

## Expansion should chase corroboration, not just coverage

Decision:
When Malcome adds sources, those additions should be judged mainly by whether they can create meaningful independent corroboration with the existing network, not simply by whether they broaden domain count or source count.

Reason:
Coverage alone produces a larger crawler. Malcome becomes a stronger cultural radar only when new lanes can cross with existing tastemakers, creator platforms, communities, and scene infrastructure in ways that make signals more trustworthy.

## Early consequential filters over respectable coverage

Decision:
Malcome should prioritize early consequential filters over respectable or prestigious cultural coverage.

Reason:
The best cultural sensors are often fringe, niche, local, or subcultural before the wider culture recognizes their importance. A source belongs in Malcome because it is good at being early and meaningful, not because it looks reputable from a distance.

## Source doctrine should be visible inside the product

Decision:
Malcome should surface a structured source-doctrine explanation in the app and harness, not just in markdown docs.

Reason:
If the source philosophy only lives in documents, future source selection can still drift. The product should make source rationale inspectable in the same places where users and developers review source health.

## Stable observation identity over process-local hashes

Decision:
Observation identity must be deterministic across launches, and event-like historical counting must collapse repeated sightings of the same event instance.

Reason:
If observation keys change from run to run, the same calendar item can be reinserted and then look like multiple historical mentions. Stable IDs plus event-instance-aware counting preserve persistence without inflating corroboration.

## Derive event-instance identity before adding a dedicated event model

Decision:
Malcome should derive an event-instance key from event name, day, location, and normalized URL now, instead of waiting for a full standalone event table.

Reason:
This gives storage checks, timeline logic, and future cross-source event matching a shared event concept immediately, without blocking on a larger schema expansion.

## Controlled expansion should prefer adapter-fit sources

Decision:
When Malcome expands across domains and cities, it should prefer culturally strong sources that fit existing stable adapters before taking on new parser families.

Reason:
This keeps expansion additive instead of destabilizing. Public cultural value still leads source choice, but using proven adapters where possible lets Malcome broaden its surface area without turning every expansion step into parser debt.

## Controlled expansion should broaden domains, not only cities

Decision:
When Malcome expands, each pass should aim to widen the cultural radar itself, not just add more sources inside one already-dominant lane.

Reason:
Geographic breadth matters, but cross-domain breadth matters just as much. A network that only gets denser inside music editorial will still underperform as a cultural radar even if it covers more cities.

## Curated creator platforms beat open firehoses

Decision:
When Malcome expands into creator-platform territory, it should prefer clearly curated lanes such as staff picks, featured selections, or trusted platform curation over open public firehoses.

Reason:
Public access alone is not enough. Malcome needs platform signals that already carry taste, selection pressure, or scene-aware filtering, otherwise the network turns into a much noisier crawler without becoming a better cultural radar.

## Source doctrine favors upstream tastemakers over general commentary

Decision:
Malcome's core source network should prioritize places where creators, scenes, and ideas appear before mainstream validation: creator platforms, tastemakers, niche publications, communities, marketplaces, and scene infrastructure.

Reason:
Malcome is a cultural radar system, not a general commentary reader. Sources must earn their place by predictive cultural value, not by editorial polish, broad prestige, or ingestion convenience.

## Document-driven development

Decision:
Repository documents are the operational source of truth for product, requirements, architecture, decisions, history, and next work.

Reason:
Prevent drift, reduce ambiguity, and make project context durable across sessions and engineers.

## Historical signal intelligence

Decision:
Malcome persists entity history and signal runs as first-class product data, rather than deriving emergence only from current overlap.

Reason:
Emergence detection requires durable history, movement tracking, and explainable change over time.

## Signal movement taxonomy

Decision:
Signals are classified as new, rising, stable, or declining based on persisted prior runs.

Reason:
Users need directional intelligence, not just ranked overlap snapshots.

## Rebuild history from stored observations

Decision:
Entity history is rebuilt from persisted observations on each analysis pass instead of maintained as a fragile incremental counter.

Reason:
Historical truth should come from stored evidence, and rebuilds are safer than drift-prone partial updates at this stage.

## Canonical identity over raw titles

Decision:
Signals and history should resolve through canonical entity identities with alias support, instead of treating raw normalized titles as the final identity layer.

Reason:
True emergence detection depends on trustworthy identity, source-role attribution, and later sequence analysis across inconsistent source naming.

## Conservative merge policy

Decision:
Canonical identity matching should prefer conservative merges based on exact aliases first and relaxed aliases second, with domain and entity-type compatibility checks.

Reason:
For this product, false merges are more damaging than temporary false splits because they corrupt historical signal progression.

## Sequence detection from source roles

Decision:
Sequence and progression intelligence should be derived from canonical entity source-role history, not from source counts alone.

Reason:
Emergence is better understood as movement through cultural systems than as repeated overlap in the same layer.

## Sequence-first progression scoring

Decision:
Signals receive an explicit progression score that rewards meaningful ordered pathways and interpretable time gaps between source roles.

Reason:
Cultural emergence is more credible when an entity moves through discovery, editorial, venue, community, or institutional layers in a recognizable sequence.

## Daily stage snapshots for longer-horizon emergence

Decision:
Malcome persists a per-entity daily stage snapshot with stage, source count, and daily signal score.

Reason:
Sustained emergence cannot be inferred reliably from one run or one progression chain; it needs daily historical structure across longer windows.

## Maturity classification over short-run momentum

Decision:
Signals receive a maturity classification of early emergence, advancing, peaking, cooling, or stalled based on 7 day, 30 day, and 90 day history.

Reason:
Malcome should distinguish short-run motion from sustained cultural emergence, plateauing, or fadeout.

## Conservative disappearance modeling

Decision:
The first longer-horizon layer models stalled and cooling states from persisted stage history, but does not yet declare fully disappeared entities unless the evidence is durable enough.

Reason:
False disappearance calls would make the product feel brittle; it is safer to add confident cooling and stalled detection before full disappearance reporting.

## Lifecycle outcomes over only active signals

Decision:
Malcome should synthesize lifecycle outcomes for entities that were previously signals even when they no longer appear in the current scrape.

Reason:
A cultural radar system needs to understand what vanished or failed, not just what is currently active.

## Decay and disappearance from run history

Decision:
Decay, failed progression, and disappearance should be inferred from persisted signal-run history plus current absence, not from current observations alone.

Reason:
Lifecycle intelligence depends on comparing what used to matter against what is missing now.

## Lifecycle state as first-class signal metadata

Decision:
Every scored entity should carry a lifecycle state of emerging, advancing, peaked, cooling, failed, or disappeared.

Reason:
Malcome needs to explain where an entity sits in its broader trajectory, not just whether it moved up or down this run.

## Learned pathway weighting

Decision:
Progression pathways should be stored historically and aggregated into pathway statistics that feed back into current scoring.

Reason:
Malcome should begin learning which cultural routes tend to convert into stronger outcomes instead of relying only on fixed hand-authored progression bonuses.

## Conversion over internal momentum alone

Decision:
Pathway learning should be upgraded to value downstream conversion evidence, not just Malcome’s internal lifecycle labels.

Reason:
The product should learn which early signals actually turn into broader cultural relevance, not merely which ones looked lively inside the early-signal network.

## Predictive source weighting must stay inspectable

Decision:
Malcome should learn source and source-family influence from stored historical outcomes, but those learned weights must remain inspectable and explainable in plain language.

Reason:
Some sources and source combinations will prove more predictive than others, but Malcome should surface that learning as evidence-backed reasoning rather than hide it inside a black-box score.

## Historical backfill through the production path

Decision:
Historical depth should be added by backfilling approved archive-friendly sources through the same production fetch, parse, persist, and score pipeline instead of a sidecar importer.

Reason:
Backfilled evidence should strengthen the real product state, not create a parallel truth that drifts from the live app and harness.

## Published time over import time for archival evidence

Decision:
When historical observations provide a trustworthy published date, Malcome should use that date as the timeline date for historical reasoning.

Reason:
Archive imports should deepen entity history, not masquerade as new emergence on the day the archive page was fetched.

## Cross-domain historical depth before source breadth

Decision:
Historical backfill should be expanded across at least one non-music source and one additional music source before broadening the source graph further.

Reason:
Malcome needs deeper multi-domain evidence before it needs more endpoints, otherwise emergence intelligence stays shallow and domain-biased.

## Identity hardening should favor false splits

Decision:
Canonical identity matching now applies stricter rejection rules for short names, common names, title-like aliases, cross-domain reuse, and unsupported long-gap historical jumps, and records the weakest accepted merge confidence with an explainable summary.

Reason:
Deep archive history is only valuable if it does not quietly rewrite entity timelines through weak alias matches. For Malcome, a false split is safer than a false merge because it preserves historical truth and progression integrity.

## No fake behavior in the live path

Decision:
Unfinished work must either stay out of the live path or fail honestly with a clear reason and a documented next step.

Reason:
Malcome should never pretend a capability exists when it does not. Honest failure is safer than ambiguous product behavior.

## Identity ambiguity must be reviewable

Decision:
Canonical merge confidence, merge summaries, aliases, and source-role evidence should be surfaced in the product and CLI harness rather than left hidden inside the scoring engine.

Reason:
Malcome will not be trustworthy unless a human can audit why a signal resolved to a given identity and where ambiguity remains.

## Multi-entity extraction from roundup articles

Decision:
When an article is tagged as a roundup (songs of the week, festival coverage, best-of lists), Malcome should extract each mentioned cultural entity as a separate observation rather than treating the entire article as a single entity. Use AFM at parse time to extract the list of names, entity types, and brief per-entity context from the article title and excerpt.

Reason:
A BrooklynVegan Coachella roundup mentioning Turnstile, The xx, Sabrina Carpenter, Lykke Li, Ethel Cain, and DEVO currently produces zero usable entities. Each of those artists is a legitimate observation that could corroborate with mentions from other sources. Multi-entity extraction is the single highest-impact change for signal density without adding sources or lowering thresholds. Each extracted entity becomes a separate ObservationDraft with the article URL, source, and a per-entity excerpt.

## Cold start seed database

Decision:
Malcome ships a pre-populated seed database (malcome_seed.sqlite) bundled as an app resource. On first launch, if no database exists, the seed is copied to the documents directory. A first-launch backfill then brings the data current.

Seed policy:
Deep start date is the earliest observation in the seed (currently 1997, from historical backfill).
Seed cutoff date is stored as metadata. First-launch backfill covers from the cutoff to the current moment.
Rebuild cadence is quarterly — regenerate the seed from the development database, scrub, and ship with the next app update.
Privacy: observations about public cultural entities from public sources only. No user data, no personal information, no chat history, no briefs.

Scrubbed tables (always empty in the seed): chat_messages, briefs.
Preserved tables: observations, sources, canonical entities, entity history, signal runs, pathway stats, source influence stats, snapshots.

Current seed size: 21MB with 2647 observations across 31 sources. Under the 50MB threshold for direct bundling without Git LFS.

Reason:
A fresh install with an empty database is nearly useless for weeks. The corroboration threshold requires historical depth that takes time to accumulate organically. The seed database provides months of pre-processed observations and entity history. The first-launch backfill covers the gap between the seed database snapshot and the current moment. Together they ensure every user gets a useful Malcome from first launch.

## Observation windows: 14/60/90 days, not 3/10

Decision:
Replace the hardcoded 3-day current window and 10-day prior window with windows that reflect real user behavior: 14-day current window, 60-day prior window, 90-day pattern window.

Reason:
Malcome is for people who do not have time to check an app every three days. That is the entire premise. A user might open Malcome once a week or once every two weeks. A 3-day current window means most observations are already historical by the time the user sees them. A 14-day current window keeps two weeks of cross-family corroboration as active intelligence, not stale data.

Current window (14 days): anything with cross-family corroboration in the past two weeks is active intelligence. These lead the brief.
Prior window (60 days): used for growth scoring, comparing current period to prior period.
Pattern window (90 days): used for progression scoring, horizon intelligence, and surfacing entities that have been building slowly.

## Excerpt quality filtering for brief context

Decision:
Distilled excerpts that contain only Bandcamp structural metadata (track titles with location, album names with city) should be filtered from brief context. For entities with observations from multiple sources, editorial source excerpts should be preferred over discovery/platform source excerpts.

Reason:
"Rabbot Ho Los Angeles, California" is Bandcamp metadata, not editorial context. When an entity has observations from both Bandcamp (discovery) and The Quietus (editorial), the editorial excerpt is almost always more useful for the brief because it describes why the entity matters, not just what it is called.

## Distilled excerpt prompt must require current relevance

Decision:
The AFM distillation prompt must explicitly require that the extracted sentence be about the entity being tracked and describe something current or recent. Historical quotes about other entities or publications should be rejected.

Reason:
A 1982 Melody Maker quote about Scritti Politti is vivid but completely irrelevant context for a 2026 signal about The Fall. The distillation prompt should constrain extraction to factually relevant, entity-specific, temporally appropriate content.

## DraftComposer template variation

Decision:
DraftComposer must not repeat the same template phrase within a single brief. Fallback phrases like "Consistency at this stage usually means something real underneath" must have at least 3-4 variants, and a used-phrase tracker must prevent repetition within one brief generation.

Reason:
Repeated phrases break the illusion that Malcome is a person speaking. A friend would not say the same sentence twice in the same conversation.

## Citation deduplication across the full brief

Decision:
Citations should be deduplicated by source URL across the entire brief. Each unique source URL gets one citation number regardless of how many signals reference it. If Bandcamp Daily supports both Thundercat and Earl Sweatshirt, both references point to the same citation chip.

Reason:
[2] Bandcamp Daily and [4] Bandcamp Daily appearing in the same brief is confusing. A unified citation index makes the brief cleaner and the citation chips more useful.

## Context-aware empty state messages

Decision:
The empty state brief should use three levels of context-aware language based on data state: Level 1 for genuinely sparse data, Level 2 for data that exists but hasn't crossed thresholds, Level 3 for near-miss entities close to the signal threshold.

Reason:
A static "I have not landed enough corroboration" message gives the user no sense of progress. Context-aware messages tell them whether Malcome is just getting started, watching things that haven't crossed the line, or sitting on names that are almost ready. This builds trust and keeps users engaged during the cold start period.

## Two-tier signal architecture

Decision:
Signals carry an explicit tier: current (cross-family corroboration in the 14-day window) or historical (cross-family corroboration in the 90-day pattern window but not the 14-day window). DraftComposer uses different language for each tier.

Reason:
Tier 1 signals are active intelligence: "This is what has been moving." Tier 2 signals are pattern intelligence: "This has been building. I have been sitting on it." Both are valuable to the user but they carry different confidence levels and should be framed differently. A user who opens Malcome after two weeks gets both what is happening now and what has been developing in the background.

## Domain-specific context fallbacks (planned)

Decision:
When Wikipedia returns no entry for a cultural entity, Malcome should fall back to domain-specific APIs: MusicBrainz for music artists, Artsy for visual artists, TMDB for film entities. These are planned but not yet built. Wikipedia is the primary context source.

Reason:
Emerging cultural entities often lack Wikipedia entries — that is part of what makes them emerging. Domain-specific APIs have broader coverage of lesser-known creators. MusicBrainz, Artsy, and TMDB all have public APIs with no authentication required for basic lookups. The architecture leaves room for these fallbacks without requiring a rewrite.

## Signals require independent source family corroboration for the brief

Decision:
Signals fetched for the brief must have currentSourceFamilyCount >= 2. Single-family signals remain in the database for historical tracking and pathway learning but do not appear in the user-facing brief or lead the product.

Reason:
The signal engine allows single-family signals to graduate via progression stages or snapshot count, which is useful for internal intelligence. But the product-facing brief should only surface entities with genuinely independent corroboration — the same standard the watchlist applies. Flying Lotus appeared across Bandcamp Daily, Bandcamp LA Discover, and Bandcamp LA Tag, but all three are in the same Bandcamp source family. This is valuable internal evidence but not independent cultural agreement. The brief filter ensures users only see signals where different parts of the scene are independently arriving at the same conclusion.

## Editorial source entity extraction: headline over author

Decision:
For sources classified as editorial, the RSS dc:creator / author field must not be used as the primary entity candidate. The subject of an editorial article lives in the headline, not the byline. The dc:creator preference path in the RSS parser is restricted to non-editorial sources (discovery, community, venue, creator platforms) where the author IS the cultural entity.

Reason:
Editor and journalist names in the dc:creator field are indistinguishable from artist names in the data structure. "Mika Lee" (an Artforum editor) looks identical to "Mika Lee" (an artist) at the parser level. When the RSS parser preferred dc:creator for all sources, editorial bylines became canonical entities and led the brief. The headline is the reliable signal for what an editorial article is about. The author field is publication metadata.

## AFM-assisted subject classification at parse time (planned)

Decision:
Malcome should eventually use a small AFM call at parse time to classify the primary subject and subject type from an article headline and first paragraph. This handles cases where even the headline does not contain a trackable cultural entity — AFM would correctly classify an archaeological discovery article as geography rather than a creator or work worth tracking.

Reason:
Headline inference patterns cover many editorial title formats but not all. Some articles have subjects that require understanding the content to classify correctly. A small AFM classification call (entity name, entity type, confidence) at ingest time would dramatically improve entity extraction quality for edge cases. This is the medium-term fix. The short-term fix is the editorial source entity priority change above.

## Staff bylines must not become canonical entities

Decision:
When a source's dc:creator or author field contains the source publication name or a staff-credit pattern (e.g. "BrooklynVegan Staff", "Pitchfork Staff", "[Source] Editorial"), that value must be rejected as a canonical entity name. The parser should fall back to editorial entity inference from the title instead.

Reason:
A staff byline is publication metadata, not a cultural entity. When "BrooklynVegan Staff" becomes a canonical entity and leads the brief, the product sounds broken. The dc:creator preference path in the RSS parser needs a source-name byline filter before accepting a value as an entity.

## Festival roundup and headliner content

Decision:
Malcome should not blanket-filter festival content. Undercard and smaller-stage acts at major festivals are legitimate early signal territory. The filter should target mainstream headliner roundups specifically — articles that lead with already-obvious names and treat them as discoveries.

Reason:
An article about emerging acts at Coachella is high-value cultural radar material. A generic "here's everything streaming from weekend one" piece that leads with DEVO is not — it is a coverage roundup, not an emergence signal. The roundup tag already fires for these articles; the fix is to downgrade roundup-tagged entities from the signal path unless they escape into independent corroboration, which is how the existing roundup downgrade logic works. The doctrine filter should preserve the distinction between coverage roundups and genuine scene-level festival observations.

## Re-normalization of stored observation entity names

Decision:
Malcome should support a RENORMALIZE_OBSERVATIONS command that re-applies current parser normalization logic to all stored observations, then automatically resets the identity graph. This is a two-step atomic operation: update normalizedEntityName on every observation where the recomputed value differs, then clear and rebuild the identity resolution layer.

Reason:
When parser improvements change how entity names are extracted, existing stored observations keep their old normalizedEntityName from the original parse. Waiting for organic data replacement is too slow for a dev workflow. Re-normalization lets parser fixes take effect immediately on the entire observation history, producing cleaner canonical entities on the next identity resolution pass. The credit-string detection heuristic identifies Bandcamp-style multi-artist credit strings and falls back to editorial entity inference rather than treating the full credit string as a single entity.

## Bandcamp Daily RSS: separate artist credit from release title

Decision:
When the Bandcamp Daily RSS feed provides titles in "Artist, Artist, 'Release Title'" format, the RSS parser should detect the Bandcamp Daily source and extract the leading artist name as the entity identity, not the full credit-plus-title string.

Reason:
The RSS feed title is a full credit string (e.g. "Earl Sweatshirt, MIKE & SURF GANG, 'POMPEII // UTILITY'"). When this enters entity resolution as a single canonical entity, the brief reads "Earl Sweatshirt, MIKE & SURF GANG, 'POMPEII // UTILITY' is the one right now" — which sounds like a system log, not a cultural radar. The entity should resolve to "Earl Sweatshirt" (the lead artist) with the full title preserved as the observation title. The RSS item's dc:creator field often carries the artist name separately and should be preferred for entity resolution when available.

## Targeted identity graph reset

Decision:
Malcome should support a surgical reset of the identity resolution layer that deletes canonical entities, aliases, source roles, entity history, and stage snapshots while preserving observations, signal runs, pathway history, source influence stats, and brief history. After the reset, the signal engine re-resolves canonical entities from existing observations on the next refresh.

Reason:
When parser fixes change how entity names are extracted (e.g. the Bandcamp Daily credit-string fix), existing canonical entities keep their old names because the identity graph persists across refreshes. A targeted reset forces re-resolution against current parser behavior without losing observation history. This is a dev tool first but is robust enough for production use if the identity graph ever becomes badly corrupted.

## Article body ingestion for source context

Decision:
Malcome should eventually store article body text alongside observation metadata so AFM can read actual source content before writing briefs and chat responses. At parse time, fetch and store 500 to 800 words of article body text in a bodyExcerpt field on ObservationRecord. At brief generation time, run through the summarizer for a verified 2 to 3 sentence context summary. Store raw, summarize at generation time.

Reason:
Currently the pipeline ingests structured metadata — title, author, tags, excerpt. It knows The Quietus wrote about an artist but not what they said. If the parser also fetched and stored article body text, AFM could read the actual source content and pull culturally relevant context: what kind of artist this is, what makes this release interesting, why the publication thought it mattered. Wikipedia gives the who. The source article gives the why right now. Together they give Malcome something real to say beyond the corroboration pattern.

The distilledExcerpt field is the first step toward this architecture. It uses the same pattern — small AFM call at ingest time, entity-specific extraction, stored for downstream use — at a smaller scope. When article body ingestion is built, it follows the same pipeline: store raw body text, use AFM at generation time for verified contextual summaries.
