# StellarPop

## Project Overview

StellarPop is a Ruby on Rails stellar population synthesis application built as
a blackboard-style pipeline. The system coordinates multiple physics-focused
knowledge sources to synthesize composite stellar population outputs from user inputs.
Core astrophysics logic is implemented in pure Ruby, and pipeline execution runs
asynchronously via Sidekiq jobs.

## Scientific Background

This project models stellar populations using four core components:

- **Initial Mass Function (IMF):** Samples stellar masses from a distribution
  (Kroupa-like piecewise power law) to represent how stars are born across mass.
- **Stellar Spectra:** Generates representative spectral energy distributions
  by spectral class using Planck-law radiance.
- **Isochrones:** Applies age and metallicity evolution corrections, including
  main-sequence lifetime transitions and post-main-sequence behavior.
- **Star Formation History (SFH):** Weights contributions across stellar ages
  using constant, exponential-decay, or burst-like models.

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
- `StellarPop::Integrator::SpectralIntegrator`
- `StellarPop::SdssClient` (Faraday-based SDSS SkyServer DR18 SQL client)
- `SynthesisPipelineJob` (async orchestration + persistence)

### Pipeline Flow

1. A `SynthesisRun` is created in the web UI with status `pending`.
2. `SynthesisPipelineJob` is enqueued (`perform_later`) on the `synthesis` queue.
3. The job sets status `running`, builds a blackboard, samples IMF masses, computes SFH weights, and runs the spectral integrator.
4. The integrator writes `:composite_spectrum` to the blackboard.
5. The job saves a `SpectrumResult` (wavelength/flux JSON).
6. If SDSS coordinates are present, the job fetches `ugriz` photometry, computes chi-squared, and stores:
   - `SpectrumResult.sdss_photometry` (JSON)
   - `SynthesisRun.chi_squared`
7. The run is marked `complete` (or `failed` with `error_message` on exceptions).

### Integrator Notes

`StellarPop::Integrator::SpectralIntegrator` currently:

- Reads IMF masses, age bins, SFH weights, metallicity, and wavelength range from blackboard.
- Builds per-star spectra with temperature correction.
- Normalizes each star spectrum by unit integral over the wavelength grid.
- Uses two-pass mass-based weights (`mass ** 1.0`) normalized to sum to `1.0`.
- Accumulates into a composite spectrum and normalizes final peak flux to `1.0`.

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
- `/synthesis_runs/:id` shows:
  - run parameters and status
  - chi-squared (if available)
  - composite spectrum table
  - SDSS `ugriz` photometry table (if fetched)
- `/synthesis_runs/seed_test` creates a prefilled test run using 3C 273 coordinates.
- `/sidekiq` exposes Sidekiq Web UI.

### Rails Console Access

You can interact directly with knowledge sources:

```ruby
imf = StellarPop::KnowledgeSources::ImfSampler.new(seed: 42)
masses = imf.sample(1000)
counts = imf.count_by_type(masses)

spectra = StellarPop::KnowledgeSources::StellarSpectra.new
g_spectrum = spectra.spectrum("G", 350..900)

iso = StellarPop::KnowledgeSources::Isochrone.new
flux_scale = iso.luminosity_correction(1.0, 5.0, 0.02)
delta_t = iso.temperature_correction(1.0, 0.03)

sfh = StellarPop::KnowledgeSources::SfhModel.new
w = sfh.weights(:exponential, [0.1, 1.0, 5.0, 10.0], tau: 3.0)

client = StellarPop::SdssClient.new
phot = client.fetch_photometry(187.2779, 2.0523)
```

## Tech Stack

- Ruby on Rails 7.1
- SQLite3
- Sidekiq
- Faraday
- Pure Ruby astrophysics/physics modules
- No external astronomy libraries

## Note

This project is presented as the first known implementation of stellar
population synthesis in Ruby on Rails.
