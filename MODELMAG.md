# MODELMAG Status

## Done Today

- `galaxies` table created and seeded with 30 galaxies
- `observations` table is DB-only (literature-entered rows; no YAML seeding)
- `BenchmarkCatalog` wired to DB
- `SdssLocalCatalog` retired and deleted
- All `synthesis_runs` and `grid_fits` back-filled with `galaxy_id`
- Everything committed except the final multiwavelength migration, which is on hold

## On Hold Pending SDSS

- `modelMag` `ugriz` fix in `SdssClient`
- FUV/NUV/W1/W2 migration
- GALEX/WISE rake task

## When SDSS Comes Back

1. Verify `modelMag` vs Petrosian magnitude question
2. Run the multiwavelength migration
3. Build the rake task to fetch GALEX and WISE

## Recommended Next-Session Order

1. SDSS back online check
2. `SdssClient` switch/verify to `modelMag_*`
3. Re-verify local `ugriz` provenance (`sdss_dr` + mag type)
4. Run/add multiwavelength migration (FUV/NUV/W1/W2)
5. Build GALEX/WISE import rake task
6. Re-run benchmark/grid validation with updated photometry baseline
