# Malcome

## Purpose

Malcome is a cultural signal detection system.

It identifies early emergence patterns across culture:
music, art, design, fashion, nightlife, film, internet culture, and adjacent domains.

It is NOT:
a concert listing app
a recommendation engine
a popularity tracker
a trend summarizer

It IS:
a cultural radar system.

## Core Product Principles

1. Detect movement, not listings.
2. Detect emergence, not popularity.
3. Detect progression across time.
4. Remain domain-agnostic.
5. Music is only a test domain.
6. Historical signals matter more than snapshots.
7. Cross-source corroboration is stronger than volume.
8. Architecture must scale to multiple cultural domains.

## Non-negotiable product constraints

Malcome must never become domain-locked.

Any change that narrows Malcome to a single domain is a regression.

Signals must rely on:
time
corroboration
progression
source diversity

Not:
raw counts
event listings
scraped volume.

## Product goal

Answer:

What is emerging before it becomes obvious?

Not:

What is already popular?

## Source Doctrine

Malcome should prefer sources that surface culture before mainstream validation.

Highest-value sources usually come from:
creator platforms
scene infrastructure
small or niche publications
tastemakers
communities
marketplaces
tool ecosystems

General commentary is not enough on its own.
Calendar listings are useful but are not sufficient on their own.
Easy ingestion is never a valid reason to keep a source in the core network.
Respectability is not the bar.
Prestige is not the bar.
Being early, selective, and culturally consequential is the bar.

When choosing sources, ask:

Does this source tend to see culturally relevant movement before broad consensus?

Does attention from this source actually mean something inside a live scene or subculture?

Is it acting as a selector, validator, connector, or bridge before consensus forms?

If not, it does not belong in Malcome’s core path.

## Engineering Behavior Rules

Documents override chat instructions.

If chat direction conflicts with documents:
Update documents first before implementation.

ARCHITECTURE.md must be updated before structural changes.

NEXT.md defines work priority order.

Do not implement work not reflected in NEXT.md.

No fake behavior in the live path.

If something is unfinished, it must either:
be out of the live path
or fail honestly with a clear reason and an explicit documented next step.
