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

StellarPop is a web-based stellar population synthesis pipeline implemented in Ruby on Rails using a blackboard architecture. It is the first known implementation of stellar population synthesis in this language and framework. The system coordinates pure-Ruby knowledge sources via a shared blackboard to produce composite spectra from user-defined parameters: an initial mass function (IMF) sampler, stellar spectra generator, isochrone correction module, star formation history (SFH) model, and a BaSeL 3.1 spectral library parser. Runs can select either a BaSeL-library spectral source or a Planck-based spectral source. In addition to synthetic modeling, StellarPop resolves SDSS photometry via a local reference catalog with live API fallback and computes chi-squared goodness of fit against synthetic spectra. SDSS dataset release selection is configurable (`DR18`/`DR19`) in the pipeline configuration UI, with `DR19` as the default. The v0.3.3 update also standardizes objid-based SDSS fetches for runtime/catalog refresh, keeps both Petrosian and model photometry per galaxy under `mag_type` control, expands literature-backed observation coverage, and adds synthesis-run stellar-mass estimation from best-fit SFH/IMF plus observed `r`-band magnitude and redshift-based luminosity distance. FITS table parsing for SDSS-derived products is now handled through an external standalone Ruby gem (`fits_parser`, v0.1.0), published on RubyGems and integrated via Bundler.

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

For benchmark reliability, StellarPop now tracks data-quality provenance at galaxy level in SQLite. In addition to active photometry values, the DR19 refresh path stores per-band photometric uncertainties (`err_*`, `petro_err_*`, `model_err_*`), extinction terms, SDSS clean flag, and spectroscopic quality (`z_err`, `z_warning`). Identity and redshift confidence are persisted via `id_match_quality` and `redshift_confidence` (with provenance/source timestamps), enabling deterministic quality gates before scientific benchmark scoring.

Measurement persistence is now fully split from galaxy identity into dedicated tables: `galaxy_photometries` and `galaxy_spectroscopies`. The `galaxies` table serves as target identity/provenance (`name`, `ra`, `dec`, object identifiers, catalog metadata), while SDSS ingestion tasks upsert photometric and spectroscopic measurements in their corresponding tables. Legacy duplicated measurement columns were removed from `galaxies` after backfill and code-path migration.
To support benchmark target curation, a `photometry_usable` boolean flag (default `true`) was added on both `galaxies` and `galaxy_photometries`, and benchmark catalog selection now filters through `Galaxy.usable_photometry`. This provides an explicit mechanism to exclude known-bad photometric targets from SPS fitting without deleting records.

Asynchronous execution is handled by Sidekiq through a dedicated synthesis queue. Each synthesis run is persisted in Rails models, executed in a background job, and stored as a composite spectrum in the database. During integration, per-star spectra are interpolated onto a user-configurable wavelength grid (300-1100nm, default 350-900nm), combined with IMF/SFH weighting and MIST-derived luminosity weighting from FSPS-sourced isochrone tables, and smoothed before final normalization. BaSeL spectral lookup and MIST isochrone weighting now use consistent per-run metallicity selection derived from `metallicity_z`. For observational comparison, StellarPop first checks local SDSS photometry in SQLite and falls back to the configured SDSS SkyServer release (`DR18`/`DR19`, default `DR19`) on misses. Runtime and catalog refresh fetches use objid-based SDSS lookup when `sdss_objid` is available, replacing coordinate-first lookup in normal workflows (coordinate fallback remains for maintenance utilities). Petrosian and model photometry plus active `mag_type` selection are now stored in `galaxy_photometries` (including promoted `mag_u..mag_z` values used for chi-squared fitting). Spectroscopic measurements are stored in `galaxy_spectroscopies`, modeled as `has_many` per galaxy to preserve history, with one record marked current for runtime consumers. Chi-squared is computed using SDSS filter-convolved synthetic fluxes (ugriz), with redshift k-corrections applied before comparison. After a successful fit, run-level stellar mass is estimated from best-fit SFH/IMF context, observed `r`-band magnitude, and redshift-derived luminosity distance, then persisted in `synthesis_runs.stellar_mass` for UI display and downstream analysis.

FITS ingestion tasks used for SDSS-derived tabular products (for example `gal_info_dr7_v5_2.fit` and `totlgm_dr7_v5_2.fit`) now rely on the standalone `fits_parser` gem rather than app-local FITS parsing code. This extraction improves modularity and enables parser versioning independent of the Rails application.
For nearby galaxies with unresolved SDSS `SpecObj.bestObjID` linkage, spectroscopy history was extended with external SIMBAD redshift ingestion tasks (single-object and bulk-report modes). A DR19-wide SIMBAD audit/report (`dr19_simbad_z_check.json`) was generated and applied to current spectroscopy rows with provenance fields (`redshift_source`, `source_release`, confidence). After backfill, unresolved placeholder spectroscopy rows (`redshift_z=nil`) were removed.

To support future age/stellar-metallicity benchmark provenance keyed by spectroscopic identifiers, two DR2 Gallazzi reference catalogs are ingested (`gallazzi_z_star.txt`, `gallazzi_lwage.txt`) with unique `(plateid, mjd, fiberid)` indexing and batch upsert through `gallazzi:import_dr2`; current ingest size is 261,054 rows for each catalog. To prevent growth of the primary application database, these catalogs are stored in dedicated SQLite files (`gallazzi_*_development.sqlite3`) through model-specific external DB connections, while the main development DB retains core application state only.
An additional comparison task (`gallazzi:compare_ages_to_galaxies`) resolves Gallazzi age entries to sky coordinates and SDSS object identity through DR7 `gal_info` FIT metadata, then checks overlap with the local `galaxies` table using object-id-first matching with angular-separation fallback.

Three pipeline fixes were required to recover physically correct color behavior: (1) BaSeL binary parsing was corrected from big-endian (`g*`) to little-endian (`e*`) unpacking; (2) spectral lookup now uses MIST-evolved `teff/logg` per star instead of a mass-only mapping; and (3) chi-squared moved to magnitude-space color comparison normalized to `r`-band, reducing scale artifacts in photometric fitting.

Recent usability and provenance updates focused on reproducible interpretation: local SDSS catalog entries now carry `agn` and `sdss_dr` metadata, the run form defaults to catalog-driven target selection with RA/Dec autofill (manual override optional), and run notes now distinguish SDSS failure causes (no object found vs API timeout vs unreachable API) instead of using a single ambiguous message.
AGN labeling was extended with explicit source traceability fields on `galaxies` (`agn_source`, `agn_method`, `agn_confidence`, `agn_checked_at`) and an SDSS-driven classifier task (`sdss:classify_agn_dr19`) using `SpecObj.class/subClass` matched by `bestObjID = sdss_objid`. In the current DR19 sample, strict objid-linked spectroscopy class resolution produced AGN labels for `5/26` galaxies and left `21/26` unresolved. A SIMBAD fallback workflow (`external:classify_simbad_agn_for_unresolved_dr19`) is implemented to fill unresolved rows when endpoint connectivity is available.
To keep AGN filtering decisions auditable at run-selection time, benchmark target views now display AGN flags explicitly both in candidate selection (`/benchmark_runs/new`) and run listing summaries (`/benchmark_runs`).

The web UI was also reorganized around this split model. Galaxy detail pages now expose separate cards for identity metadata, photometry, and spectroscopy, with dedicated edit forms per card. This reduces source ambiguity between PhotoObj-like and SpecObj-like fields and makes provenance boundaries explicit during manual review and curation. The spectroscopy layer is tested with model and integration coverage for history semantics (current-row demotion and nested CRUD flows).

## Grid fitting

StellarPop includes a parameter-grid sweep workflow over 1050 model combinations. The age grid is `[0.01, 0.05, 0.1, 0.5, 1.0, 3.0, 5.0, 8.0, 10.0, 12.0]` Gyr, with 5 metallicities and 3 IMF choices across SFH models. For burst SFH runs, the burst center is additionally swept through `burst_age_gyr = [0.1, 0.5, 1.0, 2.0]` Gyr, increasing total combinations and improving sensitivity to bursty star formation at different epochs. For each combination, the pipeline generates a synthetic spectrum and computes chi-squared against observed SDSS photometry. Results are sorted by chi-squared, and the best-fit age, metallicity, SFH, and IMF are recorded automatically. This ranking-based sweep is the primary inference mechanism for deriving physical galaxy properties from observed photometry.

## Calibration workflow

StellarPop now includes a benchmark calibration workflow (`CalibrationRun`) that executes the grid-fitting pipeline against reference galaxies with expected physical ranges. Benchmark targets are selectable per run from the observation-backed galaxy set filtered to the active SDSS dataset release, with a `full` profile (complete sweep) and a `fast` profile (reduced sweep) for quicker turnaround. Literature observations were updated for 16 galaxies with published sources in the v0.3.3 provenance refresh. Each calibration run records benchmark-specific best fits, top-ranked alternatives, and pass/warn/fail checks for age, metallicity, and SFH class agreement. A dedicated progress panel reports completed combinations, active benchmark step, and estimated remaining runtime while the calibration job is running.

Calibration now includes an explicit benchmark-eligibility gate. Targets without sufficient confidence (for example missing redshift uncertainty or low-confidence identity provenance) are marked in benchmark output as data-quality failures (`data_quality_ok=false`) and are excluded from valid scientific pass criteria. This separates physics/model disagreement from upstream catalog-confidence issues.
To support controlled calibration experiments without changing core grid physics, a dedicated tuning parameter (`calibration_mass_log_offset_dex`) was added to runtime configuration and exposed in a standalone "Tuning" UI section. This offset applies multiplicatively in log space (`M_corrected = M_base * 10^dex`) and is used consistently in synthesis and benchmark mass calculations.

## Results

First grid-fit results show plausible astrophysical behavior and known photometric fitting limits. For M101, the best fit was age `0.1` Gyr, metallicity `Z=0.0063`, and exponential SFH, consistent with a young star-forming spiral. For NGC3379, corrected DR19 objid-based photometry yields old-population best fits in the `8-10` Gyr range with near-solar metallicity, consistent with published constraints. After the pipeline fixes, synthetic `g-r` colors span approximately `-0.44` (young `0.01` Gyr) to `+0.65` (old `12` Gyr), covering the observed galaxy color range and restoring physically correct age dependence.

For FIT-linked mass validation, a DR19 coordinate crossmatch workflow was added against `gal_info_dr7_v5_2.fit` (1 arcsec threshold), followed by row-aligned mass PDF extraction from `totlgm_dr7_v5_2.fit`. In the current benchmark subset, three galaxies were matched (`NGC4387`, `NGC4874`, `NGC4889`). After updating `NGC4387` observational mass to the FIT-derived `AVG` value with explicit FIT provenance, all three matched galaxies fall within the FIT 95% interval (`P2P5-P97P5`), with one inside the 68% interval (`P16-P84`). A three-target fast benchmark run gives mass ratios (`SPS/observed`) of `2.153` (`NGC4387`), `1.160` (`NGC4874`), and `0.366` (`NGC4889`), indicating mixed residuals but improved FIT-consistency diagnostics.
For Tier1 ATLAS3D calibration (`NGC4387`, `NGC4564`, `NGC4570`, `NGC4660`), applying a global offset of `+0.0845` dex (derived from prior BM residuals) shifted `SPS/observed` mass ratios from `[0.488, 0.900, 2.373, 0.754]` to `[0.593, 1.093, 2.882, 0.916]`. This improved underestimation for three galaxies but amplified an existing high outlier (`NGC4570`), indicating that a single global mass offset is only a partial correction and that class-aware or quality-aware calibration is likely required.
In follow-up SFH debugging, the spectral integrator was updated to apply luminosity-aware SFH accumulation per age bin (`sfh_weight * luminosity_scale`) instead of SFH weighting alone. Focused integration tests remained green after this change. A targeted NGC4564 exponential run still showed objective-function tension: the formal chi-squared winner (`age=14.0`, `Z=0.0100`) was less observationally plausible than the near-best ranked candidate (`age=10.0`, `Z=0.0250`) relative to literature anchors (`age~11.9`, `Z~0.0208`). This indicates residual calibration limits in the scoring objective (and/or missing priors), not only in SFH weighting mechanics.
For AGN metadata quality, SDSS spectroscopy-based classification now runs as a reproducible batch task with JSON reporting. Current coverage remains partial due unresolved strict `bestObjID` linkages in SDSS `SpecObj`; fallback enrichment from SIMBAD type metadata is available in code but operationally dependent on SIMBAD endpoint reachability.
For DR2 Gallazzi age overlap checks, scanning all 261,054 age rows against the current local 35-galaxy table produced no matches at 1 arcsec; 258,381 rows were resolvable to RA/DEC via FIT metadata and 2,673 were unresolved. This indicates current local targets do not intersect the DR2 Gallazzi subset under the present identifier/coordinate constraints.
Additional FIREFLY-based validation workflows were added using standalone FIT catalogs. DR17 MaNGA products produced small overlap (`1/35` for Pipe3D and `2/35` for FIREFLY globalprop at 1 arcsec), while the larger DR16 eBOSS FIREFLY table yielded `12/35` matches (`11` by SDSS object identity and `1` by coordinate fallback). For the `10` matched galaxies that also had observation rows, a fast benchmark sweep was executed and paired against FIREFLY age/metallicity/stellar-mass values with per-galaxy JSON output. During this comparison, an initial analysis error was corrected: FIREFLY metallicity was first compared in raw catalog units against benchmark `Z`, then normalized to `Z` using a documented assumption (`Z = metallicity_raw * Zsun`, with `Zsun=0.02`). After applying that conversion, age agreement remained mixed, metallicity agreement improved for some targets but stayed inconsistent across the set, and stellar-mass comparisons were available for a subset of galaxies where run-level SPS mass estimates were emitted.
This FIREFLY exercise is treated as a negative-result checkpoint rather than a validation success: overlap improved in count but remained heterogeneous in object identity quality (including large-separation matches), and metric definitions were not sufficiently aligned for robust benchmark truthing across the full set. As a result, FIREFLY outputs are retained as exploratory comparisons, while benchmark-grounding continues to prioritize strongly keyed mass references (MPA-JHU `totlgm`) and literature-constrained age/metallicity values.

### Note on FIREFLY Comparison, Aperture Effects, and Match Quality

A comparison between StellarPop benchmark values and FIREFLY-derived stellar-population parameters shows mixed behavior: several quiescent massive ellipticals (for example `NGC4889`, `NGC4874`) are broadly more consistent than actively star-forming or AGN-host galaxies (for example `NGC1068`, `NGC3690`, `NGC4194`). A likely contributor is aperture mismatch. FIREFLY values are derived from SDSS spectroscopy (3-arcsecond fibers), which in nearby systems can sample nucleus-dominated light rather than global galaxy light. In AGN/starburst systems, this central spectrum can be strongly affected by non-stellar emission and young concentrated components, reducing comparability with global photometric fits.

StellarPop benchmark inference uses broadband SDSS imaging photometry integrated over the galaxy, and therefore targets a more global stellar-population signal. For morphologically smooth, quiescent systems, central-fiber and global-light estimates can be closer; for centrally active systems, disagreement is expected. In addition, the FIREFLY overlap set includes some large-separation coordinate matches, so identity quality is non-uniform across the sample. Together, these effects support using FIREFLY here as an exploratory cross-check rather than a definitive validation reference for global age/metallicity benchmarking.

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
