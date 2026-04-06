# Technical Requirements

Platform:
iOS first

Storage:
SQLite required

Models:
Apple Foundation Models when applicable

Architecture:
Domain-agnostic entities
Modular ingestion pipeline
Persistent observation history

Pipeline must remain:

Registry
Fetch
Parse
Persist
Score
Brief

No mock pipelines.

Production path only.

Data rules:

History must be preserved.
Signals must derive from stored data.
No signal from single scrape.

Engineering rules:

No fake implementations.
No disguised placeholders in the live path.
No dead sources in production set.
Broken parsers must be fixed, explicitly disabled, or fail honestly with the next step documented.

Source selection must not optimize for:
ease of parsing
institutional prestige
broad popularity
generic cultural coverage
raw listing volume
