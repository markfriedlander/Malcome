# Parked UI Todos

These are known issues that are documented but not yet scheduled for a build. They will be addressed in a future session.

## Loading Animation

- Opacity pulse too subtle. Current range 0.5–1.0 is not visible enough in practice. Needs a more dramatic shimmer closer to the Claude UI style.
- Pull-to-refresh minimum duration still too short. Showing ~2 seconds, target is ~15 seconds minimum regardless of refresh speed. The timer mechanism is not holding the loading state long enough.

## Citations

- Inline citation markers [1][2] not rendering inline in brief text. They appear only as bottom chips, not superscript in the prose. The CitedBriefText inline rendering is not firing.
- Citation chips at bottom are not separately numbered. All showing the same index despite the source-name dedup fix. Needs further debugging of SourceTracker.cite() inout chain through DraftComposer.

## Entity Cleanup

- "Reissue of the Week: Fall Heads Roll by The Fall" still appearing as a signal entity despite RETAG. Will self-heal on next RELINK but consider scheduling RELINK automatically after RETAG so they run together.
- "Earl Sweatshirt, MIKE & SURF GANG, POMPEII // UTILITY" credit string entity name still appearing. Will self-heal on RENORMALIZE but same scheduled cleanup logic would help.

## Settings Refresh

- After "Refresh now" in Settings, takes a few seconds before navigating to Today. Should feel more immediate or show a clear loading state during the transition.
