# StellarPop

## Project Overview

StellarPop is a Ruby on Rails stellar population synthesis application built as
a blackboard-style pipeline. The system coordinates multiple physics-focused
knowledge sources to synthesize composite stellar population outputs from user
inputs. Core astrophysics logic is implemented in pure Ruby.

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

## Architecture

StellarPop follows a **blackboard pattern**:

- A shared blackboard holds intermediate and final synthesis context.
- Specialized knowledge sources contribute independent domain computations.
- A synthesis pipeline orchestrates steps and combines outputs.

Knowledge sources currently implemented:

- `StellarPop::KnowledgeSources::ImfSampler`
- `StellarPop::KnowledgeSources::StellarSpectra`
- `StellarPop::KnowledgeSources::Isochrone`
- `StellarPop::KnowledgeSources::SfhModel`

## Getting Started

```bash
git clone https://github.com/unixneo/stellar_pop.git
cd stellar_pop
bundle install
bin/rails db:migrate
bin/rails server
```

Then open `http://localhost:3000`.

## Usage

### SynthesisRuns Web Interface

- Visit `/` to access `SynthesisRuns#index`.
- Create a synthesis run from `/synthesis_runs/new` with IMF, age, metallicity,
  and SFH inputs.
- Inspect individual runs at `/synthesis_runs/:id`.
- Sidekiq dashboard is available at `/sidekiq`.

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
```

## Tech Stack

- Ruby on Rails 7.1
- SQLite3
- Sidekiq
- Pure Ruby astrophysics/physics modules
- No external astronomy libraries

## Note

This project is presented as the first known implementation of stellar
population synthesis in Ruby on Rails.
