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
- [x] Validate isochrone temperature corrections against published tables
- [x] Replace simple Isochrone KS with MistIsochrone in pipeline as default
- [x] Integrate MIST corrections for non-solar metallicities
- [x] Add wavelength range control to the UI and new run form
- [x] Download and integrate remaining BaSeL metallicity bins (z0.0002, z0.0006, z0.0020, z0.0063, z0.0632)

## Data and Persistence

- [x] Add local SDSS reference catalog CSV and nearest-object lookup
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
- [ ] Add zoom and pan to canvas spectrum viewer
- [x] Add progress indicator beyond status polling
- [x] Add visible processing banner for pending/running runs
- [x] Show error details in UI when a run fails
- [x] Make SDSS fetch optional/toggleable in UI
- [ ] Improve CSS polish across index/new/show views
- [ ] Add configuration page for pipeline parameters
- [ ] Document deployment and runbook updates
