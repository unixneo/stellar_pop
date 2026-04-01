# StellarPop

[![DOI](https://zenodo.org/badge/DOI/10.5281/zenodo.19277970.svg)](https://doi.org/10.5281/zenodo.19277970)

## What This App Does

StellarPop is a Ruby on Rails application that generates a synthetic stellar
population spectrum from user-defined astrophysical inputs (IMF, age, metallicity,
and SFH model). It runs an async pipeline, persists the resulting spectrum, and
optionally compares synthetic output against SDSS `ugriz` photometry using a
chi-squared metric.

## v0.3.3 Updates

- SDSS `DR19` is now the default dataset release, configurable in `/pipeline_config/edit`.
- Live SDSS photometry refresh now uses objid-based fetch as the primary path (`sdss_objid`), replacing coordinate-first lookup for runtime fetches.
- The `galaxies` table stores both Petrosian and model magnitudes (`petro_*`, `model_*`) per galaxy, with `mag_type` controlling active `mag_u..mag_z`.
- Added Chabrier IMF support alongside Kroupa and Salpeter.
- Added delayed exponential SFH (`tau * t * exp(-t/tau)`).
- Added `burst_age_gyr` as a grid-sweep parameter for burst SFH runs.
- Added redshift k-corrections before SDSS `ugriz` chi-squared comparison.
- Added synthesis-run stellar mass estimation from best-fit SFH/IMF, observed `r`-band magnitude, and redshift-based luminosity distance.
- Updated literature-backed observations for 16 galaxies with published sources.
- Corrected NGC3379 best-fit age interpretation from `0.5` Gyr to `8-10` Gyr.

## v0.3.4 Data-Quality and Benchmark Reliability Updates

- FITS parsing was extracted into a standalone Ruby gem (`fits_parser`) and is now consumed via Bundler from RubyGems (`~> 0.1.0`) instead of a local parser path.
- The gem repository is maintained at `https://github.com/unixneo/fits_parser`.
- Added FIT crossmatch/validation workflows for DR19 galaxies against MPA-JHU DR7 FIT tables:
  - `fits:crossmatch_dr19_gal_info` (coordinate match against `gal_info_dr7_v5_2.fit`, default 1 arcsec)
  - `fits:mass_pdfs_from_report` (pull `totlgm_dr7_v5_2.fit` stellar-mass PDFs for matched rows)
  - `fits:compare_mass_pdfs_with_observations` (compare FIT log-mass PDFs with `observations.stellar_mass`)
- FIT-based mass validation now reports interval coverage in log-mass space (`P16-P84` and `P2P5-P97P5`) and supports JSON export for reproducibility.
- Added DR2 Gallazzi reference-catalog ingestion for stellar metallicity and r-band weighted age:
  - schema tables: `gallazzi_stellar_metallicities`, `gallazzi_rband_weighted_ages`
  - import task: `bin/rails gallazzi:import_dr2`
  - ingested rows: `261,054` metallicity + `261,054` age
  - storage split: Gallazzi catalogs now live in dedicated development SQLite files
    (`storage/gallazzi_stellar_metallicities_development.sqlite3`,
    `storage/gallazzi_rband_weighted_ages_development.sqlite3`) via model-specific
    external DB connections, not the main `storage/development.sqlite3`
- Added SDSS uncertainty and quality ingestion for DR19 galaxies:
  - per-band photometric errors (`err_*`, `petro_err_*`, `model_err_*`)
  - per-band extinction (`extinction_*`)
  - SDSS clean flag (`sdss_clean`)
  - spectroscopy quality fields (`z_err`, `z_warning`)
- Added galaxy-level identity and redshift provenance fields:
  - `id_match_quality`, `id_match_distance_arcsec`, `id_match_note`
  - `redshift_source`, `redshift_confidence`, `redshift_checked_at`
- Benchmarks now include a hard data-quality gate:
  - only benchmark-eligible targets (exact object-ID match + required quality fields)
    are treated as valid scientific comparisons
  - ineligible targets are explicitly flagged in benchmark output with reasons
- Benchmark UI now exposes per-target data quality directly:
  - color-coded OID match and data-quality columns on `/benchmark_runs/new`
  - per-run benchmark result cards include a Data Quality table and `data_quality_ok` check
- SDSS ingestion was hardened to prevent redshift field collisions:
  - spectroscopic redshift aliases (`spec_z`, `spec_zErr`, `spec_zWarning`) are
    separated from photometric `z` band in parsing

## FIT Crossmatch Snapshot (DR19 sample)

Recent DR19 sample crossmatch against DR7 FIT metadata (`gal_info_dr7_v5_2.fit`) found 3 matches within 1 arcsec for the active benchmark subset (`NGC4889`, `NGC4874`, `NGC4387`). Stellar-mass PDF extraction from `totlgm_dr7_v5_2.fit` and comparison against `observations.stellar_mass` showed 3/3 inside the 95% interval (`P2P5-P97P5`) after updating `NGC4387` to the FIT-derived `AVG` value with explicit FIT provenance.

## Why This App Exists

The goal is to show that a practical stellar population synthesis workflow can be
implemented end-to-end in Ruby on Rails, with:

- domain logic in pure Ruby,
- transparent pipeline orchestration via a blackboard pattern,
- reproducible async processing via Sidekiq jobs,
- and an inspectable web UI for runs, spectra, and fit quality.

StellarPop provides a self-contained stellar population fitting pipeline
that is controlled by, and the results viewed, in a browser, requires no local scientific computing environment,
and produces version-controlled reproducible results. A researcher with
galaxy coordinates and observed photometry can run a 1050-combination
parameter grid fit (or a reduced fast benchmark sweep) and identify the best-fit age, metallicity, and star
formation history without installing Python, Fortran, or any astronomy
library.

## Scientific Purpose

Stellar population synthesis fitting lets us infer a galaxy's physical history
from integrated light alone. By comparing synthetic spectra against observed
photometry, we can estimate which combination of age, metallicity, and star
formation history most plausibly produced the observed fluxes.

This matters because it connects observed galaxy light to core astrophysical
questions: the cosmic star formation history, galaxy evolution and quenching,
and stellar mass estimation. For example, if NGC3379 is best fit by a model
with age ~10 Gyr, solar metallicity, and an exponential SFH, the interpretation
is that most stars formed rapidly about 10 billion years ago and the system has
since evolved passively, consistent with a red-and-dead elliptical in the Virgo
cluster.

StellarPop provides a deployable, reproducible, browser-based fitting workflow
for researchers working on smaller targeted samples who still need citable,
version-controlled outputs without maintaining a Python or Fortran stack. It is
not intended to replace FSPS or PEGASE for large-survey production, but it is a
practical option for focused studies of roughly 10-50 galaxies.

The chi-squared metric is the fit-quality score: it measures how closely the
synthetic spectrum matches observed SDSS `ugriz` photometry. Lower values mean
better agreement. Searching parameter combinations for the minimum chi-squared
is the inference step that maps observed light to physical galaxy properties.

## Key Concepts

### Metallicity

In astrophysics, any element heavier than helium is called a "metal."
Metallicity (`Z`) measures how much of this heavy-element content a star has.
Solar metallicity (`Z=0.02`) means roughly 2% of the Sun's mass is in elements
heavier than helium. The first stars in the universe formed with near-zero
metallicity (almost pure hydrogen and helium). As generations of stars form,
evolve, and explode as supernovae, they enrich surrounding gas with heavier
elements. So metallicity tracks chemical evolution: sub-solar metallicity often
indicates an older or less chemically evolved population, while super-solar
metallicity suggests stars formed from already-enriched gas.

### Initial Mass Function (IMF)

When gas clouds collapse, they do not produce stars all at one mass. The IMF
describes the distribution of stellar masses formed in a star formation event.
Kroupa (2001) and Salpeter (1955) are two commonly used empirical IMF models.
Massive stars are rare but dominate emitted light; low-mass stars are numerous
but contribute much less light. Because of this, IMF choice changes both the
luminosity scaling of a synthetic population and how quickly that population
evolves over time.

### Star Formation History (SFH)

Galaxies generally do not form all stars in a single instant. SFH describes how
star formation rate varies with time. An exponential-decay SFH means strong
early star formation that declines later, typical of passive ellipticals. A
constant SFH means ongoing star formation at a steady rate, typical of many
late-type spirals. A burst SFH represents a short, intense star-forming episode
at a specific epoch, often associated with merger-driven starbursts.

### Isochrone

An isochrone is a curve on the Hertzsprung-Russell (HR) diagram showing where
stars of different masses lie at one fixed age and metallicity. In population
synthesis, isochrones are used to estimate how hot and how luminous each star
is at the observation epoch. StellarPop uses the MIST v1.2 grid (Choi et al.
2016) for this age/metallicity-dependent stellar evolution information.

### Stellar Spectral Library

A stellar spectral library is a dataset of precomputed stellar spectra spanning
temperature, surface gravity, and metallicity. BaSeL 3.1 provides semi-empirical
stellar spectra recalibrated against observed photometry, which generally gives
more realistic spectral shapes than a pure Planck blackbody curve (which does
not include absorption features).

### Chi-Squared

Chi-squared is a fit-quality metric that quantifies how closely the synthetic
spectrum matches observed photometry. It is computed as the sum of squared
differences between synthetic and observed fluxes in each SDSS band, normalized
by observed flux. Lower chi-squared means better agreement. Minimizing this
value across parameter combinations is the inference step that maps observed
light to physical quantities such as age and metallicity.

### SDSS ugriz Filters

The Sloan Digital Sky Survey uses five broadband filters centered near 354nm
(`u`), 477nm (`g`), 623nm (`r`), 763nm (`i`), and 913nm (`z`). Each filter
measures total flux through a specific wavelength window. Filter convolution
means integrating the synthetic spectrum against each filter transmission curve
so synthetic and observed photometry are compared on the same basis.

### Age

In StellarPop, age refers to stellar population age in gigayears (Gyr; billions
of years). A 10 Gyr population means most stars formed about 10 billion years
ago. This is distinct from the age of the universe (~13.8 Gyr): it describes
when star formation occurred in the specific galaxy being modeled.

### Wavelength Range

Wavelength range is the spectral interval (in nanometers) used to compute the
synthetic spectrum. Wider ranges include more features but increase computation.
The optical window (350-900nm) covers the SDSS `ugriz` bands and many key
diagnostic stellar-population features.

### Spectral Energy Distribution (SED)

A spectral energy distribution (SED) is flux as a function of wavelength. The
composite spectrum produced by StellarPop is a model SED: predicted integrated
light from the whole stellar population, combining contributions from all stars
weighted by IMF, SFH, and isochrone-based evolution corrections.

## Why SPS Matters

Stellar population synthesis (SPS) is used to infer unresolved stellar content
from integrated galaxy light. Instead of observing individual stars, astronomers
model the combined spectrum or broadband photometry of entire galaxies and
estimate the underlying stellar age distribution, star formation history,
metallicity, and total stellar mass.

SPS is widely used in observational and survey astronomy (for example SDSS,
HST, JWST, and Euclid) to:

- estimate stellar masses across cosmic time,
- infer when galaxies formed most of their stars,
- track metallicity evolution with redshift,
- classify star-forming versus quiescent systems,
- and support photometric-redshift calibration workflows.

Cosmology and instrumentation workflows also consume SPS outputs, including
large-scale structure modeling and exposure-time planning.

## Where StellarPop Fits

Established SPS toolchains such as FSPS, PEGASE, and BC03 are scientifically
powerful, but are typically code-first workflows in Python/Fortran ecosystems.
StellarPop focuses on a complementary mode: a deployable web application with a
browser UI, asynchronous pipeline execution, and version-controlled,
reproducible runs.

The blackboard architecture keeps the pipeline modular: IMF, SFH, spectral
source, and correction models can be swapped independently without rewriting
the orchestration layer.

## Current Limitations

The current physics model is intentionally simplified compared with production
SPS frameworks. In particular, StellarPop does not yet include full
state-of-the-art isochrone tracks (for example Padova or MIST). Stabilizing
and validating the BaSeL-based workflow is a prerequisite before deeper
isochrone upgrades.

## Scientific Background

This project models stellar populations using core components:

- **Initial Mass Function (IMF):** Samples stellar masses from a distribution
  (`kroupa` piecewise, `salpeter` single power law, or `chabrier` lognormal+power law) to represent how stars
  are born across mass.
- **Stellar Spectra:** Generates spectral energy distributions using the BaSeL 3.1
  semi-empirical stellar spectral library (Westera et al. 2002, A&A 381, 524),
  covering 1963 wavelength points from 91 Angstroms to 160 micrometers across
  OBAFGKM spectral types.
- **Isochrones:** Applies age and metallicity evolution corrections, including
  main-sequence lifetime transitions and post-main-sequence behavior.
- **Star Formation History (SFH):** Weights contributions across stellar ages
  using constant, exponential-decay, delayed-exponential, or burst-like models,
  with burst age/width exposed in the UI and passed through to pipeline weighting.
- **BaSeL 3.1 Spectral Library:** Loads and queries the BaSeL grid from
  binary tables using pure Ruby parsing (Fortran column-major indexing and
  sentinel filtering), providing the primary stellar SED source.

The pipeline can also compare synthetic output to observed SDSS `ugriz`
photometry and compute a simple chi-squared fit metric.

## Architecture

StellarPop follows a **blackboard pattern**:

- A shared blackboard holds intermediate and final synthesis context.
- Specialized knowledge sources contribute independent domain computations.
- A synthesis pipeline orchestrates steps and combines outputs.

### Core Modules

- External gem: `fits_parser` (FITS HDU/BINTABLE parsing used by `fits:*` rake workflows)
- `StellarPop::KnowledgeSources::ImfSampler`
- `StellarPop::KnowledgeSources::StellarSpectra`
- `StellarPop::KnowledgeSources::Isochrone`
- `StellarPop::KnowledgeSources::MistIsochrone`
- `StellarPop::KnowledgeSources::SfhModel`
- `StellarPop::KnowledgeSources::BaselSpectra`
- `StellarPop::Integrator::SpectralIntegrator`
- `StellarPop::SdssFilterConvolver` (SDSS ugriz filter-weighted synthetic fluxes)
- `StellarPop::StellarMassEstimator` (run-level stellar mass estimator from IMF/SFH + observed `r` magnitude + redshift distance)
- `Galaxy` (SQLite-backed SDSS photometry/provenance records with `sdss_objid`, `mag_type`, and separate `petro_*` / `model_*` magnitude columns)
- `StellarPop::SdssClient` (Faraday-based SDSS SkyServer SQL client with configurable dataset release `DR18`/`DR19`, default `DR19`)
- `SynthesisPipelineJob` (async orchestration + persistence)
- `GridFitJob` (1050-combination parameter sweep + ranked inference output)
- `CalibrationRunJob` (benchmark calibration checks against published science targets)

### Pipeline Flow

1. A `SynthesisRun` is created in the web UI with status `pending`.
2. `SynthesisPipelineJob` is enqueued (`perform_later`) on the `synthesis` queue.
3. The job sets status `running`, builds a blackboard, samples IMF masses, computes SFH weights, applies a user-configurable wavelength range (`wavelength_min..wavelength_max`, 300-1100nm, default 350-900nm), and runs the spectral integrator.
4. The integrator writes `:composite_spectrum` to the blackboard.
5. The job saves a `SpectrumResult` (wavelength/flux JSON).
6. If SDSS target metadata is present, the job resolves `ugriz` photometry using local-first lookup:
   - first `galaxies` table records in SQLite
   - fallback to live SDSS API (`SdssClient`) if local DB lookup misses
   - live fetch is objid-first (`fetch_photometry_by_objid`) for runtime/catalog refresh; coordinate fallback is retained for maintenance utilities
   Then applies redshift k-corrections to observed magnitudes and computes chi-squared via SDSS filter convolution, and stores:
   - `SpectrumResult.sdss_photometry` (JSON)
   - `SynthesisRun.chi_squared`
   - `SynthesisRun.stellar_mass` (estimated stellar mass in solar-mass units)
   - informational source/fetch note in `SynthesisRun.error_message` for complete runs
7. The run is marked `complete` (or `failed` with `error_message` on exceptions).

### Integrator Notes

`StellarPop::Integrator::SpectralIntegrator` currently:

- Reads IMF masses, age bins, SFH weights, metallicity, and wavelength range from blackboard.
- Builds per-star spectra from either `BaselSpectra` or `StellarSpectra` (Planck), based on run `spectra_model`; when BaSeL is selected, `metallicity_z` is passed through for nearest-bin BaSeL metallicity selection.
- Normalizes each star spectrum by unit integral over the wavelength grid.
- Uses two-pass luminosity weights from `MistIsochrone` (Choi et al. 2016) via `luminosity_solar`, with fallback to `mass ** 1.0` for out-of-grid stars, then normalizes weights to sum to `1.0`; `metallicity_z` is also passed through to MIST nearest-[Fe/H] selection.
- Interpolates all stellar spectra onto a fixed 5.0nm grid over `wavelength_range`.
- Applies 11-point boxcar smoothing to the composite before final scaling.
- Normalizes final peak flux to `1.0`.

## Getting Started

```bash
git clone https://github.com/unixneo/stellar_pop.git
cd stellar_pop
bundle install
bin/rails db:migrate
```

Run web + worker:

```bash
bin/rails server
bundle exec sidekiq -C config/sidekiq.yml
```

Then open `http://localhost:3000`.

## Usage

### SynthesisRuns Web Interface

- `/` shows all runs in a status-colored table.
- `/synthesis_runs/new` creates a new run and enqueues processing.
  - includes an SDSS toggle to enable/disable photometry fetch + chi-squared
  - includes a local SDSS catalog target selector that auto-fills RA/Dec
  - supports optional manual RA/Dec entry for advanced use
  - auto-generates a compact run name from selected parameters (editable)
  - includes a spectra model selector (`basel` or `planck`)
  - includes wavelength range fields (`wavelength_min`, `wavelength_max`)
  - includes burst SFH controls (`burst_age_gyr`, `burst_width_gyr`) that appear when `sfh_model=burst`
- `/synthesis_runs/:id` shows:
  - animated pending/running banner with pre-load messaging and a live elapsed timer
  - run parameters and status
  - wavelength range (`min-max nm`)
  - pipeline configuration (active spectra library, IMF, MIST isochrone weighting, SFH model, and chi-squared method)
  - explicit SDSS source/failure note (local hit, live API hit, timeout, unreachable API, or no object found)
  - canvas-based spectrum viewer
  - chi-squared (if available)
  - estimated stellar mass (if available)
  - composite spectrum table
  - SDSS `ugriz` photometry table (if fetched)
- `/synthesis_runs/seed_test` creates a randomized test run (unique name, randomized model parameters, random local SDSS target).
- `/pipeline_config/edit` provides a centralized configuration page for runtime pipeline constants (sample sizes, age grids, SFH taus, wavelength defaults, retry/backoff, and benchmark fast-mode profiles).
- `/pipeline_config/edit` also controls active SDSS dataset release (`DR18` or `DR19`), with `DR19` as default.
- `/pipeline_config/edit` also controls active SDSS magnitude type (`petrosian` or `model`), which determines which `mag_u..mag_z` values feed chi-squared comparisons.
- `/sidekiq` exposes Sidekiq Web UI.
- Navbar includes a dynamic git-derived version badge (e.g., `v0.3.0-4-g<sha>`) and a Sidekiq status dot (green=online, red=offline).

### Parameter Grid Fitting

- Visit `/grid_fits/new` and enter galaxy coordinates.
- The pipeline automatically sweeps 1050 parameter combinations:
  10 ages (`[0.01, 0.05, 0.1, 0.5, 1.0, 3.0, 5.0, 8.0, 10.0, 12.0]` Gyr)
  × 5 metallicities × 3 IMFs × (3 non-burst SFH models + 4 burst-age variants).
- For `sfh_model=burst`, the burst center is configurable via `burst_age_gyr`
  and swept on `[0.1, 0.5, 1.0, 2.0]` Gyr.
- Results are ranked by chi-squared.
- Best-fit age, metallicity, and SFH are identified automatically.
- This is the primary scientific use case: infer physical galaxy properties
  from observed photometry through systematic model comparison.

### Calibration Benchmarks

- Visit `/calibration_runs/new` to run benchmark calibration checks.
  - benchmark target selection is filtered to the active SDSS release configured in pipeline settings.
- Benchmarks are selectable per run (none preselected by default), currently including:
  `NGC3379`, `M101`, `M87`, and `NGC4459`, each with fixed reference photometry
  and literature-backed expected physical ranges.
- Observation records now include a wider literature-backed set (16 galaxies with published sources), used for benchmark metadata and reference context.
- Runs support `fast` mode (reduced grid) or `full` mode (full benchmark grid).
- Calibration executes the configured sweep for each selected benchmark and stores:
  - pass/warn/fail verdicts for age/metallicity/SFH-class checks
  - best-fit parameters and top ranked solutions
  - summary counts across all benchmarks
- `/calibration_runs/:id` includes a dedicated progress panel (separate from the top status banner) with completed/total combinations, current benchmark step, and ETA.
- Benchmark index/show pages display run mode and runtime in seconds.

## Scientific Results

First grid-fit results on local SDSS targets show physically plausible trends:

- `M101` best fit: age `0.1` Gyr, `Z=0.0063`, exponential SFH; consistent with
  a young, star-forming spiral population.
- `NGC3379` best fit: age `8-10` Gyr, near-solar `Z`, consistent with published
  old-population constraints for this elliptical after DR19 objid-based
  photometry correction.
- Synthetic `g-r` colors now span approximately `-0.44` (young `0.01` Gyr) to
  `+0.65` (old `12` Gyr), consistent with the observed galaxy color range.

### Rails Console Access

You can interact directly with knowledge sources:

```ruby
imf = StellarPop::KnowledgeSources::ImfSampler.new(seed: 42)
masses = imf.sample(1000)
counts = imf.count_by_type(masses)

spectra = StellarPop::KnowledgeSources::StellarSpectra.new
g_spectrum = spectra.spectrum("G", 350..900)

basel = StellarPop::KnowledgeSources::BaselSpectra.new
library_spectrum = basel.spectrum_for_mass(1.0, 300.0..1000.0)

iso = StellarPop::KnowledgeSources::Isochrone.new
flux_scale = iso.luminosity_correction(1.0, 5.0, 0.02)
delta_t = iso.temperature_correction(1.0, 0.03)

sfh = StellarPop::KnowledgeSources::SfhModel.new
w = sfh.weights(:exponential, [0.1, 1.0, 5.0, 10.0], tau: 3.0)

conv = StellarPop::SdssFilterConvolver.new
synthetic = conv.synthetic_magnitudes(library_spectrum)

local_phot = Galaxy.find_by(name: "3C273")&.slice("mag_u", "mag_g", "mag_r", "mag_i", "mag_z", "redshift_z")

client = StellarPop::SdssClient.new
phot = client.fetch_photometry(187.2779, 2.0523)
```

## Tech Stack

- Ruby on Rails 7.1
- SQLite3
- Sidekiq
- Faraday
- Pure Ruby astrophysics pipeline (no external code libraries)
- BaSeL 3.1 stellar spectral library (Westera et al. 2002) — binary data files

## Data Sources

- BaSeL 3.1 stellar spectral energy distribution library (Westera, Lejeune,
  Buser, Cuisinier & Bruzual 2002, A&A 381, 524) — all six metallicity
  bins active via zlegend nearest-bin selection:
  z=0.0002, 0.0006, 0.0020, 0.0063, 0.0200, 0.0632; spectra sourced
  from the FSPS repository (Conroy et al.)
- MIST isochrone grid v1.2 (Choi et al. 2016, ApJ 823, 102) — all 12 FSPS
  metallicity grids with nearest-[Fe/H] selection from `metallicity_z`
- Local SDSS photometry records persisted in the SQLite `galaxies` table (DB-backed source of truth for this app)
- Local SDSS records include both `petro_*` and `model_*` photometry per band, with active `mag_u..mag_z` populated from the configured pipeline `mag_type`.
- SDSS SkyServer DR18/DR19 — observed photometry via public SQL API (release configurable in pipeline settings; default DR19)

## Citation

If you use StellarPop, cite the software DOI:
https://doi.org/10.5281/zenodo.19277971

## Milestone Validation

Recent end-to-end validation with local-catalog photometry produced a
physically plausible comparative result:

- SDSS target matched and displayed: `NGC3379` (Leo group elliptical)
- Chi-squared for NGC3379 old-population run: `9174.20`
- Reference quasar case (3C 273): `80180` (substantially worse fit)
- Run configuration: burst SFH, 12 Gyr, Salpeter IMF
- Composite spectrum peak near `~525 nm` with structured shape
- Salpeter IMF sampling and burst SFH parameter pass-through are active in pipeline runs

Interpretation: the lower chi-squared for a passive elliptical under an old
single-burst population is consistent with expected SPS behavior.

## Note

This project is presented as the first known implementation of stellar
population synthesis in Ruby on Rails.
