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

## Data Dictionary (`data/dictionary.rda`)

A data dictionary covering all TACSAT2 and EFLALO2 fields, built from
`data-raw/DATASET_field_definitions.R`. Documented in `R/data.R`. Accessible
in R as `dictionary`.

**Columns:** `old` (ICES/raw name), `table` (`"tacsat"` / `"eflalo"`), `type` (R type post-cleaning), `format` (raw format), `description`, `required`, `derived`, `new` (output name after `fd_translate`).

**⚠️ Keep this in sync** when new columns are introduced by package functions — particularly:
- Preprocessing (`fd_clean_*`): derived columns like `time`, `T1`, `T2`, `t1`, `t2`, `.tsrc`, `eid`, `.tid`
- Analysis (`fd_add_trips()` and future functions): any columns appended to tacsat/eflalo during the analysis phase
- Post-distribution helpers (swept area, CPUE, etc.) once implemented

To update: edit `data-raw/DATASET_field_definitions.R` and re-run it (`source()` or `Rscript`).

## Key Concepts

**eflalo** — logbook records; one row per trip × day × ICES rectangle event. Catch columns are `LE_KG_{SPECIES}` and `LE_EURO_{SPECIES}`. Aggregated totals are `LE_KG_TOT` and `LE_EURO_TOT`.

**tacsat** — VMS ping records; one row per vessel × timestamp position. Key state column: `SI_STATE` (1 = fishing, 0 = non-fishing/steaming).

**Catch distribution problem** — logbook catch is reported at event level (trip/day/rectangle) but must be distributed proportionally across VMS pings to produce spatially explicit catch maps.

## R Source Files

| File | Key Functions | Notes |
|---|---|---|
| `R/data_clean.R` | `fd_check_input()`, `fd_clean_tacsat()`, `fd_clean_eflalo()`, `fd_revert_tacsat()`, `fd_revert_eflalo()` | Pre-processing & name revert; R-only (not duckdb-compatible) |
| `R/data_flag.R` | `fd_flag_tacsat()`, `fd_flag_trips()`, `fd_flag_events()`, `fd_flag_eflalo()` | QC / labelling; R-only (not duckdb-compatible) |
| `R/tidy_eflalo.R` | `fd_trips()`, `fd_events()`, `fd_tidy_eflalo()` | Extraction / decomposition helpers |
| `R/trail_steps.R` | `fd_step_time()` | Ping interval calculation |
| `R/analysis.R` | `fd_add_trips()` | Trip assignment; accepts output of `fd_clean_tacsat()` / `fd_trips()` |
| `R/geo.R` | `d2ir()`, `fd_calc_csq()`, `csq2lonlat()` | Coordinate/spatial utilities; `d2ir()` and `fd_calc_csq()` are dbplyr-compatible |
| `R/utils.R` | `fd_translate()` | Column name translation utility |
| `R/data.R` | Dataset documentation | |
| `R/globals.R` | Global variable declarations | |

## Setup Functions (`R/data_clean.R`)

### `fd_check_input(data, which)`
A generic preflight validator called internally by both `fd_clean_tacsat()` and `fd_clean_eflalo()`, and also exported for standalone use. Drives its logic entirely from `dictionary`:
- **Required fields** → `stop()` with the list of missing columns
- **Optional fields** absent → `message()` (processing continues)
- **Coercion safety**: tests `as.numeric()` on `dbl` fields and `lubridate::dmy()` on `date` fields — `warning()` if either would introduce new `NA`s
- Skips pattern fields (`LE_KG_<SP>`, `LE_EURO_<SP>`)
- Returns `data` invisibly; pipeable

⚠️ Both setup functions are **R-only** — `paste()`, `lubridate::dmy_hms()`, `lubridate::dmy()`, `row_number()`, and `consecutive_id()` are not duckdb-compatible. Marked with inline comments in source.

### `fd_clean_tacsat(tacsat, remove = TRUE)`
- Checks for: `VE_COU`, `VE_REF`, `SI_DATE`, `SI_TIME`, `SI_LATI`, `SI_LONG`, `SI_SP`, `SI_HE`
- Coerces `SI_LATI`, `SI_LONG`, `SI_SP`, `SI_HE` to numeric
- Creates `SI_DATIM` (POSIXct, UTC) from `SI_DATE` + `SI_TIME`; drops originals by default
- Adds `.pid` (integer row identifier) via `row_number()`; sorts by `VE_REF`, `SI_DATIM`
- Applies `fd_translate(dictionary)` at the end → output uses **new** names:

| Raw / internal | Output name |
|---|---|
| `VE_COU` | `cid` |
| `VE_REF` | `vid` |
| `SI_LATI` | `lat` |
| `SI_LONG` | `lon` |
| `SI_SP` | `speed` |
| `SI_HE` | `heading` |
| `SI_DATIM` | `time` |
| `.pid` | `pid` |

### `fd_clean_eflalo(eflalo, remove = TRUE)`
- Checks for: `VE_KW`, `VE_LEN`, `VE_TON`, `LE_MSZ`, `LE_CDAT`, `FT_DDAT`, `FT_DTIME`, `FT_LDAT`, `FT_LTIME`
- Creates `FT_DDATIM` (trip departure POSIXct), `FT_LDATIM` (trip landing POSIXct)
- Coerces `LE_CDAT` from `"DD/MM/YYYY"` character to R Date
- Coerces `KG`/`EURO` columns + `VE_KW`, `VE_LEN`, `VE_TON`, `LE_MSZ` to numeric
- Adds `.eid` (integer row identifier) and `.tid` (trip identifier via `consecutive_id()`)
- Removes raw date/time columns by default; sorts by `VE_COU`, `VE_REF`, `FT_DDATIM`, `FT_LDATIM`, `LE_CDAT`
- If `LE_STIME` and `LE_ETIME` are present, also derives `t1`, `t2`, `.tsrc`
- Applies `fd_translate(dictionary |> filter(table == "eflalo"))` at the end → output uses **new** names (selected):

| Raw / internal | Output name |
|---|---|
| `VE_REF` | `vid` |
| `VE_FLT` | `flt` |
| `VE_COU` | `cid` |
| `VE_LEN` | `length` |
| `VE_KW` | `kw` |
| `VE_TON` | `gt` |
| `FT_REF` | `tid` |
| `FT_DCOU` | `cid1` |
| `FT_DHAR` | `hid1` |
| `FT_DDATIM` | `T1` |
| `FT_LCOU` | `cid2` |
| `FT_LHAR` | `hid2` |
| `FT_LDATIM` | `T2` |
| `LE_ID` | `.sid` |
| `LE_CDAT` | `date` |
| `LE_GEAR` | `gear` |
| `LE_MSZ` | `mesh` |
| `LE_RECT` | `ir` |
| `LE_DIV` | `fao` |
| `LE_MET` | `met6` |
| `.eid` | `eid` |
| `.tid` | `.tid` (**not** renamed — avoids clash with `FT_REF → tid`) |
| `t1`, `t2`, `.tsrc`, `LE_STIME`, `LE_ETIME`, `LE_KG_*`, `LE_EURO_*` | unchanged |

⚠️ **Naming conflict**: `FT_REF` and `.tid` both map to `"tid"` in `field_definitions`. Resolution: `.tid` is excluded from the translate so `FT_REF` cleanly becomes `tid`. Fix the `new` value for `.tid` in `DATASET_field_definitions.R` if a public rename is desired.

## Revert Functions (`R/data_clean.R`)

Thin wrappers around `fd_translate()` that reverse the `new → old` name mapping for downstream code expecting ICES ALLCAPS column names.

### `fd_revert_tacsat(tacsat)`
- Input: output of `fd_clean_tacsat()` (short lowercase names)
- Calls `fd_translate(tacsat, dictionary |> filter(table == "tacsat"), from = "new", to = "old")`
- Only present columns are renamed; extras (e.g. `.intv`, `ir`) pass through unchanged
- `time → SI_DATIM`; `SI_DATE` (`"DD/MM/YYYY"`) and `SI_TIME` (`"HH:MM"`) are **reconstructed** from `SI_DATIM` via `format()` and placed immediately after it

### `fd_revert_eflalo(eflalo)`
- Input: output of `fd_clean_eflalo()` (short lowercase names)
- Calls `fd_translate(eflalo, dictionary |> filter(table == "eflalo"), from = "new", to = "old")`
- `tid → FT_REF` and `.tid → .tid` both revert cleanly (no exclusion needed)
- `FT_DDAT` / `FT_DTIME` and `FT_LDAT` / `FT_LTIME` are **reconstructed** from `FT_DDATIM` / `FT_LDATIM` via `format()` and placed immediately after their source column
- Extra columns (`t1`, `t2`, `.tsrc`, `LE_KG_*`, `LE_EURO_*`, etc.) pass through unchanged

## Check Functions (`R/data_flag.R`)

All check functions **never filter** — they add a labelled check column and leave filtering to the caller. All are **R-only** (sf joins, `duplicated()` not duckdb-compatible; marked with inline comments).

### `fd_flag_tacsat(tacsat, minimum_interval_seconds = 30, area, harbours)`
- Expects output of `fd_clean_tacsat()` — uses new column names (`lon`, `lat`, `vid`, `cid`, `time`, `speed`)
- Computes `.intv` (seconds since last ping via `fd_step_time()`, grouped by `vid`)
- Adds `.checks` and `.intv` columns; checks 00–08 plus `"ok"`:
  - `"00 missing coordinates"`: `lon`/`lat` is `NA` — split out before spatial ops, rejoined with this label
  - 01–08: area, duplicate, interval, harbour, missing ID/datetime/speed checks

### `fd_flag_trips(trips)`  ← moved here from `tidy_eflalo.R`
- Input: trips data frame from `fd_trips()` — uses new column names (`cid`, `vid`, `T1`, `T2`, `length`, `kw`)
- Adds `.tchecks` column; checks 01–08 plus `"ok"`
- Checks: `T1`/`T2` missing, `T1 > T2`, `T1 == T2`, temporal overlaps (lead/lag), missing `length`/`kw`

### `fd_flag_events(events, gear = NULL, met6 = NULL)`
- Input: events data frame from `fd_events()` — uses new column names (`lid`, `date`, `gear`, `met6`, `t1`, `t2`)
- Adds `.echecks` column; checks 01–08 plus `"ok"`:
  - 01–03: duplicate event id, invalid gear, invalid metier (gear/metier skipped if `NULL`)
  - 04–08: `t1`/`t2` temporal checks (missing, inverted, overlap) — only applied when `t1`/`t2` are present
- Overlap detection (check 08) uses **cumulative-max of `t2`** within each trip rather than lead/lag-of-1, so all cascading overlaps are resolved in a single pass
- Events are sorted by `.tid, t1` at the start of the function before any checks are applied
- Defaults for `gear`/`met6` are `NULL` (checks skipped); pass `icesVocab::getCodeList(...)$Key` to enable
- ⚠️ `.data$gear` / `.data$met6` / `.data$date` pronouns used in `case_when()` to avoid name shadowing
- ⚠️ Catch-date range checks are NOT performed here; use `fd_flag_eflalo()` for that
- ⚠️ Check 08 (overlap) may produce false positives for static gears with simultaneous deployments

### `fd_flag_eflalo(eflalo, year = NULL, gear = NULL, met6 = NULL)`
- Delegates overlap detection to `fd_trips()` + `fd_flag_trips()`, joins back on `cid, vid, length, kw, gt, tid, T1, T2`
- Adds `.checks` column; checks 01–12 plus `"ok"`
- Defaults for `gear`/`met6` are `NULL` (checks skipped); pass `icesVocab::getCodeList(...)$Key` to enable
- Uses `.data$` pronoun for `date`, `gear`, `met6`, `length` to avoid shadowing by base R functions or parameters

## `fd_calc_csq()` and `csq2lonlat()` (`R/geo.R`)

### `fd_calc_csq(lon, lat, degrees = 0.05)`
Encodes decimal-degree coordinates as a c-square code (c-squares spec v1.1, Rees 2005).
- Supports all standard resolutions: `10`, `5`, `1`, `0.5`, `0.1`, `0.05`, `0.01`
- Returns `NA_character_` for `NA` inputs
- **dbplyr-compatible**: uses only `floor()`, `abs()`, `round()`, integer arithmetic, `paste0()`, `as.integer()` / `as.character()` — all translate to SQL. Works inside `dplyr::mutate()` on lazy DuckDB / `duckdbfs` tables.
- ~2× faster and uses ~65% less memory than the vmstools `CSquare()` it replaces (no intermediate 3D array)

### `csq2lonlat(csq, degrees = 0.05)`
Decodes a c-square code to the **centre coordinates** of the cell at the requested resolution.
- Returns a `data.frame` with columns `lat` and `lon` (decimal degrees, WGS84)
- **R-only** (returns a `data.frame`; not compatible with `dplyr::mutate()` on lazy tables)
- Returns exact cell centres; the vmstools `CSquare2LonLat()` it replaces returns centres offset by ~1e-5° due to an Excel-rounding hack (`ra = 1e-6`)
- Input codes must be at the requested `degrees` resolution or finer

## `fd_step_time()` (`R/trail_steps.R`)

Computes time interval (seconds) between consecutive pings as a weighted blend of backward and forward differences. Used internally by `fd_flag_tacsat()`. Call within `group_by(vid)` + `mutate()` (vessel grouping column is now `vid` after `fd_clean_tacsat()`).

## `fd_add_trips()` (`R/analysis.R`)

Joins VMS/AIS pings (`ais`) with trip windows (`trips`) by vessel identity and time overlap. Signature: `fd_add_trips(ais, trips, cn = "tid", remove = TRUE)`.

- `ais`: output of `fd_clean_tacsat()` — requires `cid`, `vid`, `time`
- `trips`: output of `fd_trips()` — requires `cid`, `vid`, `tid`, `T1`, `T2`
- `cn`: columns to carry across from `trips`; `"tid"` is always included; extras validated before the join
- Row-count guard stops with an informative message if overlapping trips cause a ping to match more than one trip (directs user to `fd_flag_trips()`)

## `R/tidy_eflalo.R` — Trip / Event decomposition

Contains three functions; `fd_flag_trips()` and `fd_flag_events()` have been **moved to `R/data_checks.R`**.

### `fd_trips(eflalo)`
- Selects `.tid, vid, flt, cid, length, kw, gt, tid, cid1, hid1, T1, cid2, hid2, T2`; returns distinct rows (one row per trip)
- Requires `.tid` added (but not renamed) by `fd_clean_eflalo()`

### `fd_events(eflalo)`
- Selects `eid, .sid, date`, optional event coords (`lat1, lon1, lat2, lon2`) and gear columns (`gear, mesh, ir, fao, met6`), `starts_with("LE_")` (catches `LE_STIME`, `LE_ETIME`, `LE_KG_*`, `LE_EURO_*`), optional `t1, t2, .tsrc`, and `.tid`
- Errors with a helpful message if rows decrease after `distinct()` (duplicate events detected)
- Requires `eid` and `.tid` from `fd_clean_eflalo()`
- `t1`, `t2`, `.tsrc` are derived by `fd_clean_eflalo()` (not here) and passed through. Derivation logic (uses raw column names before translate):

| `.tsrc` | Condition | `t1` | `t2` |
|---|---|---|---|
| `"data"` | All three present; `LE_STIME ≤ LE_ETIME` | `date` + `LE_STIME` | `date` + `LE_ETIME` |
| `"next day"` | All three present; `LE_STIME > LE_ETIME` | `date` + `LE_STIME` | `(date + 1)` + `LE_ETIME` |
| `"dummy"` | `date` present; one or both times `NA` | `date 00:01` | `date 23:59` |
| `NA` | `date` is `NA` | `NA` | `NA` |

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

Active vignettes live under `vignettes/articles/`:

| File | Description |
|---|---|
| `technical_clean-and-flag.Rmd` | Walkthrough of `fd_clean_*` and `fd_flag_*` functions |
| `technical_merging.Rmd` | Merging EFLALO and TACSAT: technical documentation |
| `ices-rectangle-bug.Rmd` | Documents the ICES rectangle zone-A coordinate bug |

Draft / scratch articles live under `_articles/` (not built as package vignettes):

| File | Description |
|---|---|
| `catch-distribution.Rmd` | End-to-end catch distribution pipeline (in progress) |
| `under_the_hood.Rmd` | Internal design notes |
| `implementation-comparison.Rmd` | Historical comparison of split implementations (superseded) |
| `spreading_fish-and-cash.Rmd` | Legacy scratch article (superseded) |

## Tests

| File | What is tested |
|---|---|
| `tests/testthat/test-data_checks.R` | `fd_flag_eflalo()` overlap detection: overlapping trip labelled `"06 - overlapping trips"`, earlier trip and non-overlapping vessel pass as `"ok"` |

## Outstanding Work

- [x] **`fd_add_trips()` updated** to accept output of `fd_clean_tacsat()` / `fd_trips()` directly (short lowercase names). Signature: `fd_add_trips(ais, trips, cn = "tid", remove = TRUE)`. `tid` is always carried across; `cn` adds optional extra columns from `trips`. Both inputs are validated before the join. Row-count guard catches overlapping trips with an informative message directing the user to `fd_flag_trips()`.
- [x] **Resolved `.tid`/`FT_REF → tid` naming conflict in `dictionary`**: `.tid` now maps `new = ".tid"` in `DATASET_field_definitions.R`; `FT_REF → tid` is unambiguous. Workaround filter `old != ".tid"` removed from `fd_clean_eflalo()` and `fd_revert_eflalo()`.
- [ ] Implement catch distribution (`fd_split_among_pings()`) — see `_articles/catch-distribution.Rmd` for design notes
- [ ] Post-distribution helpers: catch-per-unit-effort, swept area, ecosystem indicators
- [x] Records with `NA` coordinates crash `fd_flag_tacsat()` silently — pre-check guard added: NA-coord records are split out before `st_as_sf()`, labelled `"00 missing coordinates"`, and rejoined to the output

### Completed

- [x] `fd_clean_tacsat()` and `fd_clean_eflalo()`: column names translated from ICES ALLCAPS to short lowercase via `fd_translate()`. All internal references in `data_flag.R` and `tidy_eflalo.R` updated accordingly.
- [x] `fd_revert_tacsat()` and `fd_revert_eflalo()` implemented; reconstruct split date/time columns (`SI_DATE`/`SI_TIME`, `FT_DDAT`/`FT_DTIME`, `FT_LDAT`/`FT_LTIME`) from their POSIXct counterparts via `format()`
- [x] `fd_flag_trips()` and `fd_flag_events()` moved from `tidy_eflalo.R` to `data_flag.R` — all check functions now co-located
- [x] Fixed `.tchecks` numbering collision in `fd_flag_trips()` (04 and 05 were each used twice; renumbered to 01–08)
- [x] `gear`/`met6` defaults in `fd_flag_events()` and `fd_flag_eflalo()` changed from live `icesVocab::getCodeList()` calls to `NULL` (skipped by default); avoids network requests on every call
- [x] `fd_flag_eflalo()` overlap logic and NA checks simplified
- [x] `fd_flag_tacsat()` grouping simplified to `group_by(vid)`; docs corrected
- [x] `fd_events()` error message made actionable
- [x] `LE_CDAT` added to required cols in `fd_clean_eflalo()`
