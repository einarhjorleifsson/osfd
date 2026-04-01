# osfd — Agent Memory File

## Package Overview

**osfd** (`Spatial Fisheries Data Tools`) consolidates functions for the ICES WGSFD VMS and logbook data-call workflow. The primary author is Einar Hjörleifsson.

- GitHub: https://github.com/einarhjorleifsson/osfd
- Core dependencies: `dplyr`, `tidyr`, `lubridate`, `sf`, `stringr`, `icesVocab`
- Optional: `duckdbfs`, `icesConnect`, `icesVMS`, `vmstools`, `sfdSAR`

## Data Sources

| File | Description |
|---|---|
| `data-raw/eflalo_IS.parquet` | Icelandic fleet logbook data (test/dev data) |
| `data-raw/tacsat_IS.parquet` | Icelandic fleet VMS ping data (test/dev data) |
| `data-raw/trail.parquet` | Trail data |

Both parquet files are the primary test data for catch distribution development.

## Key Concepts

**eflalo** — logbook records; one row per trip × day × ICES rectangle event. Catch columns are `LE_KG_{SPECIES}` and `LE_EURO_{SPECIES}`. Aggregated totals are `LE_KG_TOT` and `LE_EURO_TOT`.

**tacsat** — VMS ping records; one row per vessel × timestamp position. Key state column: `SI_STATE` (1 = fishing, 0 = non-fishing/steaming).

**Catch distribution problem** — logbook catch is reported at event level (trip/day/rectangle) but must be distributed proportionally across VMS pings to produce spatially explicit catch maps.

## R Source Files

| File | Key Functions | Notes |
|---|---|---|
| `R/split_among_pings.R` | `fd_split_among_pings()`, `fd_distribute_across_levels()`, `fd_distribute_one_level()`, `fd_prep_inputs()`, `has_rows()` | ✅ Primary implementation |
| `R/splitAmongPings.R` | `splitAmongPings_dt()`, `prepSplitInputs_dt()`, `distributeAcrossLevels_dt()` | Reference: data.table decomposition; requires **vmstools** + **doBy** attached |
| `R/splitAmongPings_tidy.R` | `splitAmongPings_tidy()`, `prepSplitInputs_tidy()`, `distributeAcrossLevels_tidy()`, `distribute_one_level_tidy()` | Reference: dplyr rewrite; exported from osfd |
| `R/tidy_eflalo.R` | `fd_trips()`, `fd_events()`, `fd_tidy_eflalo()` | Extraction / decomposition helpers |
| `R/data_clean.R` | `fd_clean_eflalo()`, `fd_clean_tacsat()` | Pre-processing; R-only (not duckdb-compatible) |
| `R/data_flag.R` | `fd_flag_tacsat()`, `fd_flag_trips()`, `fd_flag_events()`, `fd_flag_eflalo()` | QC / labelling; R-only (not duckdb-compatible) |
| `R/trail_steps.R` | `fd_step_time()` | Ping interval calculation |
| `R/analysis.R` | `fd_add_trips()`, analysis helpers | Trip assignment lives here |
| `R/data.R` | Dataset documentation | |
| `R/globals.R` | Global variable declarations | |

## Setup Functions (`R/data_clean.R`)

⚠️ Both setup functions are **R-only** — `paste()`, `lubridate::dmy_hms()`, `lubridate::dmy()`, `row_number()`, and `consecutive_id()` are not duckdb-compatible. Marked with inline comments in source.

### `fd_clean_tacsat(tacsat, remove = TRUE)`
- Checks for: `VE_COU`, `VE_REF`, `SI_DATE`, `SI_TIME`, `SI_LATI`, `SI_LONG`, `SI_SP`, `SI_HE`
- Coerces `SI_LATI`, `SI_LONG`, `SI_SP`, `SI_HE` to numeric
- Creates: `SI_DATIM` (POSIXct, UTC) from `SI_DATE` + `SI_TIME`; drops originals by default
- Adds `.pid` (integer row identifier) via `row_number()`
- Sorts by `VE_REF`, `SI_DATIM`

### `fd_clean_eflalo(eflalo, remove = TRUE)`
- Checks for: `VE_KW`, `VE_LEN`, `VE_TON`, `LE_MSZ`, `LE_CDAT`, `FT_DDAT`, `FT_DTIME`, `FT_LDAT`, `FT_LTIME`
- Creates: `FT_DDATIM` (trip departure POSIXct), `FT_LDATIM` (trip landing POSIXct)
- Coerces `LE_CDAT` from `"DD/MM/YYYY"` character to R Date
- Coerces `KG`/`EURO` columns + `VE_KW`, `VE_LEN`, `VE_TON`, `LE_MSZ` to numeric
- Adds `.eid` (integer row identifier) and `.tid` (trip identifier via `consecutive_id()`)
- Removes raw date/time columns by default; sorts by `VE_COU`, `VE_REF`, `FT_DDATIM`, `FT_LDATIM`, `LE_CDAT`

## Check Functions (`R/data_flag.R`)

All check functions **never filter** — they add a labelled check column and leave filtering to the caller. All are **R-only** (sf joins, `duplicated()` not duckdb-compatible; marked with inline comments).

### `fd_flag_tacsat(tacsat, minimum_interval_seconds = 30, area, harbours)`
- Performs sf spatial joins (ICES areas, harbours with 3 km buffer)
- Also computes `.intv` (seconds since last ping via `fd_step_time()`, grouped by `VE_REF`)
- Adds `.checks` and `.intv` columns; checks 01–08 plus `"ok"`
- ⚠️ Records with `NA` coordinates will cause `sf::st_as_sf()` to error — pre-filter upstream if needed

### `fd_flag_trips(trips)`  ← moved here from `tidy_eflalo.R`
- Input: trips data frame from `fd_trips()`
- Adds `.tchecks` column; checks 01–08 plus `"ok"`
- Checks: departure/arrival missing, departure after/equals arrival, temporal overlaps (lead/lag), missing VE_LEN/VE_KW

### `fd_flag_events(events, gear = NULL, met6 = NULL)`  ← moved here from `tidy_eflalo.R`
- Input: events data frame from `fd_events()`
- Adds `.echecks` column; checks 01–03 plus `"ok"`
- Defaults for `gear`/`met6` are `NULL` (checks skipped); pass `icesVocab::getCodeList(...)$Key` to enable
- ⚠️ Catch-date range checks are NOT performed here (events separated from trips); use `fd_flag_eflalo()` for that

### `fd_flag_eflalo(eflalo, year = NULL, gear = NULL, met6 = NULL)`
- Delegates overlap detection to `fd_trips()` + `fd_flag_trips()`, then joins back
- Adds `.checks` column; checks 01–12 plus `"ok"`
- Defaults for `gear`/`met6` are `NULL` (checks skipped); pass `icesVocab::getCodeList(...)$Key` to enable
- The two-row `is.na(FT_DDATIM) | is.na(FT_LDATIM)` check is collapsed to one `case_when()` arm

## `fd_step_time()` (`R/trail_steps.R`)

Computes time interval (seconds) between consecutive pings as a weighted blend of backward and forward differences. Used internally by `fd_flag_tacsat()`. Call within `group_by(VE_REF)` + `mutate()`.

## `fd_add_trips()` (`R/analysis.R`)

Assigns trip metadata (`FT_REF`, gear, metier, rectangle etc.) to tacsat pings by time-interval join against eflalo trip windows. Lives in `R/analysis.R`, not `trail_steps.R`.

## Primary Function: `fd_split_among_pings()`

Distributes logbook catch (`LE_KG_TOT`, `LE_EURO_TOT`) proportionally across VMS pings.

### Inputs

- `tacsat` — VMS data; requires `FT_REF`, `SI_STATE`, `VE_REF`. If not already present: `SI_DATIM` (POSIXct) or `SI_DATE` + `SI_TIME`; `SI_YEAR`, `SI_DAY`, `LE_RECT` derived automatically if absent (R data.frames only).
- `eflalo` — logbook data; requires `VE_REF`, `FT_REF`, `LE_KG_TOT`, `LE_EURO_TOT`, `LE_RECT`. `LE_CDATIM` (POSIXct) or `LE_CDAT` needed for temporal keys.

### Pipeline Bridge

`fd_clean_tacsat()` produces `time`; `fd_split_among_pings()` expects `SI_DATIM`. Rename before calling:
```r
tacsat <- tacsat |> dplyr::rename(SI_DATIM = time)
```

### Three-Pass Distribution Hierarchy

| Pass | Scope | Levels tried (fine → coarse) |
|---|---|---|
| 1 | Trip-matched | trip:day → trip:rect → trip |
| 2 | Vessel-matched (`conserve = TRUE`) | vessel:day → vessel:rect → vessel:year |
| 3 | Fleet-level (`conserve = TRUE`) | fleet:day → fleet:rect → fleet:year |

Each level joins on progressively coarser keys; unmatched eflalo rows cascade. Only `SI_STATE == 1` pings receive catch; `SI_STATE == 0` pings appear with `NA`.

### Output Columns (added to tacsat)

| Column | Description |
|---|---|
| `kg` | Distributed catch (kg); renamed from `LE_KG_TOT` internally |
| `euro` | Distributed value (EUR); renamed from `LE_EURO_TOT` internally |
| `.how` | Pipe-separated pass:level labels e.g. `"trip:day\|vessel:year"`; `NA` = unmatched |
| `.n_eflalo` | Count of distinct eflalo rows contributing catch to each ping |

### Key Design Decisions

1. **duckdb-compatible:** All joins/filters/aggregations lazy; R-only operations (ICESrectangle, datetime assembly) guarded with informative `stop()`.
2. **`.le_id` row key:** Added in `fd_prep_inputs()` as `row_number()` — used for `anti_join()`-based removal of matched rows between passes.
3. **Fishing pings only in denominator:** `tacsat_fishing` (SI_STATE == 1) is the denominator; `tacsat_act` (SI_STATE != 0) receives the final merge.
4. **No automatic filtering:** All checks return label columns; filtering is the user's responsibility (osfd convention).
5. **Mass conservation is fleet-level only with `conserve = TRUE`:** Per-trip and per-vessel totals will not balance. Unmatched trips' catch redistributes to sibling trips' pings via `vessel:year`; catch from vessels absent from VMS redistributes to all fleet pings via `fleet:year`. Both inflate `kg_tacsat` on matched trips. The `.how` column is the diagnostic: `vessel:year` or `fleet:year` in `.how` means a ping absorbed redistributed catch beyond its own trip's logbook. With `conserve = FALSE` only `trip:*` labels appear and per-trip balance holds (only truly unmatched trips have `NA`).

### Internal call chain

```
fd_split_among_pings()
  └─ fd_prep_inputs()               # validate + ensure key cols + partition
  └─ fd_distribute_across_levels()  # called up to 3× (trip/vessel/fleet)
        └─ fd_distribute_one_level()
```

## `R/tidy_eflalo.R` — Trip / Event decomposition

Contains three functions; `fd_flag_trips()` and `fd_flag_events()` have been **moved to `R/data_checks.R`**.

### `fd_trips(eflalo)`
- Selects `.tid` + all `VE_*` and `FT_*` columns; returns distinct rows (one row per trip)
- Requires `.tid` added by `fd_clean_eflalo()`

### `fd_events(eflalo)`
- Selects `.eid`, all `LE_*` columns (including `LE_KG_*` / `LE_EURO_*`), and `.tid`
- Errors with a helpful message if rows decrease after `distinct()` (duplicate events detected)
- Requires `.eid` and `.tid` added by `fd_clean_eflalo()`

### `fd_tidy_eflalo(eflalo)`
- Convenience wrapper returning `list(trips = fd_trips(eflalo), events = fd_events(eflalo))`

## Typical Pre-Distribution Pipeline

Two approaches are supported: **classical** (single eflalo data frame throughout) and **tidy** (split into `trips` + `events`).

```r
library(dplyr)
library(nanoparquet)  # or duckdbfs
library(osfd)

eflalo <- read_parquet("data-raw/eflalo_IS.parquet")
tacsat <- read_parquet("data-raw/tacsat_IS.parquet")

# 1. Setup (standardise column names/types; R-only)
eflalo <- fd_clean_eflalo(eflalo)
tacsat <- fd_clean_tacsat(tacsat)

# --- Classical approach ---
# 2a. QC (adds .checks, does NOT filter)
eflalo <- fd_flag_eflalo(eflalo)            # gear/met6 checks skipped by default
tacsat <- fd_flag_tacsat(tacsat)
# 3a. Filter
eflalo <- filter(eflalo, .checks == "ok")
tacsat <- filter(tacsat, .checks == "ok")

# --- Tidy approach ---
# 2b. Decompose and check separately
trips  <- fd_trips(eflalo)  |> fd_flag_trips()
events <- fd_events(eflalo) |> fd_flag_events()
# 3b. Filter and rejoin
trips  <- filter(trips,  .tchecks == "ok") |> select(-.tchecks)
events <- filter(events, .echecks == "ok") |> select(-.echecks)

# 4. Trip assignment
tacsat <- fd_add_trips(tacsat, eflalo)

# 5. Ensure LE_KG_TOT / LE_EURO_TOT exist in eflalo (may need rowwise sum)

# 6. Distribute catch
result <- fd_split_among_pings(tacsat, eflalo)
```

## Vignettes

| File | Description |
|---|---|
| `vignettes/articles/catch-distribution.Rmd` | End-to-end pipeline vignette: raw parquet → QC → trip assignment → `fd_split_among_pings()` (with `conserve = FALSE` and `conserve = TRUE` runs + side-by-side comparison with extreme case examples) → mass conservation diagnostics |
| `vignettes/articles/spreading_fish-and-cash.Rmd` | Legacy scratch article — superseded by `implementation-comparison.Rmd` |
| `vignettes/articles/implementation-comparison.Rmd` | Compares all three implementations (`splitAmongPings` data.table, `splitAmongPings` tidy, `fd_split_among_pings`) on a controlled synthetic dataset; documents interface differences, numerical equivalence, and when to use each |

## Reference Implementations (for Comparison)

- **vmstools `splitAmongPings()`** — original data.table implementation (`R/splitAmongPings.R`)
- **tidyverse rewrite** — same logic but lazy/dplyr (`R/splitAmongPings_tidy.R`)
- **ramb `dc_spread_cash_and_catch()`** — inspiration for the three-pass cascade logic

## Tests

| File | What is tested |
|---|---|
| `tests/testthat/test-data_checks.R` | `fd_flag_eflalo()` overlap detection: overlapping trip labelled `"06 - overlapping trips"`, earlier trip and non-overlapping vessel pass as `"ok"` |

## Outstanding Work

- [ ] Investigate ~20% overall fleet-level mass conservation gap (`conserve = TRUE`: 903k kg in, 728k kg out) — cause unclear beyond the ~30k kg from vessels entirely absent from VMS
- [x] Rename setup-function output columns to ALLCAPS convention: `time`→`SI_DATIM`, `lon`→`SI_LONG`, `lat`→`SI_LATI`, `speed`→`SI_SP`, `heading`→`SI_HE` (tacsat); `T1`→`FT_DDATIM`, `T2`→`FT_LDATIM`, `date`→`LE_CDAT` (eflalo). Applied across `data_setup.R`, `data_checks.R`, `analysis.R`, `globals.R`, and test fixtures.
- [ ] Confirm `LE_KG_TOT` / `LE_EURO_TOT` availability after `fd_clean_eflalo()` (currently requires user to create them)
- [x] Comparison article created as `vignettes/articles/implementation-comparison.Rmd`
- [x] Functions in all three `splitAmongPings*.R` files renamed with suffixes (`_dt`, `_tidy`, `fd_`) to disambiguate; `splitAmongPings_tidy()` is the osfd-exported version
- [x] `fd_flag_trips()` and `fd_flag_events()` moved from `tidy_eflalo.R` to `data_checks.R` — all check functions now co-located
- [x] Fixed `.tchecks` numbering collision in `fd_flag_trips()` (04 and 05 were each used twice; renumbered to 01–08)
- [x] `gear`/`met6` defaults in `fd_flag_events()` and `fd_flag_eflalo()` changed from live `icesVocab::getCodeList()` calls to `NULL` (skipped by default); avoids network requests on every call
- [x] `1L:dplyr::n()` → `dplyr::row_number()` in both setup functions
- [x] `LE_CDAT` added to `required_cols` in `fd_clean_eflalo()`; `lubridate::dmy(LE_CDAT, tz = "UTC")` silently-ignored `tz` argument dropped
- [x] `fd_flag_eflalo()` overlap logic simplified: `.overlap = (.tchecks != "ok")` (was `ifelse(...)`)
- [x] `fd_flag_eflalo()` two separate `is.na()` arms for `FT_DDATIM`/`FT_LDATIM` collapsed to one with `|`
- [x] `fd_flag_tacsat()` group for `.intv` simplified to `group_by(VE_REF)` (was `VE_COU, VE_REF`)
- [x] `fd_flag_tacsat()` docs: corrected `fd_tacsat_clean()` → `fd_clean_tacsat()`; clarified `.intv` IS returned
- [x] `fd_events()` error message made actionable
- [x] README.Rmd: fixed `select(.checks)` → `select(-.checks)` bug in filtering example
- [ ] Post-distribution helpers: catch-per-unit-effort, swept area, ecosystem indicators
- [ ] Possibly extend `fd_split_among_pings()` to handle species-level columns (beyond TOT)
- [ ] Records with `NA` coordinates crash `fd_flag_tacsat()` silently — consider a pre-check guard
