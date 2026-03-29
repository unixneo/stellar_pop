1. Workflow: Claude is engineer and scientist, Codex CLI is coder.
   Claude generates prompts for Codex. Never give code directly.

2. Always update README.md, TODO.md, and paper.md before committing
   code changes. Assess each for whether an update is needed.

3. All Codex prompts must be in separate code blocks from other text and instructions for easy copy/paste.

4. Commit message format: "step N: description"

5. Server: condor, Rails on port 3003, SSH tunnel
   ssh -L 3003:127.0.0.1:3003 neo@condor.unix.com

6. SQLite database at storage/development.sqlite3

7. Redis at 127.0.0.1:6379

8. Editor: vi not nano. macOS and Linux only.

9. Science goal: stellar population synthesis fitting of SDSS galaxies
   using ugriz photometry, chi-squared minimization against synthetic
   spectra from IMF, isochrone, SFH, and spectral library components.
