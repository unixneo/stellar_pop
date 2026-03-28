# StellarPop

[![DOI](https://zenodo.org/badge/DOI/10.5281/zenodo.19274470.svg)](https://doi.org/10.5281/zenodo.19274470)

## What This App Does

StellarPop is a Ruby on Rails application that generates a synthetic stellar
population spectrum from user-defined astrophysical inputs (IMF, age, metallicity,
and SFH model). It runs an async pipeline, persists the resulting spectrum, and
optionally compares synthetic output against SDSS `ugriz` photometry using a
chi-squared metric.

## Why This App Exists

The goal is to show that a practical stellar population synthesis workflow can be
implemented end-to-end in Ruby on Rails, with:

- domain logic in pure Ruby,
- transparent pipeline orchestration via a blackboard pattern,
- reproducible async processing via Sidekiq jobs,
- and an inspectable web UI for runs, spectra, and fit quality.

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
  (Kroupa-like piecewise power law) to represent how stars are born across mass.
- **Stellar Spectra:** Generates spectral energy distributions using the BaSeL 3.1
  semi-empirical stellar spectral library (Westera et al. 2002, A&A 381, 524),
  covering 1963 wavelength points from 91 Angstroms to 160 micrometers across
  OBAFGKM spectral types.
- **Isochrones:** Applies age and metallicity evolution corrections, including
  main-sequence lifetime transitions and post-main-sequence behavior.
- **Star Formation History (SFH):** Weights contributions across stellar ages
  using constant, exponential-decay, or burst-like models.
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

- `StellarPop::KnowledgeSources::ImfSampler`
- `StellarPop::KnowledgeSources::StellarSpectra`
- `StellarPop::KnowledgeSources::Isochrone`
- `StellarPop::KnowledgeSources::SfhModel`
- `StellarPop::KnowledgeSources::BaselSpectra`
- `StellarPop::Integrator::SpectralIntegrator`
- `StellarPop::SdssFilterConvolver` (SDSS ugriz filter-weighted synthetic fluxes)
- `StellarPop::SdssLocalCatalog` (local SDSS photometry lookup from curated CSV)
- `StellarPop::SdssClient` (Faraday-based SDSS SkyServer DR18 SQL client)
- `SynthesisPipelineJob` (async orchestration + persistence)

### Pipeline Flow

1. A `SynthesisRun` is created in the web UI with status `pending`.
2. `SynthesisPipelineJob` is enqueued (`perform_later`) on the `synthesis` queue.
3. The job sets status `running`, builds a blackboard, samples IMF masses, computes SFH weights, and runs the spectral integrator.
4. The integrator writes `:composite_spectrum` to the blackboard.
5. The job saves a `SpectrumResult` (wavelength/flux JSON).
6. If SDSS coordinates are present, the job resolves `ugriz` photometry using local-first lookup:
   - first `SdssLocalCatalog` (`lib/data/sdss/photometry.csv`)
   - fallback to live SDSS API (`SdssClient`) if local lookup misses
   Then computes chi-squared via SDSS filter convolution and stores:
   - `SpectrumResult.sdss_photometry` (JSON)
   - `SynthesisRun.chi_squared`
   - informational source/fetch note in `SynthesisRun.error_message` for complete runs
7. The run is marked `complete` (or `failed` with `error_message` on exceptions).

### Integrator Notes

`StellarPop::Integrator::SpectralIntegrator` currently:

- Reads IMF masses, age bins, SFH weights, metallicity, and wavelength range from blackboard.
- Builds per-star spectra from `BaselSpectra`.
- Normalizes each star spectrum by unit integral over the wavelength grid.
- Uses two-pass mass-based weights (`mass ** 1.0`) normalized to sum to `1.0`.
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
- `/synthesis_runs/:id` shows:
  - animated "Processing synthesis pipeline..." banner for pending/running runs
  - run parameters and status
  - informational SDSS note (local/live/fetch-unavailable) on completed runs
  - canvas-based spectrum viewer
  - chi-squared (if available)
  - composite spectrum table
  - SDSS `ugriz` photometry table (if fetched)
- `/synthesis_runs/seed_test` creates a randomized test run (unique name, randomized model parameters) using fixed 3C 273 coordinates.
- `/sidekiq` exposes Sidekiq Web UI.

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

local_phot = StellarPop::SdssLocalCatalog.lookup(187.2779, 2.0523)

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
  Buser, Cuisinier & Bruzual 2002, A&A 381, 524) — solar metallicity
  spectra sourced from the FSPS repository (Conroy et al.)
- Local SDSS photometry catalog (`lib/data/sdss/photometry.csv`) for well-known reference objects
- SDSS SkyServer DR18 — observed photometry via public SQL API

## Citation

If you use StellarPop, cite the software DOI:
https://doi.org/10.5281/zenodo.19274470

## Note

This project is presented as the first known implementation of stellar
population synthesis in Ruby on Rails.
