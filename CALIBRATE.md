# Calibration Plan

## Goal

Bring StellarPop benchmark outputs into stable agreement with trusted observation references by calibrating the highest-impact model and data-handling components in a controlled sequence.

Primary target:
- achieve reproducible improvement on a fixed benchmark subset first, then scale to larger samples.

## Scope

This plan focuses on the current benchmark outputs:
- age (Gyr)
- metallicity (Z)
- stellar mass (Msun)
- fit quality (chi-squared)

Out of scope for this phase:
- adding new physics metrics (e.g., SFR) before age/Z/mass calibration is stable.

## Calibration Principles

1. Freeze inputs while calibrating:
- freeze galaxy subset, observation rows, and redshift provenance policy for each run.

2. One moving part at a time:
- do not tune filter calibration, M/L scaling, and interpolation logic in the same step.

3. Keep train/holdout split:
- tune on train galaxies; evaluate on holdout galaxies.

4. Every run must emit artifacts:
- JSON output with parameters, metrics, and provenance for reproducibility.

## Phase 0: Baseline and Dataset Freeze

Objective:
- define a locked baseline to measure improvement against.

Steps:
1. Select calibration subset (start small):
- train: 3-5 galaxies with strongest references.
- holdout: 3-5 galaxies not used in tuning.

2. Freeze benchmark inputs:
- `observations` rows for selected galaxies.
- active redshift confidence policy in config.
- active photometry selection policy.

3. Run baseline fast benchmarks:
- one report JSON for train
- one report JSON for holdout

Exit criteria:
- baseline report artifacts committed and timestamped.

## Current Benchmark Readiness (2026-04-03)

Usable benchmark galaxies right now: 7

Tier 1 (run first):
- NGC4660
- NGC4564
- NGC4570
- NGC4387

Tier 2 (usable after Tier 1):
- NGC4339
- NGC4350

Tier 3 (usable with caveat):
- NGC4365 (known high-age outlier; interpret cautiously)

Not usable yet (missing reliable SDSS objid linkage):
- NGC4452
- NGC4474
- NGC4483

Immediate execution order:
1. Run fast benchmarks on Tier 1 only.
2. Export JSON deltas for age/Z/mass against observations.
3. Promote Tier 2 only after Tier 1 residuals are stable.

## Phase 1: Filter Calibration Parity (Highest Priority)

Objective:
- ensure synthetic photometry uses the same photometric system assumptions as reference papers.

Checks:
1. SDSS filter response handling:
- transmission files and wavelength units
- integration convention
- magnitude system consistency

2. Zeropoint parity:
- confirm identical zeropoint assumptions for observed and synthetic magnitudes.

3. Regression fixture:
- add a small fixture test with known expected band flux/magnitude outputs.

Tuning:
- only filter/photometric conversion logic in this phase.

Exit criteria:
- reduced systematic color residuals on train set.
- no regression on holdout color residuals.

## Phase 2: Stellar Mass (M/L) Scaling

Objective:
- reduce mass ratio bias vs observation references.

Checks:
1. Verify mass formula inputs:
- redshift distance source
- chosen photometric band and correction flow
- IMF assumptions in mass normalization

2. Fit/update scaling constants:
- tune only M/L constants on train set.
- preserve formula structure where possible.

3. Validate holdout:
- compute mass ratio distribution on holdout.

Target thresholds (initial):
- median mass ratio on train in [0.8, 1.25]
- holdout median not degraded vs baseline

Exit criteria:
- clear mass bias reduction with reproducible JSON evidence.

## Phase 3: Isochrone Interpolation and Grid Handling

Objective:
- eliminate interpolation artifacts that create age/Z instability.

Checks:
1. Boundary behavior:
- explicit handling at min/max grid edges.

2. Interpolation method consistency:
- deterministic interpolation across age/Z bins.

3. No silent extrapolation:
- explicit warnings/flags when extrapolation would occur.

4. Unit compatibility:
- ensure metallicity representation is consistent across model and benchmark comparisons.

Exit criteria:
- smoother age/Z behavior across nearby grid points.
- reduced abrupt age/Z jumps in ranked fits.

## Phase 4: Weighted Scoring and Uncertainty-Aware Benchmarks

Objective:
- improve scoring realism using available uncertainties.

Steps:
1. Add/enable weighted chi-squared with photometric errors.
2. Apply sigma floor policy when errors missing.
3. Carry observation uncertainty into pass/fail comparisons where available.

Exit criteria:
- benchmark decisions reflect uncertainty, not only point deltas.

## Operational Workflow Per Iteration

For each iteration:
1. run train benchmark
2. run holdout benchmark
3. write comparison artifact JSON
4. update calibration log
5. commit with one-line summary of what changed

Recommended artifact naming:
- `lib/data/fit/calibration_train_<date>.json`
- `lib/data/fit/calibration_holdout_<date>.json`
- `lib/data/fit/calibration_delta_<date>.json`

## Suggested Metrics Dashboard

Track these per run:
- age absolute error (Gyr)
- metallicity absolute error (Z)
- stellar mass ratio (SPS / observed)
- chi-squared median and spread
- pass/warn/fail counts
- benchmark eligibility counts and reasons

## Risk Controls

1. Provenance drift:
- never mix reference sources without explicit tagging.

2. Overfitting:
- do not claim improvement without holdout confirmation.

3. Hidden unit mismatch:
- enforce unit labels in JSON artifacts.

4. UI/config mismatch:
- keep calibration-critical gates in Config only.

## Completion Definition for v1 Calibration

Calibration v1 is complete when:
- train and holdout both show sustained improvement over baseline.
- no known unit/provenance mismatches remain in age/Z/mass comparisons.
- benchmark runs are reproducible from documented tasks/config.

## Calibration Findings Log

### 2026-04-03 - BM Runs 1-3 (Tier 1 Fast, ugriz only)

Runs:
- `bm_tier1_fast_20260403_040111` (BM1)
- `bm_tier1_fast_weighted_20260403_041528` (BM2)
- `bm_tier1_fast_weighted_ageZ_20260403_043205` (BM3)

Galaxies:
- NGC4660, NGC4564, NGC4570, NGC4387 (Tier 1, ATLAS3D)

Changes between runs:
- BM1 -> BM2: weighted chi-squared + extended age grid to 14 Gyr
- BM2 -> BM3: expanded `grid_metallicities_z` definition to 9 points

Age recovery:
- BM1: catastrophic (3/4 at 2.0 Gyr)
- BM2/BM3: good (all 4 in 12-13 Gyr range; within about +/-1.5 Gyr of observed)
- Weighted chi-squared was the decisive fix for age behavior

Metallicity recovery:
- BM1/BM2/BM3: all 4 converged to Z=0.020
- BM3 did not change outcomes in the Tier 1 fast run configuration
- Important caveat: BM3 used fast mode; fast-mode metallicity sweep must also be expanded to test dense-Z impact in fast runs directly
- Root cause remains consistent with age-metallicity degeneracy in optical-only ugriz fitting

Stellar mass recovery:
- BM1: catastrophic spread
- BM2/BM3: improved (NGC4564 ~0.90x; NGC4660 ~0.75x)
- NGC4387 (~0.49x) and NGC4570 (~2.37x) remain outside preferred bounds

Current calibration ceiling with ugriz-only:
- Age: +/-1-2 Gyr recoverable
- Metallicity: +/-0.01 not robustly recoverable from ugriz alone
- Mass: factor ~2 achievable when age is correct

Resolution options for metallicity degeneracy (ordered by implementation complexity):
1. UV photometry (GALEX NUV/FUV)
2. NIR photometry (2MASS JHK)
3. Spectroscopic indices (Hbeta, Mg b, Fe5015)
4. Mass-metallicity prior

## Phase 5: GALEX UV Photometry Ingestion

Objective:
- Extend SED coverage from ugriz to include GALEX NUV and FUV to increase age/metallicity leverage.

Why GALEX:
- UV is sensitive to hot/young components.
- NUV-r is a strong age-sensitive color.
- Coverage is good for nearby ETGs and adequate for compact targets.

Implementation steps:
1. Add GALEX columns on photometry records:
- `fuv_mag`, `fuv_mag_err`
- `nuv_mag`, `nuv_mag_err`
- `galex_source`, `galex_objid`, `galex_checked_at`
2. Build `GalexClient` for catalog query + positional match.
3. Add GALEX filter curves in `lib/data/filters/`.
4. Extend model/filter convolution to include GALEX bands.
5. Extend chi-squared to include UV bands when present (graceful fallback when absent).
6. Re-run Tier 1 benchmarks with ugriz+NUV/FUV where available.

Exit criteria:
- NUV reproduced within ~0.3 mag for Tier 1 targets.
- Measurable metallicity recovery improvement vs ugriz-only.
- No regression in age recovery.

Risks:
- Incomplete FUV coverage (NUV is generally better).
- UV-upturn behavior in old ellipticals may require additional model handling.
- Spectral library UV support must be verified below 300 nm.
