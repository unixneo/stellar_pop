# TODO

Legend: 🟩 Done, ⬜ Optional, 🟨 Pending, 🟦 Critical: SDSS Offline, 🟥 Critical Pending

v0.3.3 doc sync:
- 🟩 DR19 default + pipeline-config release selector documented
- 🟩 Objid-first SDSS photometry fetch documented
- 🟩 Petro/model dual photometry + `mag_type` control documented
- 🟩 Chabrier IMF, delayed-exponential SFH, `burst_age_gyr` grid sweep, and k-corrections documented
- 🟩 Synthesis-run stellar mass estimation documented (best-fit SFH/IMF + observed `r` + redshift-distance)
- 🟩 Literature observations update documented for 16 galaxies with published sources
- 🟩 NGC3379 age correction documented (`0.5` Gyr -> `8-10` Gyr)

v0.3.4 packaging/doc sync:
- 🟩 Extract FITS parsing into standalone `fits_parser` gem repository (`https://github.com/unixneo/fits_parser`)
- 🟩 Publish `fits_parser` `0.1.0` to RubyGems and switch app dependency from local path/git source to RubyGems (`gem "fits_parser", "~> 0.1.0"`)
- 🟩 Update FITS rake tasks to load parser via `require "fits_parser"` (Bundler-managed gem)
- 🟩 Add DR19-to-DR7 FIT coordinate crossmatch task (`fits:crossmatch_dr19_gal_info`) with 1-arcsec matching and JSON report output
- 🟩 Add FIT stellar-mass PDF extraction task from crossmatch reports (`fits:mass_pdfs_from_report`)
- 🟩 Add FIT-vs-observations stellar-mass comparison task (`fits:compare_mass_pdfs_with_observations`) in log-mass space with interval checks (`P16-P84`, `P2P5-P97P5`)
- 🟩 Update NGC4387 observation stellar mass from FIT `AVG` PDF value with FIT provenance note (`method_used=fits_pdf_avg`)
- 🟩 Add DR2 Gallazzi catalog schema (`gallazzi_stellar_metallicities`, `gallazzi_rband_weighted_ages`) with unique `(plateid,mjd,fiberid)` keys
- 🟩 Add DR2 Gallazzi importer task (`gallazzi:import_dr2`) and ingest both catalogs (`261054` rows each)
- 🟩 Move Gallazzi catalogs off main app DB into dedicated development SQLite files (`storage/gallazzi_*_development.sqlite3`) and drop Gallazzi tables from `storage/development.sqlite3`
- 🟩 Reclaim SQLite file space after Gallazzi table removal (`VACUUM`), reducing main DB from ~84MB to ~1.1MB
- 🟩 Add Gallazzi age-to-main-galaxy comparison task (`gallazzi:compare_ages_to_galaxies`) with SDSS object-id-first matching and RA/DEC fallback; current run reports `0` overlap with local `galaxies`
- 🟩 Add MaNGA/SDSS FIREFLY FIT crossmatch workflows:
  - `fits:crossmatch_pipe3d_galaxies` (DR17 Pipe3D; overlap `1/35`)
  - `fits:crossmatch_firefly_galaxies` (DR17 MaNGA FIREFLY globalprop; overlap `2/35`)
  - `fits:crossmatch_eboss_firefly_galaxies` (DR16 eBOSS FIREFLY; overlap `12/35`, `11` ObjID + `1` RA/DEC)
- 🟩 Add DR16 FIREFLY-vs-observations comparison task (`fits:compare_eboss_firefly_with_observations`) and export normalized age/Z/mass comparison JSON
- 🟩 Run fast BM over FIREFLY-overlap targets (`10` galaxies with observations) and export BM-vs-FIREFLY value comparison JSON (`lib/data/fit/firefly_bm_vs_firefly_values.json`)
- 🟩 Fix FIREFLY metallicity comparison units in JSON/report workflow (keep raw value and add converted `Z` assuming linear `Z/Zsun` with `Zsun=0.02`)
- 🟩 Document FIREFLY aperture-effects and match-quality caveats in `paper.md` (fiber-vs-global light and large-separation match risk)

v0.3.5 galaxy data-model split:
- 🟩 Add `galaxy_photometries` and `galaxy_spectroscopies` tables and backfill from existing `galaxies` columns
- 🟩 Add dedicated edit controllers/routes/views for measurement cards (`/galaxies/:id/photometry/edit`, `/galaxies/:id/spectroscopy/edit`)
- 🟩 Refactor galaxy show page into distinct Identity/Photometry/Spectroscopy cards
- 🟩 Move galaxy index to render split measurement data (`photometry` mags + `spectroscopy` redshift)
- 🟩 Remove index-row edit actions; keep metadata/measurement edits in show-card actions
- 🟩 Migrate calculators/jobs to read split measurement tables (`galaxy_photometries`, `galaxy_spectroscopies`) as canonical sources
- 🟩 Drop duplicated legacy measurement columns from `galaxies`; keep identity/provenance fields only
- 🟩 Support spectroscopy history with `has_many :galaxy_spectroscopies` and current-row promotion/demotion logic
- 🟩 Add spectroscopy history test coverage (model + integration flows)
- 🟩 Add `photometry_usable` flags to `galaxies` and `galaxy_photometries` (default `true`) and exclude unusable targets from benchmark selection via `Galaxy.usable_photometry`
- 🟩 Add SIMBAD spectroscopy ingestion task for a single galaxy (`external:import_simbad_spectroscopy`)
- 🟩 Add DR19 SIMBAD z audit/report JSON (`lib/data/fit/dr19_simbad_z_check.json`)
- 🟩 Add bulk SIMBAD report apply task to spectroscopy history (`external:apply_simbad_z_report`)
- 🟩 Backfill DR19 spectroscopy current rows from SIMBAD z report (`26/26` with current non-nil z)
- 🟩 Remove legacy unresolved spectroscopy rows with `redshift_z=nil` after SIMBAD backfill
- 🟩 Add AGN traceability columns on `galaxies` (`agn_source`, `agn_method`, `agn_confidence`, `agn_checked_at`)
- 🟩 Add SDSS DR19 AGN classification task (`sdss:classify_agn_dr19`) using `SpecObj.class/subClass` by `bestObjID = sdss_objid` with JSON report output (`lib/data/fit/dr19_agn_classification_report.json`)
- 🟩 Persist SDSS-based AGN classifications where strict objid linkage resolves (`5/26` DR19 galaxies in current run)
- 🟩 Show AGN flags in benchmark UI target listings (`/benchmark_runs/new` sortable AGN column and `/benchmark_runs` targets-with-AGN summary column)
- 🟨 Resolve remaining DR19 AGN classification coverage (`21/26` unresolved under strict SDSS `bestObjID`) via controlled fallback policy
- 🟨 Restore SIMBAD connectivity (or provide offline SIMBAD export) so `external:classify_simbad_agn_for_unresolved_dr19` can classify unresolved AGN rows

v0.3.7 mass calibration tuning:
- 🟩 Add `calibration_mass_log_offset_dex` to `PipelineConfig` defaults/form persistence
- 🟩 Add standalone `Tuning` section in Pipeline Config UI (show/edit) for mass calibration controls
- 🟩 Apply `calibration_mass_log_offset_dex` in synthesis and benchmark stellar-mass estimation paths
- 🟩 Add tests for config persistence and estimator `10^dex` scaling behavior
- 🟨 Evaluate whether a single global mass offset should be replaced by tier/type-specific or confidence-weighted mass calibration
- 🟨 Add benchmark report helper to emit before/after mass-offset deltas in one JSON artifact for calibration tracking

v0.3.8 SFH weighting validation (experimental; do not push yet):
- 🟩 Verify and document SFH-weighting bug in `SpectralIntegrator` (sfh_weights read but not applied) with minimal reproducible evidence
- 🟩 Implement luminosity-aware SFH accumulation fix in `SpectralIntegrator` (`sfh_weight * luminosity_scale` per age bin)
- 🟨 Run paired post-fix Tier1 protocol: exponential-only then delayed-only, and record strict side-by-side outputs in `CALIBRATE.md`
- 🟨 Investigate severe age regression after SFH weighting patch (`run 73`, exponential-only) before any merge to `main`
- 🟨 Fix benchmark progress denominator bug when SFH model list excludes `burst` (current `progress_total` overcounts combinations)
- 🟥 Hold commit/push of SFH weighting patch until post-fix diagnostics produce an explicit accept/reject decision
- 🟨 Resolve objective mismatch where chi-squared winner is less observationally plausible than a near-best alternative (documented for NGC4564 exponential)

## Science/Physics
- 🟦 Validate grid fit results for M101 against published SPS fits — pending, blocked on DR18 photometry resolution
- 🟨 Add more galaxy targets to local SDSS catalog covering wider range of types and environments
- 🟨 Execute calibration plan in `CALIBRATE.md` (Phases 1-4) and track per-phase completion in TODO
- 🟨 Stellar mass estimator needs calibration -- current M/L ratios produce systematic underestimates; validate against NGC3379 and NGC4472 published masses and recalibrate SFH_BASE_MASS_TO_LIGHT and age_scale formula
- 🟨 Reconcile DR19 `sdss_objid` values where `SpecObj.bestObjID` lookup fails and restore high-confidence redshift coverage for benchmark targets
- 🟨 Add strict redshift sanity checks (target-type-aware z bounds) to block implausible spectroscopic matches from ever being persisted
- 🟨 Add weighted chi-squared in benchmark and grid jobs using stored `err_*` columns (`sum((model-observed)^2 / sigma^2)`)
- 🟨 Add observation uncertainty columns to `observations` table: `age_err_plus`, `age_err_minus`, `metallicity_err_plus`, `metallicity_err_minus`, `method_note`
- 🟨 Use configurable per-band sigma floor when errors are missing, and flag reduced confidence
- 🟨 Upgrade isochrone source from MIST v1.2 to latest MIST v2.5 in a controlled path: ingest v2.5 side-by-side, run v1.2 vs v2.5 A/B benchmarks on the same galaxy set, document deltas, and switch default only after calibration sign-off
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
- 🟩 Add stellar mass estimation to synthesis pipeline and persist to `synthesis_runs.stellar_mass` (derived from SFH, IMF, observed `r` magnitude, and redshift-based luminosity distance)
- 🟩 Run `sdss:verify_photometry` rake task and update `sdss_dr` provenance for all catalog entries — provenance updated via DR19 objid-based fetch with both Petrosian and model magnitude storage
- 🟩 Add SDSS uncertainty/quality ingestion for DR19 galaxies (`petro_err_*`, `model_err_*`, `err_*`, `extinction_*`, `sdss_clean`, `z_err`, `z_warning`)
- 🟩 Add galaxy-level benchmark confidence fields (`id_match_quality`, `id_match_distance_arcsec`, `redshift_source`, `redshift_confidence`, `redshift_checked_at`)
- 🟩 Add benchmark data-quality gate and UI visibility (`data_quality_ok`, benchmark eligibility reasons)
- 🟩 Decouple benchmark classification from run-level validation gating (gate off no longer forces `pass`; checks still classify `pass/warn/fail`)


## Data and Persistence
- 🟨 Backfill `sdss_objid` for all galaxies via SDSS query and persist in `galaxies` table
- 🟨 Add side-by-side run comparison view
- 🟨 Add GSWLC-specific importer/profile mapping (column normalization + validation presets)
- ⬜ Add spectrum data export as CSV
- ⬜ Add user or session scoping to `SynthesisRuns`
- 🟩 Build galaxy import tool to load new galaxies from CSV
- 🟩 Rename internal `CalibrationRun` model/routes/job naming to `BenchmarkRun` for terminology consistency
- 🟩 Add run deletion from the UI
- 🟩 Keep `sdss:verify_photometry` DB-only against the `galaxies` table
- 🟩 Retire `SdssLocalCatalog` after all tests/docs are migrated to `Galaxy` model lookups
- 🟩 Add local SDSS reference catalog CSV and nearest-object lookup
- 🟩 Add local catalog metadata fields (`agn`, `sdss_dr`) and galaxy-only target selection
- 🟩 Add configurable SDSS dataset release (`DR18`/`DR19`) in pipeline config UI and apply it to selectors/API-backed workflows
- 🟩 Add configurable SDSS magnitude type preference (`petrosian`/`model`) in pipeline config and use it to populate active `mag_u..mag_z` during DR19 photometry refresh
- 🟩 Migrate galaxy photometry to SQLite `galaxies` table and add `galaxy_id` foreign keys on `synthesis_runs`/`grid_fits`
- 🟩 Switch synthesis/grid runtime lookup path from `SdssLocalCatalog` to `Galaxy` table (`find_by(name)` / `find_by_ra_dec`)
- 🟩 Add `observations` table for academic benchmark data
- 🟩 Update literature observation coverage for 16 galaxies with published sources
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
