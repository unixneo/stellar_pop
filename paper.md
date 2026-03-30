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
date: 2026-03-30
bibliography: paper.bib
---

# Summary

StellarPop is a web-based stellar population synthesis pipeline implemented in Ruby on Rails using a blackboard architecture. It is the first known implementation of stellar population synthesis in this language and framework. The system coordinates pure-Ruby knowledge sources via a shared blackboard to produce composite spectra from user-defined parameters: an initial mass function (IMF) sampler, stellar spectra generator, isochrone correction module, star formation history (SFH) model, and a BaSeL 3.1 spectral library parser. Runs can select either a BaSeL-library spectral source or a Planck-based spectral source. In addition to synthetic modeling, StellarPop resolves SDSS photometry via a local reference catalog with live API fallback and computes chi-squared goodness of fit against synthetic spectra. SDSS dataset release selection is configurable (`DR18`/`DR19`) in the pipeline configuration UI, with `DR19` as the default. The v0.3.3 update also standardizes objid-based SDSS fetches for runtime/catalog refresh, keeps both Petrosian and model photometry per galaxy under `mag_type` control, expands literature-backed observation coverage, and adds synthesis-run stellar-mass estimation from best-fit SFH/IMF plus observed `r`-band magnitude and redshift-based luminosity distance.

# Statement of need

Existing stellar population synthesis tools such as FSPS, SLUG, and galIMF are primarily implemented in Python or Fortran. StellarPop provides a self-contained web application with no external astronomy library dependencies, making it accessible to researchers and developers who want a deployable end-to-end pipeline with a browser interface, asynchronous job processing via Sidekiq, and a SQLite database that can be version-controlled and shared via GitHub for reproducible workflows. Automated parameter-grid fitting is a key capability: instead of manual one-off runs, users can execute a full parameter sweep and rank models by fit quality in one reproducible workflow.

# Implementation

StellarPop uses a blackboard pattern in which all intermediate and final values are written to and read from a shared data structure. This architecture enables loose coupling between the scientific components and job orchestration logic.

The pipeline is organized around knowledge sources:

1. **IMF Sampler**: Implements Kroupa, Salpeter, and Chabrier IMFs with inverse-transform/rejection-based mass sampling.
2. **Stellar Spectra**: Supports two selectable spectral sources: BaSeL 3.1 stellar spectral library lookup and Planck-based spectral generation by spectral type.
3. **Isochrone Corrections**: Uses the MIST isochrone grid (Choi et al. 2016) parsed directly from FSPS repository data files for luminosity weighting, with simple analytic corrections retained for comparison/validation workflows.
4. **SFH Model**: Provides exponential, delayed-exponential, constant, and burst star formation history weight functions, with burst age/width parameters exposed through the web UI and persisted per run.
5. **BaSeL Spectra**: Parses BaSeL 3.1 binary spectral grids in pure Ruby with class-level memoization, Fortran column-major indexing, and sentinel-value filtering for robust library-based spectral retrieval. All six BaSeL metallicity planes are active with nearest-bin selection using zlegend values [0.0002, 0.0006, 0.0020, 0.0063, 0.0200, 0.0632].

Asynchronous execution is handled by Sidekiq through a dedicated synthesis queue. Each synthesis run is persisted in Rails models, executed in a background job, and stored as a composite spectrum in the database. During integration, per-star spectra are interpolated onto a user-configurable wavelength grid (300-1100nm, default 350-900nm), combined with IMF/SFH weighting and MIST-derived luminosity weighting from FSPS-sourced isochrone tables, and smoothed before final normalization. BaSeL spectral lookup and MIST isochrone weighting now use consistent per-run metallicity selection derived from `metallicity_z`. For observational comparison, StellarPop first checks local SDSS photometry in SQLite and falls back to the configured SDSS SkyServer release (`DR18`/`DR19`, default `DR19`) on misses. Runtime and catalog refresh fetches use objid-based SDSS lookup when `sdss_objid` is available, replacing coordinate-first lookup in normal workflows (coordinate fallback remains for maintenance utilities). The `galaxies` table stores both Petrosian and model photometry (`petro_*`, `model_*`) and tracks active photometry provenance through `mag_type`. Pipeline configuration now includes a `mag_type` preference (`petrosian`/`model`) that determines which magnitude set is promoted into active `mag_u..mag_z` values used for chi-squared fitting. Chi-squared is computed using SDSS filter-convolved synthetic fluxes (ugriz), with redshift k-corrections applied before comparison. After a successful fit, run-level stellar mass is estimated from best-fit SFH/IMF context, observed `r`-band magnitude, and redshift-derived luminosity distance, then persisted in `synthesis_runs.stellar_mass` for UI display and downstream analysis.

Three pipeline fixes were required to recover physically correct color behavior: (1) BaSeL binary parsing was corrected from big-endian (`g*`) to little-endian (`e*`) unpacking; (2) spectral lookup now uses MIST-evolved `teff/logg` per star instead of a mass-only mapping; and (3) chi-squared moved to magnitude-space color comparison normalized to `r`-band, reducing scale artifacts in photometric fitting.

Recent usability and provenance updates focused on reproducible interpretation: local SDSS catalog entries now carry `agn` and `sdss_dr` metadata, the run form defaults to catalog-driven target selection with RA/Dec autofill (manual override optional), and run notes now distinguish SDSS failure causes (no object found vs API timeout vs unreachable API) instead of using a single ambiguous message.

## Grid fitting

StellarPop includes a parameter-grid sweep workflow over 1050 model combinations. The age grid is `[0.01, 0.05, 0.1, 0.5, 1.0, 3.0, 5.0, 8.0, 10.0, 12.0]` Gyr, with 5 metallicities and 3 IMF choices across SFH models. For burst SFH runs, the burst center is additionally swept through `burst_age_gyr = [0.1, 0.5, 1.0, 2.0]` Gyr, increasing total combinations and improving sensitivity to bursty star formation at different epochs. For each combination, the pipeline generates a synthetic spectrum and computes chi-squared against observed SDSS photometry. Results are sorted by chi-squared, and the best-fit age, metallicity, SFH, and IMF are recorded automatically. This ranking-based sweep is the primary inference mechanism for deriving physical galaxy properties from observed photometry.

## Calibration workflow

StellarPop now includes a benchmark calibration workflow (`CalibrationRun`) that executes the grid-fitting pipeline against reference galaxies with expected physical ranges. Benchmark targets are selectable per run from the observation-backed galaxy set filtered to the active SDSS dataset release, with a `full` profile (complete sweep) and a `fast` profile (reduced sweep) for quicker turnaround. Literature observations were updated for 16 galaxies with published sources in the v0.3.3 provenance refresh. Each calibration run records benchmark-specific best fits, top-ranked alternatives, and pass/warn/fail checks for age, metallicity, and SFH class agreement. A dedicated progress panel reports completed combinations, active benchmark step, and estimated remaining runtime while the calibration job is running.

## Results

First grid-fit results show plausible astrophysical behavior and known photometric fitting limits. For M101, the best fit was age `0.1` Gyr, metallicity `Z=0.0063`, and exponential SFH, consistent with a young star-forming spiral. For NGC3379, corrected DR19 objid-based photometry yields old-population best fits in the `8-10` Gyr range with near-solar metallicity, consistent with published constraints. After the pipeline fixes, synthetic `g-r` colors span approximately `-0.44` (young `0.01` Gyr) to `+0.65` (old `12` Gyr), covering the observed galaxy color range and restoring physically correct age dependence.

To reduce interpretation burden for non-specialists, Grid Fit outputs now include a deterministic plain-language summary generated from the best-fit parameters (age class, enrichment level, SFH interpretation, and qualitative fit-strength bucket from chi-squared), without requiring any LLM dependency.

## Validation Against Published Results

For NGC3379, published spectroscopic measurements from Terlevich & Forbes (2002) report age `9.3` Gyr and `[Fe/H]=+0.16`, and HST NICMOS resolved-population measurements from Gregg et al. (2004) find ages `>8` Gyr with mean metallicity around solar in outer regions. StellarPop now returns best-fit ages in the `8-10` Gyr range with near-solar metallicity (`Z~0.02`) after the DR19 objid-based photometry correction. This aligns the inferred age regime with published results while retaining the expected broadband age-metallicity degeneracy envelope in nearby ranked solutions.

This behavior is consistent with the known age-metallicity degeneracy in broadband photometric SPS fitting. As described by Worthey (1994), the "3/2 rule" implies that increasing age by a factor of three is approximately degenerate with increasing metallicity by a factor of two in broadband colors. Breaking this degeneracy generally requires additional constraints such as UV coverage (`u`-band or shorter) or spectroscopic line indices (e.g., Balmer absorption), which are not fully available in ugriz-only photometric fitting. This is a fundamental limitation of the problem class rather than a StellarPop-specific artifact.

For M101, a well-known actively star-forming late-type spiral, StellarPop returns best-fit age `0.1` Gyr, `Z=0.0063`, and exponential SFH. This is physically consistent with a young, sub-solar metallicity population dominated by recently formed stars and aligns with M101's established star-forming classification.

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

Terlevich, A. I., & Forbes, D. A. (2002). A catalogue and analysis of ages and metallicities for Galactic globular clusters and nearby galaxies. *Monthly Notices of the Royal Astronomical Society, 330*(2), 547-558.

Gregg, M. D., Ferguson, H. C., Minniti, D., Tanvir, N., & Catchpole, R. (2004). The Stellar Population of the Elliptical Galaxy NGC 3379. *The Astronomical Journal, 127*(3), 1441-1454.

Worthey, G. (1994). Comprehensive stellar population models and the disentanglement of age and metallicity effects. *The Astrophysical Journal Supplement Series, 95*, 107-149.
