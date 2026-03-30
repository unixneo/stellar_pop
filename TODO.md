# TODO

Legend: 🟩 Done, 🟨 Pending, 🟥 Critical Pending, 🟦 Critical: SDSS Offline, ⬜ Optional

## Science/Physics

- 🟦 Validate grid fit results for M101 against published SPS fits — pending, blocked on DR18 photometry resolution
- 🟨 Run `sdss:verify_photometry` rake task and update `sdss_dr` provenance for all catalog entries
- 🟨 Add more galaxy targets to local SDSS catalog covering wider range of types and environments
- 🟨 Add photometric error columns to `galaxies` table: `petro_u_err`, `petro_g_err`, `petro_r_err`, `petro_i_err`, `petro_z_err`, `model_u_err`, `model_g_err`, `model_r_err`, `model_i_err`, `model_z_err` and fetch from SDSS `petroMagErr` and `modelMagErr` fields
- 🟨 Add observation uncertainty columns to `observations` table: `age_err_plus`, `age_err_minus`, `metallicity_err_plus`, `metallicity_err_minus`, `method_note`
- 🟨 Update chi-squared to weighted form: `sum((model-observed)^2 / sigma^2)` per band
- 🟨 Use configurable per-band sigma floor when errors are missing, and flag reduced confidence
- 🟩 Store both Petrosian and model magnitudes in `galaxies` (`petro_*`, `model_*`) and keep active photometry provenance in `mag_type`
- 🟩 Update `SdssClient` photometry query path to retrieve both `petroMag_*` and `modelMag_*` fields
- 🟩 Add DR19 objid maintenance tasks (`sdss:verify_objids`, `sdss:fix_objids`) and objid-first photometry fetch for catalog refresh (`sdss:fetch_dr19_photometry`)
- 🟩 Investigate NGC3379 age estimate — resolved by correcting DR19 objid-based photometry fetch (root cause was source-object selection, not magnitude type)
- 🟩 Validate grid fit results for NGC3379 against published SPS fits — validated: best fit age 8-10 Gyr is consistent with published 9.3 Gyr after DR19 photometry fix
- 🟩 Verify smoothed composite spectrum shape is physically reasonable
- 🟩 Validate local-catalog elliptical target scenario (NGC3379) with lower chi-squared than quasar baseline
- 🟩 Add BaSeL 3.1 spectral library parser (`BaselSpectra`) with Fortran-order indexing and flux sentinel filtering
- 🟩 Wire BaSeL metallicity selection from `metallicity_z` (nearest zlegend bin where available)
- 🟩 Implement SDSS filter convolution for chi-squared (replace nearest-wavelength approximation)
- 🟩 Add model option to switch between Planck spectra and BaSeL library spectra in pipeline/UI
- 🟩 Implement Salpeter IMF in `ImfSampler` and pass `imf_type` through pipeline jobs
- 🟩 Expose burst SFH `burst_age_gyr` and `burst_width_gyr` parameters in UI and pipeline
- 🟩 Clarify SDSS failure reasons (timeout vs unreachable API vs no object found) in run notes
- 🟩 Validate isochrone temperature corrections against published tables
- 🟩 Replace simple Isochrone KS with MistIsochrone in pipeline as default
- 🟩 Integrate MIST corrections for non-solar metallicities
- 🟩 Add wavelength range control to the UI and new run form
- 🟩 Download and integrate remaining BaSeL metallicity bins (z0.0002, z0.0006, z0.0020, z0.0063, z0.0632)
- 🟩 Add Chabrier (2003) IMF as a third option alongside Kroupa and Salpeter
- 🟩 Add delayed exponential SFH model (`tau * t * exp(-t/tau)`)
- 🟩 Implement k-corrections for redshifted galaxies — correct observed ugriz magnitudes to rest-frame before chi-squared comparison; required for catalog objects at `z > 0.01`
- 🟩 Add redshift (`z`) column to local SDSS catalog for each object
- 🟩 Extend grid sweep to include `burst_age_gyr` variation

## Data and Persistence

- 🟨 Backfill `sdss_objid` for all galaxies via SDSS query and persist in `galaxies` table
- 🟨 Add side-by-side run comparison view
- 🟨 Add GSWLC-specific importer/profile mapping (column normalization + validation presets)
- ⬜ Add spectrum data export as CSV
- ⬜ Add user or session scoping to `SynthesisRuns`
- 🟩 Build galaxy import tool to load new galaxies from CSV
- 🟩 Rename internal `CalibrationRun` model/routes/job naming to `BenchmarkRun` for terminology consistency
- 🟩 Add run deletion from the UI
- 🟩 Update `sdss:verify_photometry` rake task to read from `galaxies` table instead of `lib/data/sdss/photometry.csv` (then `photometry.csv` becomes archival only)
- 🟩 Retire `SdssLocalCatalog` after all tests/docs are migrated to `Galaxy` model lookups
- 🟩 Add local SDSS reference catalog CSV and nearest-object lookup
- 🟩 Add local catalog metadata fields (`agn`, `sdss_dr`) and galaxy-only target selection
- 🟩 Add configurable SDSS dataset release (`DR18`/`DR19`) in pipeline config UI and apply it to selectors/API-backed workflows
- 🟩 Add configurable SDSS magnitude type preference (`petrosian`/`model`) in pipeline config and use it to populate active `mag_u..mag_z` during DR19 photometry refresh
- 🟩 Migrate galaxy photometry to SQLite `galaxies` table and add `galaxy_id` foreign keys on `synthesis_runs`/`grid_fits`
- 🟩 Switch synthesis/grid runtime lookup path from `SdssLocalCatalog` to `Galaxy` table (`find_by(name)` / `find_by_ra_dec`)
- 🟩 Add `observations` table for academic benchmark data
- 🟩 Back-fill `galaxy_id` on existing `synthesis_runs` and `grid_fits`
- 🟩 Add parameter grid sweep fitting (GridFit) with ranked chi-squared results
- 🟩 Add benchmark calibration workflow (`CalibrationRun`) with pass/warn/fail summary and ranked benchmark fits

## Infrastructure

- ⬜ Add production environment configuration
- 🟩 Review fail2ban setup for static asset and app endpoints
- 🟩 Add health check endpoint

## Testing

- ⬜ Add CI configuration (workflow file push requires PAT with `workflow` scope)
- 🟩 Add tests for `SynthesisPipelineJob` success/failure paths
- 🟩 Add tests for `StellarPop::SdssClient` response parsing and nil/error handling
- 🟩 Add tests for chi-squared calculation against known fixtures
- 🟩 Add model validations for `SynthesisRun` inputs (ranges/types/presence)
- 🟩 Add unit tests for `ImfSampler`, `StellarSpectra`, `Isochrone`, `SfhModel`
- 🟩 Add integration tests for full pipeline

## UI/UX

- 🟨 Add confidence intervals or chi-squared contour plots for grid fit results
- 🟨 Document deployment and runbook updates
- ⬜ Improve CSS polish across index/new/show views
- ⬜ Add zoom and pan to canvas spectrum viewer
- ⬜ Investigate age-metallicity degeneracy breaking with additional photometric bands
- 🟩 Add configuration page for pipeline parameters
- 🟩 Add canvas-based spectrum viewer on `SynthesisRun#show`
- 🟩 Show pipeline configuration panel with active scientific model selections and citations
- 🟩 Add navbar Sidekiq online/offline status indicator (green/red badge)
- 🟩 Add progress indicator beyond status polling
- 🟩 Add visible processing banner for pending/running runs
- 🟩 Show error details in UI when a run fails
- 🟩 Make SDSS fetch optional/toggleable in UI
- 🟩 Make SynthesisRun form usable by default with catalog target selector + RA/Dec autofill
- 🟩 Add deterministic plain-language interpretation panel on Grid Fit show page
