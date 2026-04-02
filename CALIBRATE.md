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
