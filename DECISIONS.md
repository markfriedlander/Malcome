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
