# StellarPop v0.3.1

Release date: 2026-03-29

## Summary

`v0.3.1` is a stabilization and usability release focused on benchmark operations, documentation clarity, and project workflow polish after the `v0.3.0` science milestone.

## Highlights

- Added benchmark-run UX improvements:
  - selectable benchmark targets per run
  - fast vs full benchmark modes
  - mode/runtime visibility on benchmark index/show pages
  - clearer benchmark naming (`bm_...`) and updated benchmark page labels
- Improved benchmark progress visibility:
  - live elapsed timer banner
  - dedicated progress panel with completed/total, current step, and ETA
- Added/updated benchmark reference set and metadata:
  - includes `NGC3379`, `M101`, `M87`, `NGC4459`
  - expected ranges, notes, and references displayed in UI
- Added navbar Sidekiq status indicator behavior integration with benchmark workflow monitoring.
- Synced project docs to current behavior (`README.md`, `paper.md`, `TODO.md`).

## Documentation and Workflow

- `TODO.md` migrated from checkbox format to color-priority status markers:
  - `🟩 Done`
  - `🟨 Pending`
  - `🟥 Critical Pending`
  - `🟦 Critical: SDSS Offline`
- Reordered TODO sections by priority within each section.
- Clarified current SDSS-dependent science blockers in TODO.

## Compatibility

- No breaking database/model rename in this release (internal `CalibrationRun` naming remains for compatibility).
- Existing synthesis/grid workflows remain unchanged and compatible with prior data.

## Known External Blockers

Some science-validation tasks remain blocked by SDSS service availability/provenance checks (tracked as `🟦` in `TODO.md`).

## Tag

- Git tag: `v0.3.1`
