# TODO

## Science/Physics

- [x] Verify smoothed composite spectrum shape is physically reasonable
- [x] Validate local-catalog elliptical target scenario (NGC3379) with lower chi-squared than quasar baseline
- [x] Add BaSeL 3.1 spectral library parser (`BaselSpectra`) with Fortran-order indexing and flux sentinel filtering
- [x] Wire BaSeL metallicity selection from `metallicity_z` (nearest zlegend bin where available)
- [x] Implement SDSS filter convolution for chi-squared (replace nearest-wavelength approximation)
- [x] Add model option to switch between Planck spectra and BaSeL library spectra in pipeline/UI
- [x] Implement Salpeter IMF in `ImfSampler` and pass `imf_type` through pipeline jobs
- [x] Expose burst SFH `burst_age_gyr` and `burst_width_gyr` parameters in UI and pipeline
- [x] Clarify SDSS failure reasons (timeout vs unreachable API vs no object found) in run notes
- [x] Validate isochrone temperature corrections against published tables
- [x] Replace simple Isochrone KS with MistIsochrone in pipeline as default
- [x] Integrate MIST corrections for non-solar metallicities
- [x] Add wavelength range control to the UI and new run form
- [x] Download and integrate remaining BaSeL metallicity bins (z0.0002, z0.0006, z0.0020, z0.0063, z0.0632)
- [ ] Verify local catalog photometry magnitude type (model vs Petrosian) and update `mag_type` column when SDSS SkyServer is available
- [ ] Update `SdssClient` SQL query to fetch `modelMag_u/g/r/i/z` instead of default Petrosian magnitudes when SDSS returns
- [ ] Run `sdss:verify_photometry` rake task and update `sdss_dr` provenance for all catalog entries
- [x] Add Chabrier (2003) IMF as a third option alongside Kroupa and Salpeter
- [x] Add delayed exponential SFH model (`tau * t * exp(-t/tau)`)
- [x] Implement k-corrections for redshifted galaxies — correct observed ugriz magnitudes to rest-frame before chi-squared comparison; required for catalog objects at `z > 0.01`
- [x] Add redshift (`z`) column to local SDSS catalog for each object
- [ ] Verify and document which photometry type (model vs Petrosian) is used for each catalog entry; switch to model magnitudes for all entries when SDSS returns
- [ ] Investigate NGC3379 age estimate — best fit 0.5 Gyr is too young for a known passive elliptical, likely related to photometry magnitude type
- [x] Extend grid sweep to include `burst_age_gyr` variation
- [ ] Add more galaxy targets to local SDSS catalog covering wider range of types and environments
- [ ] Validate grid fit results against published SPS fits for M101 and NGC3379 from the literature

## Data and Persistence

- [x] Add local SDSS reference catalog CSV and nearest-object lookup
- [x] Add local catalog metadata fields (`agn`, `sdss_dr`) and galaxy-only target selection
- [x] Add parameter grid sweep fitting (GridFit) with ranked chi-squared results
- [x] Add benchmark calibration workflow (`CalibrationRun`) with pass/warn/fail summary and ranked benchmark fits
- [ ] Add more galaxy targets to local SDSS catalog
- [ ] Add side-by-side run comparison view
- [ ] Add spectrum data export as CSV
- [ ] Add run deletion from the UI
- [ ] Add user or session scoping to `SynthesisRuns`

## Infrastructure

- [x] Review fail2ban setup for static asset and app endpoints
- [ ] Add production environment configuration
- [x] Add health check endpoint

## Testing

- [x] Add tests for `SynthesisPipelineJob` success/failure paths
- [x] Add tests for `StellarPop::SdssClient` response parsing and nil/error handling
- [x] Add tests for chi-squared calculation against known fixtures
- [x] Add model validations for `SynthesisRun` inputs (ranges/types/presence)
- [x] Add unit tests for `ImfSampler`, `StellarSpectra`, `Isochrone`, `SfhModel`
- [x] Add integration tests for full pipeline
- [ ] Add CI configuration (workflow file push requires PAT with `workflow` scope)

## UI/UX

- [x] Add canvas-based spectrum viewer on `SynthesisRun#show`
- [x] Show pipeline configuration panel with active scientific model selections and citations
- [x] Add navbar Sidekiq online/offline status indicator (green/red badge)
- [ ] Add zoom and pan to canvas spectrum viewer
- [x] Add progress indicator beyond status polling
- [x] Add visible processing banner for pending/running runs
- [x] Show error details in UI when a run fails
- [x] Make SDSS fetch optional/toggleable in UI
- [x] Make SynthesisRun form usable by default with catalog target selector + RA/Dec autofill
- [x] Add deterministic plain-language interpretation panel on Grid Fit show page
- [ ] Improve CSS polish across index/new/show views
- [ ] Add configuration page for pipeline parameters
- [ ] Add confidence intervals or chi-squared contour plots for grid fit results
- [ ] Investigate age-metallicity degeneracy breaking with additional photometric bands
- [ ] Document deployment and runbook updates
