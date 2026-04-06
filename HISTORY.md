# Development History

## Phase 1

Initial ingestion pipeline.
Music domain used as test environment.

## Phase 2

Signal scoring added.
Cross-source corroboration introduced.

## Phase 3

Ontology generalized.
Domain typing added.
Entity typing added.
Non-music source added.

## Phase 26

Registry modularized into source packs with pack metadata and pack-level enable/disable controls.
Controlled expansion moved beyond Los Angeles-only thinking with new live sources in art, community radio, and film editorial.
CARLA, KXLU, and Film Comment now ingest through a shared WordPress posts pipeline with archive backfill support.

## Phase 27

The app moved onto a higher-contrast dark presentation layer so the fast-read and investigation surfaces are easier to scan on device.
Shared surfaces now use a darker palette with brighter text while preserving the stronger accent colors on status and source metadata.
Pack headers in Sources were also strengthened so module-level toggles read more clearly as group controls.

## Phase 28

Source packs and source families are now separate first-class concepts.
Pack metadata continues to drive user-facing modular control, while source-family metadata now drives corroboration logic so expansion can stay modular without confusing “same pack” and “same source family.”
Editorial and community lanes now tag recurring series, roundups, and self-branded program formats at parse time, and those patterns are downgraded unless they break out of a single source family.
This kept the new multi-city expansion honest by pushing the watchlist back toward reusable cultural entities such as creators, labels, and collectives instead of publication-owned series titles.

## Phase 29

The project roadmap now explicitly includes a structured exploration layer.
Malcome will eventually help users move from a surfaced entity to the source page, the work itself, and trusted contextual destinations without dropping them into a generic search flow.
This keeps the product aligned with its cultural-radar role while opening a path from “interesting signal” to “show me the thing.”

## Phase 30

Malcome now has an inspectable predictive source-weighting layer.
It aggregates historical outcomes for sources and source families, stores those influence stats alongside pathway stats, and feeds them back into current scoring without turning the engine into a black box.
The production harness now reports learned source-family influence in plain language, and the audit surfaces can expose that same learning inside the app, so the product can say when a source family has historically earned more trust instead of silently baking that learning into a hidden score.

## Phase 31

Learned source trust now flows into the brief layer as well as the audit surfaces.
The watchlist brief can now mention when a source or source family has historically earned more trust, while still keeping that learning in calm product language instead of analytics jargon.
Full signals can also carry source-learning context inside the narrative brief, so Malcome’s fast-reading layer is closer to the intelligence actually driving the engine.

## Phase 32

Malcome now distinguishes current support from stored history in both watchlist and signal reads.
Watch items and signals can surface live mentions and live source-family support separately from stored historical mentions and source diversity, which makes the evidence hierarchy more understandable and prevents historical repetition from sounding like current corroboration.
Evidence cards now also carry a clearer outbound-link affordance so users can tell when tapping will leave Malcome.
Real-device QA also exposed a likely event-calendar counting bug: repeated pulls of the same event instance may still be inflating historical mention counts for some venue/calendar lanes, and that investigation is now explicitly queued.

## Phase 33

The event-calendar inflation bug was traced to two layers: event-like history was being counted from raw stored sightings, and observation identity for many source parsers was using process-local hash values that changed across launches.
Malcome now uses deterministic observation hashes, repository-level duplicate checks that fall back to URL plus published date, and event-instance-aware history counting in the signal engine.
This keeps repeated calendar pulls from quietly becoming new historical mentions while still preserving the useful fact that an event remained visible across refreshes.

## Phase 34

Malcome now carries a shared derived event-instance identity rather than treating event dedupe as a one-off engine trick.
Observation drafts and persisted observations can derive the same event-instance key from entity name, day, location, and normalized URL, and the repository now uses that concept during duplicate checks for event-like rows.
This gives future cross-source event reasoning a cleaner foundation without forcing an immediate dedicated event table into the schema.

## Phase 35

Controlled expansion resumed with two clean cross-city editorial additions that fit Malcome's existing WordPress adapter path.
Public Books now adds a New York intellectual/cultural editorial lane, and ARTnews now adds a New York art-editorial lane that complements Hyperallergic and CARLA instead of leaving art too isolated.
The production harness validated both sources live, increasing the healthy network to 15 of 21 sources without broad source sprawl.

## Phase 36

The project source doctrine was tightened explicitly around upstream cultural signal rather than general commentary.
Malcome now records that creator platforms, tastemakers, niche publications, communities, marketplaces, and scene infrastructure are the preferred source categories, while easy ingestion is never a valid reason to keep a source in the core path.
Public Books was removed from the active source registry because it did not yet clear that stricter standard strongly enough for the live network.
A new [SOURCE_CANDIDATES.md](/Users/markfriedlander/Desktop/Fun/Malcome/SOURCE_CANDIDATES.md) document now captures future source directions and inspiration without turning them into a must-implement list.

## Phase 37

Controlled expansion continued with The Quietus as a London music tastemaker lane.
It fit the existing WordPress-backed adapter cleanly, but unlike weaker commentary candidates it also matched Malcome's source doctrine as a real upstream critical and scene-sensitive publication.
The production harness validated it live, keeping the network disciplined while broadening Malcome's cross-city music surface beyond Los Angeles and New York.

## Phase 17

Signal trustworthiness was tightened so same-family corroboration no longer gets promoted as broad cultural agreement.
The Hyperallergic regression was fixed by moving that source onto its public Ghost content API for both current fetches and archive backfill.
Source-failure copy was softened so the app speaks more like a product and less like a parser log.

## Phase 18

The watchlist was upgraded from a raw latest-observation fallback into a curated pre-signal layer.
It now groups stored observations into stronger candidates, rewards better source tiers and classifications, and penalizes title-like or weak single-source noise.

## Phase 19

Watchlist ranking was tightened again to prefer reusable cultural entities over single-source editorial headline energy.
This shifted first-pass reads toward a more plausible mix of creators, releases, and event-like candidates while keeping the watchlist honest about thin corroboration.

## Phase 20

The watchlist now prefers canonical entity labels and stored entity history over raw observation titles when Malcome has a trustworthy reusable subject.
Single-source editorial concept items now need at least some repetition or history before they can lead the watchlist.
Hyperallergic gained stronger subject extraction so art-editorial observations can resolve to a creator like Joel Meyerowitz instead of turning an entire article headline into the tracked identity.

## Phase 21

Malcome now has a separate real-device smoke harness alongside the production data-engine harness.
Real iPhone build, install, and launch can now be repeated through a single script instead of a manual sequence of commands.
This makes hardware QA part of the project’s intentional validation surface rather than an improvised workflow.

## Phase 22

Source-specific politeness controls are now live.
Each source now carries refresh cadence and failure backoff policy, and immediate re-runs can pause sources instead of repeatedly hitting them as if every source should refresh on the same schedule.
Rate-limited sources such as KCRW now enter an explicit cooldown window, and the UI and harness surface these polite pauses as a distinct state rather than as failures.

## Phase 23

The real-device smoke harness now performs lightweight runtime verification after launch.
It inspects the Malcome app container on the connected iPhone, copies the live SQLite files, and reports core table counts so hardware validation can confirm more than a successful install.
The validation scripts now live explicitly inside the repo’s `Scripts/` directory so the testing workflow stays portable with the project.

## Phase 24

The watchlist brief now reads as an early radar narrative instead of a system disclaimer.
It introduces the leading names, explains why they are on the radar, and tells the user what would upgrade a watch item into a real signal.
This improves the fast human-reading layer without throwing away the deeper evidence trail underneath.

## Phase 25

The watchlist now carries explicit stage and explanation fields instead of asking the view layer to infer them on the fly.
Each watch item can now say why it is on the radar right now and what would upgrade it into a real signal, which makes the fast-reading layer calmer and more legible.
This also keeps the brief, cards, and future audit surfaces aligned around the same product logic instead of drifting into parallel explanations.

## Phase 4

Document-driven development adopted.
Project source-of-truth documents created in repo.

## Phase 5

Engineering behavior rules added to project constitution.
Entity history layer added.
Signal-run persistence added.
Signal movement classification added.
Signal explanations added.
UI and harness updated to expose historical movement.

## Phase 6

Canonical entity identity added.
Alias persistence added.
Source-role attribution added.
Signals moved from raw normalized titles to canonical entity IDs.
Observation records now receive canonical identity links.

## Phase 7

Sequence and progression detection added.
Signals now score ordered source-role pathways.
Time-gap modeling added between source-role stages.
Progression explanations added to signals, briefs, and harness output.

## Phase 8

Daily entity stage snapshots added.
Longer-horizon 7 day, 30 day, and 90 day emergence modeling added.
Signal maturity classification added: early emergence, advancing, peaking, cooling, stalled.
Cooling and stalled detection added on top of progression logic.
Harness, UI, and brief output updated to expose maturity and longer-horizon context.

## Phase 9

Signal lifecycle state added: emerging, advancing, peaked, cooling, failed, disappeared.
Decay modeling added for slow fade, sharp drop, and failed progression patterns.
Previously active signals can now be synthesized as disappeared or failed when they drop out of the current run.
Lifecycle state is now persisted on signal candidates, signal runs, and entity history.
Brief, UI, and harness output updated to expose lifecycle explanations.

## Phase 10

Pathway history tracking added per entity and run.
Pathway outcome aggregation added for advancing, peaked, cooling, failed, and disappeared results.
Pathway statistics now produce predictive scores and comparative summaries.
Current signal scoring now includes learned pathway weighting from historical pathway outcomes.
Briefs, signal detail, and the harness now expose pathway-level predictive context.

## Phase 11

Downstream outcome tiers added: institutional pickup, larger venue tier, major editorial coverage, cross-domain appearance.
Outcome confirmation tracking added per entity.
Conversion state added: pending, converted, stalled before conversion, never converted.
Pathway learning upgraded to incorporate downstream conversion outcomes in predictive weighting.
Briefs, signal detail, and the harness now expose conversion explanations alongside lifecycle and pathway context.

## Phase 12

Historical depth added for Aquarium Drunkard through the production pipeline.
Archive backfill now uses a reliable source-specific archive endpoint instead of a separate importer.
Observation inserts now deduplicate by source and external identity across refreshes and backfills.
Historical observations are tagged explicitly and timeline reasoning now prefers published time when available.
This gives entity histories a real archive-backed first-seen floor instead of only refresh-time depth.

## Phase 13

Historical depth expanded across domains.
Hyperallergic now backfills art editorial history through the same production pipeline with published-date parsing from archive pages.
Bandcamp LA Discover now backfills additional cursor pages through the existing discover API path, giving music history a second archive-backed lane.
Historical tagging, duplicate protection, and published-date timeline logic now work across both editorial archives and discovery APIs.

## Phase 14

Canonical identity hardening added explainable merge confidence and merge summaries to each canonical entity.
Merge rules are now stricter against short names, collision-prone names, title-like aliases, cross-domain reuse, and unsupported long-gap historical jumps.
Canonical identity now prefers false splits over false merges when archive depth makes a weak merge risky.
This makes deeper history safer for timelines, progression logic, and future sequence learning.

## Phase 15

The product now exposes an identity review surface.
Low-confidence canonical entities, merge summaries, alias sets, and source-role evidence can now be inspected directly in the app.
Signal detail now includes an identity audit card so suggestions can explain how trustworthy their canonical entity is.
The production CLI harness now prints an identity watchlist so risky merges are visible during non-UI validation.

## Phase 16

Real-device QA exposed a trust problem where repeated support inside one source family could still rise into a misleading signal.
Signal scoring now distinguishes independent source families from repeated support within one family, and same-family-only loops remain watchlist material unless they progress into another layer.
The reading experience was also rebalanced into a calmer quick-read layer and a deeper investigation layer, so narrative and evidence now stage more naturally for human use.

## Phase 38

A shared RSS-backed tastemaker lane was added to the production pipeline and validated live with Bandcamp Daily and Crack Magazine.
Controlled expansion then continued with BrooklynVegan and Artforum, giving Malcome stronger New York music and art tastemaker coverage without introducing a new parser family.
This keeps breadth disciplined: culturally upstream sources first, adapter fit second, and no fake source behavior in the live path.

## Phase 39

Controlled expansion continued with i-D and Hypebeast on the shared RSS lane.
This widened Malcome's live network beyond music, film, and art into fashion, street culture, and youth-culture editorial without introducing a new parser family.
The live pipeline validated both sources, which means Malcome's cross-city tastemaker surface now spans more domains as well as more geography.

## Phase 40

Malcome gained a dedicated Creator Platforms pack instead of forcing platform signals into editorial-only groupings.
Vimeo Staff Picks was added as a curated creator-platform lane and validated live, while the shared RSS parser was improved to understand cleaner feed-provided titles and creator credits when those fields are available.
This keeps platform expansion selective and taste-aware rather than treating public feeds as automatically worthy of the live network.

## Phase 41

The user-facing admission bar was tightened so single-source-family detections no longer appear in the watchlist or brief as if they were real radar.
Malcome still stores and learns from those thin sightings internally, but the product now waits for independent corroboration before surfacing a candidate to the user.
When the network is still thin, the brief now says so directly instead of filling the radar with single-lane curiosities.

## Phase 42

Controlled expansion resumed with two doctrine-fitting lanes: Short of the Week as a curated creator-film source and Creative Review as a design tastemaker source.
Both sources validated through the live production pipeline and the real-device smoke harness, which means Malcome's cross-city network broadened without inventing a new parser family.
The expansion rule is now explicit in the project record: new sources must be selected for corroboration value, not just coverage value.

## Phase 43

The source doctrine was tightened and made more explicit.
A new SOURCE_DOCTRINE.md now captures the shorter, harder-to-misread rule: Malcome should prefer early consequential filters over respectable coverage.
The product, requirements, decisions, and candidate docs were updated so future source expansion is less likely to drift toward prestige, convenience, or generic commentary.

## Phase 44

The source doctrine is now visible inside the product and harness instead of living only in markdown.
Each source can now explain why it is early, why it is selective, and what corroboration role it is supposed to play.
That gives Malcome a real source-audit layer, which makes future source expansion easier to inspect and harder to drift.
