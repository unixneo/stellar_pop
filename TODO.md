# TODO

Legend: 🟩 done, 🟨 pending, 🟥 critical pending

## Science/Physics

- 🟥 Verify local catalog photometry magnitude type (model vs Petrosian) and update `mag_type` column when SDSS SkyServer is available
- 🟥 Update `SdssClient` SQL query to fetch `modelMag_u/g/r/i/z` instead of default Petrosian magnitudes when SDSS returns
- 🟥 Verify and document which photometry type (model vs Petrosian) is used for each catalog entry; switch to model magnitudes for all entries when SDSS returns
- 🟥 Investigate NGC3379 age estimate — best fit 0.5 Gyr is too young for a known passive elliptical, likely related to photometry magnitude type
- 🟥 Validate grid fit results against published SPS fits for M101 and NGC3379 from the literature
- 🟨 Run `sdss:verify_photometry` rake task and update `sdss_dr` provenance for all catalog entries
- 🟨 Add more galaxy targets to local SDSS catalog covering wider range of types and environments
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

- 🟨 Rename internal `CalibrationRun` model/routes/job naming to `BenchmarkRun` for terminology consistency
- 🟨 Add more galaxy targets to local SDSS catalog
- 🟨 Add side-by-side run comparison view
- 🟨 Add spectrum data export as CSV
- 🟨 Add run deletion from the UI
- 🟨 Add user or session scoping to `SynthesisRuns`
- 🟩 Add local SDSS reference catalog CSV and nearest-object lookup
- 🟩 Add local catalog metadata fields (`agn`, `sdss_dr`) and galaxy-only target selection
- 🟩 Add parameter grid sweep fitting (GridFit) with ranked chi-squared results
- 🟩 Add benchmark calibration workflow (`CalibrationRun`) with pass/warn/fail summary and ranked benchmark fits

## Infrastructure

- 🟨 Add production environment configuration
- 🟩 Review fail2ban setup for static asset and app endpoints
- 🟩 Add health check endpoint

## Testing

- 🟨 Add CI configuration (workflow file push requires PAT with `workflow` scope)
- 🟩 Add tests for `SynthesisPipelineJob` success/failure paths
- 🟩 Add tests for `StellarPop::SdssClient` response parsing and nil/error handling
- 🟩 Add tests for chi-squared calculation against known fixtures
- 🟩 Add model validations for `SynthesisRun` inputs (ranges/types/presence)
- 🟩 Add unit tests for `ImfSampler`, `StellarSpectra`, `Isochrone`, `SfhModel`
- 🟩 Add integration tests for full pipeline

## UI/UX

- 🟨 Add zoom and pan to canvas spectrum viewer
- 🟨 Improve CSS polish across index/new/show views
- 🟨 Add configuration page for pipeline parameters
- 🟨 Add confidence intervals or chi-squared contour plots for grid fit results
- 🟨 Investigate age-metallicity degeneracy breaking with additional photometric bands
- 🟨 Document deployment and runbook updates
- 🟩 Add canvas-based spectrum viewer on `SynthesisRun#show`
- 🟩 Show pipeline configuration panel with active scientific model selections and citations
- 🟩 Add navbar Sidekiq online/offline status indicator (green/red badge)
- 🟩 Add progress indicator beyond status polling
- 🟩 Add visible processing banner for pending/running runs
- 🟩 Show error details in UI when a run fails
- 🟩 Make SDSS fetch optional/toggleable in UI
- 🟩 Make SynthesisRun form usable by default with catalog target selector + RA/Dec autofill
- 🟩 Add deterministic plain-language interpretation panel on Grid Fit show page
