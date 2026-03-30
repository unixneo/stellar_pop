# StellarPop Development Workflow

## Roles
- Claude (Anthropic): Engineer and scientist. Designs architecture, directs science decisions, generates Codex prompts, validates results, reviews physics correctness.
- Codex (OpenAI CLI): Coder. Implements all code changes from Claude-generated prompts. Never makes science or architecture decisions independently.

## Development Process
1. Claude identifies the next task from `TODO.md` or from scientific analysis of results.
2. Claude generates a precise Codex prompt specifying exactly what to implement, what to leave unchanged, and what tests must pass.
3. Codex implements the change and reports what was done.
4. Claude validates the result in the Rails console or browser.
5. Claude updates `README.md`, `TODO.md`, and `paper.md` before committing.
6. Git commit with descriptive message following the step-N convention.
7. Git push to GitHub (Zenodo auto-deposits on tagged releases).

## Commit Convention
- Step commits: `step N: description of scientific or technical change`
- Doc commits: `docs: description`
- Fix commits: `fix: description`
- DB commits: `db: description`
- Tagged releases: `vX.Y.Z` for Zenodo deposits

## Documentation Rule
_ Always update `README.md`, `TODO.md`, and `paper.md` before committing science or pipeline changes. Never commit science changes without updating documentation first.
_ Always keep TODO order exactly: 🟥 → 🟦 → 🟨 → ⬜ → 🟩 in every section, every edit.

## Science Validation Rule
Always validate physics results in the Rails console before committing. Never trust Codex smoke tests alone for science correctness. Post console output to Claude for review before committing.

## Server
- Host: `condor.unix.com` (France)
- App root: `/var/stellar_pop`
- Rails port: `3003` (SSH tunnel required from local Mac)
- Rails environment: `development` (workflow is development-only, not production)
- Ruby: `3.0.4` via rbenv
- SQLite: `storage/development.sqlite3` (committed to GitHub)
- Sidekiq: `bundle exec sidekiq` (manual start)
- SSH tunnel: `ssh -L 3003:127.0.0.1:3003 neo@condor.unix.com`

## Key Commands
- Start Rails: `rails server -p 3003 -b 127.0.0.1`
- Start Sidekiq: `bundle exec sidekiq`
- Run tests: `bin/rails test`
- Verify SDSS: `bin/rails sdss:verify_photometry`
- Console: `rails c`
