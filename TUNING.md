# Tuning Summary (April 2026)

## Core Finding

The main blocker is **optical age-metallicity degeneracy** in SDSS `ugriz`-only fitting for old galaxies (ETGs), not a simple SFH model toggle bug.

## What We Confirmed

1. Pipeline execution works, but best-fit realism is inconsistent.
2. SFH switching alone does not solve NGC4564 age mismatch:
   - `exponential` and `delayed_exponential` both preferred old ages (~14 Gyr).
3. Objective minimum and observational closeness can diverge:
   - a lower chi-squared fit is not always the most physically plausible fit.
4. This is consistent with known astrophysical degeneracy limits for optical broadband SPS.

## Practical Interpretation

- The math is not just "broken arithmetic."
- The current **objective/constraint design** is insufficient to select the physically preferred age/Z region from `ugriz` alone.
- Mass can look reasonable while age/Z remain ambiguous.

## What Pros Usually Do

To break degeneracy, professional workflows add:
- spectroscopy (line indices or full spectral fitting),
- wider wavelength coverage (UV/NIR + optical),
- strong priors (morphology/SFH expectations),
- uncertainty-aware Bayesian inference,
- strict aperture matching between model and references.

## Actionable Direction for This Project

1. Keep scope narrow (single galaxy class, single benchmark tier).
2. Tune one component at a time with explicit pass/fail criteria.
3. Prefer observational realism checks over raw chi-squared rank alone.
4. Avoid broad feature expansion until current calibration objective is stable.

## Suggested Short Loop

1. Pick one target galaxy and one SFH family.
2. Run one controlled benchmark.
3. Compare measured vs observed age/Z/mass line-by-line.
4. Record result in `CALIBRATE.md`.
5. Apply one small objective/constraint adjustment.
6. Repeat.

This loop is slower, but scientifically safer and reproducible.
