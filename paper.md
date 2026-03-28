---
title: "StellarPop: A Ruby on Rails Stellar Population Synthesis Pipeline Using a Blackboard Architecture"
tags:
  - Ruby
  - Ruby on Rails
  - stellar population synthesis
  - blackboard architecture
  - SDSS
authors:
  - name: Tim Bass
    orcid: "0000-0001-9368-6838"
    affiliation: 1
affiliations:
  - name: Independent Researcher, Bangkok Metropolitan Area
    index: 1
date: 2026-03-28
bibliography: paper.bib
---

# Summary

StellarPop is a web-based stellar population synthesis pipeline implemented in Ruby on Rails using a blackboard architecture. It is the first known implementation of stellar population synthesis in this language and framework. The system coordinates pure-Ruby knowledge sources via a shared blackboard to produce composite spectra from user-defined parameters: an initial mass function (IMF) sampler, stellar spectra generator, isochrone correction module, star formation history (SFH) model, and a BaSeL 3.1 spectral library parser. Runs can select either a BaSeL-library spectral source or a Planck-based spectral source. In addition to synthetic modeling, StellarPop resolves SDSS photometry via a local reference catalog with live API fallback and computes chi-squared goodness of fit against synthetic spectra.

# Statement of need

Existing stellar population synthesis tools such as FSPS, SLUG, and galIMF are primarily implemented in Python or Fortran. StellarPop provides a self-contained web application with no external astronomy library dependencies, making it accessible to researchers and developers who want a deployable end-to-end pipeline with a browser interface, asynchronous job processing via Sidekiq, and a SQLite database that can be version-controlled and shared via GitHub for reproducible workflows.

# Implementation

StellarPop uses a blackboard pattern in which all intermediate and final values are written to and read from a shared data structure. This architecture enables loose coupling between the scientific components and job orchestration logic.

The pipeline is organized around knowledge sources:

1. **IMF Sampler**: Implements both piecewise Kroupa and single-power-law Salpeter IMFs with inverse-transform mass sampling.
2. **Stellar Spectra**: Supports two selectable spectral sources: BaSeL 3.1 stellar spectral library lookup and Planck-based spectral generation by spectral type.
3. **Isochrone Corrections**: Uses the MIST isochrone grid (Choi et al. 2016) parsed directly from FSPS repository data files for luminosity weighting, with simple analytic corrections retained for comparison/validation workflows.
4. **SFH Model**: Provides exponential, constant, and burst star formation history weight functions, with burst age/width parameters exposed through the web UI and persisted per run.
5. **BaSeL Spectra**: Parses BaSeL 3.1 binary spectral grids in pure Ruby with class-level memoization, Fortran column-major indexing, and sentinel-value filtering for robust library-based spectral retrieval.

Asynchronous execution is handled by Sidekiq through a dedicated synthesis queue. Each synthesis run is persisted in Rails models, executed in a background job, and stored as a composite spectrum in the database. During integration, per-star spectra are interpolated onto a user-configurable wavelength grid (300-1100nm, default 350-900nm), combined with IMF/SFH weighting and MIST-derived luminosity weighting from FSPS-sourced isochrone tables, and smoothed before final normalization. For observational comparison, StellarPop first checks a local SDSS photometry catalog keyed by sky position and falls back to the SDSS SkyServer DR18 SQL API on catalog misses. Chi-squared is then computed using SDSS filter-convolved synthetic fluxes (ugriz) rather than nearest-wavelength approximations.

## Isochrone validation

Validation against MIST isochrone tables (Choi et al. 2016) indicates that the simple corrections in `StellarPop::KnowledgeSources::Isochrone` agree with MIST to within 2% for solar-mass stars at ages 1-5 Gyr, but diverge significantly for evolved stars and sub-solar masses. `StellarPop::KnowledgeSources::MistIsochrone` is now active in the synthesis pipeline for luminosity weighting across runs. All 12 MIST metallicity grids are loaded at process start, and the nearest [Fe/H] bin is selected automatically from `metallicity_z` using `feh = log10(metallicity_z / 0.0142)`. The selected [Fe/H] bin is included in run-level provenance displayed in the web UI pipeline configuration section.

# Acknowledgements

None at this time.

# References

Kroupa, P. (2001). On the variation of the initial mass function. *Monthly Notices of the Royal Astronomical Society, 322*(2), 231-246. https://doi.org/10.1046/j.1365-8711.2001.04022.x

Planck Collaboration. (2018). Planck 2018 results. I. Overview, and the cosmological legacy of Planck. *Astronomy & Astrophysics, 641*, A1. https://doi.org/10.1051/0004-6361/201833880

Ahumada, R., Allende Prieto, C., Almeida, A., et al. (2020). The 16th Data Release of the Sloan Digital Sky Surveys: First Release from the APOGEE-2 Southern Survey and Full Release of eBOSS Spectra. *The Astrophysical Journal Supplement Series, 249*(1), 3. https://doi.org/10.3847/1538-4365/ab929e

Choi, J., Dotter, A., Conroy, C., Cantiello, M., Paxton, B., & Johnson, B. D. (2016). MESA Isochrones and Stellar Tracks (MIST). I. Solar-scaled Models. *The Astrophysical Journal, 823*(2), 102. https://doi.org/10.3847/0004-637X/823/2/102

Bass, T. (2026). Blackboard SA. *ACM DTRAP* (under review). Preprint: https://doi.org/10.5281/zenodo.18824512

Bass, T. (2026). StellarPop (Version 0.2.0) [Software]. Zenodo. https://doi.org/10.5281/zenodo.19277971
