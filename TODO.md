# TODO

## Science/Physics

- [x] Verify smoothed composite spectrum shape is physically reasonable
- [x] Add BaSeL 3.1 spectral library parser (`BaselSpectra`) with Fortran-order indexing and flux sentinel filtering
- [x] Implement SDSS filter convolution for chi-squared (replace nearest-wavelength approximation)
- [ ] Add model option to switch between Planck spectra and BaSeL library spectra in pipeline/UI
- [ ] Implement Salpeter IMF in `ImfSampler` (currently selectable but not functional)
- [ ] Expose burst SFH `burst_age_gyr` and `width_gyr` parameters in the UI
- [ ] Validate isochrone temperature corrections against published tables
- [ ] Add wavelength range control to the UI and new run form

## Data and Persistence

- [ ] Add side-by-side run comparison view
- [ ] Add spectrum data export as CSV
- [ ] Add run deletion from the UI
- [ ] Add user or session scoping to `SynthesisRuns`

## Infrastructure

- [x] Review fail2ban setup for static asset and app endpoints
- [ ] Add production environment configuration
- [ ] Add systemd unit file for Sidekiq process management
- [ ] Add log rotation configuration
- [ ] Add database backup strategy
- [x] Add health check endpoint

## Testing

- [x] Add tests for `SynthesisPipelineJob` success/failure paths
- [x] Add tests for `StellarPop::SdssClient` response parsing and nil/error handling
- [x] Add tests for chi-squared calculation against known fixtures
- [x] Add model validations for `SynthesisRun` inputs (ranges/types/presence)
- [x] Add unit tests for `ImfSampler`, `StellarSpectra`, `Isochrone`, `SfhModel`
- [x] Add integration tests for full pipeline
- [x] Add CI configuration

## UI/UX

- [x] Add canvas-based spectrum viewer on `SynthesisRun#show`
- [ ] Add zoom and pan to canvas spectrum viewer
- [ ] Add progress indicator beyond status polling
- [x] Add visible processing banner for pending/running runs
- [x] Show error details in UI when a run fails
- [x] Make SDSS fetch optional/toggleable in UI
- [ ] Improve CSS polish across index/new/show views
- [ ] Add configuration page for pipeline parameters
- [ ] Document deployment and runbook updates
