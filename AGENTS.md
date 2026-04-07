# osfd — Agent Memory File

## Package Overview

**osfd** (`Spatial Fisheries Data Tools`) consolidates functions for the ICES WGSFD VMS and logbook data-call workflow. The primary author is Einar Hjörleifsson.

- GitHub: https://github.com/einarhjorleifsson/osfd
- Core dependencies: `dplyr`, `tidyr`, `lubridate`, `sf`
- Optional (Suggests): `duckdbfs`, `icesConnect`, `icesVMS`, `vmstools`, `sfdSAR`, `stringr`, `testthat`, `tibble`, `knitr`, `rmarkdown`
- `icesVocab` — listed in `Remotes` but not in `Imports` or `Suggests`. Used only in documentation examples (`icesVocab::getCodeList()`) and `data-raw/`. No package source code calls it directly. Should be added to `Suggests`.
- `stringr` — present in `Suggests` in DESCRIPTION but not used anywhere in `R/` source files. Likely a leftover; candidate for removal.

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
- Preprocessing (`fd_clean_*`): derived columns like `time`, `T1`, `T2`, `t1`, `t2`, `.tsrc`, `.eid`, `.tid`
- Analysis (`fd_add_trips()` and future functions): any columns appended to tacsat/eflalo during the analysis phase
- Post-distribution helpers (swept area, CPUE, etc.) once implemented

To update: edit `data-raw/DATASET_field_definitions.R` and re-run it (`source()` or `Rscript`).

## Key Concepts

### tacsat

**tacsat** — VMS ping records; one row per vessel × timestamp position.

### eflalo

Fundamentally split **eflalo** into **trips** and **events** at the start of the process.

**trips**: trip (and vessel) records: one row per vessel trip - marked as `.tid`
  * Hence a vessel should never have overlapping T1 and T2

**events**: one row per gear × day × ICES rectangle for a given vessel trip.
  * Ideally each event should be a distinct row in the event table — in these cases `t1` and `t2` would be recorded in the imported eflalo data, and `.eid` (a simple row counter) would also serve as a unique semantic event identifier
  * In practice `t1` and `t2` are often not recorded — just the date (`LE_CDAT`). Within that date there may then be multiple combinations of gear × mesh × `ir` rows for the same trip
  * The downstream code assumes that when `t1` and `t2` are not recorded there is only one event per `.tid × gear × date × ir`
  * Any data that violates this assumption should be flagged when user calls functions that depend on it
  * In such cases the code should take the record with the highest `LE_KG_TOT` and warn the user
    
**eflalo** — retained for historical reasons and should not be used as the primary working structure. In downstream processing it should always be reconstructed from `trips` and `events`. One row per trip × gear × day × ICES rectangle event.



**Catch distribution problem** — logbook catch is reported at event level (trip/day/rectangle) but must be distributed proportionally across VMS pings to produce spatially explicit catch maps.

## Naming Conventions

**Dot-prefix columns** — a leading `.` on a column name signals that the column was generated inside a package function, not present in the raw input. This makes it easy to distinguish derived columns from raw data columns at a glance.

| Column | Added by | Purpose |
|---|---|---|
| `.pid` | `fd_clean_tacsat()` | Integer row identifier for tacsat pings |
| `.eid` | `fd_clean_eflalo()` | Integer row counter (`row_number()`); serves as a unique event identifier when data are clean (one row per `.tid × gear × date × ir`), but is just a row number when duplicates are present |
| `.tid` | `fd_clean_eflalo()` | Integer trip identifier via `consecutive_id()` |
| `.tsrc` | `fd_clean_eflalo()` | Source of `t1`/`t2` derivation (`"data"`, `"next day"`, `"dummy"`, `NA`) |
| `.intv` | `fd_flag_tacsat()` | Seconds since previous ping (per vessel) |
| `.checks` | `fd_flag_tacsat()`, `fd_flag_eflalo()` | First failing QC label, or `"ok"` |
| `.tchecks` | `fd_flag_trips()` | First failing trip-level QC label, or `"ok"` |
| `.echecks` | `fd_flag_events()` | First failing event-level QC label, or `"ok"` |

Columns added temporarily inside a function and dropped before returning (e.g. `.in`, `.in_harbour`, `.prev_max_t2`, `.overlap`, `.t1_str`, `.t2_str`) follow the same convention — the dot signals they are not part of the public output.

## R Source Files

| File | Key Functions | Notes |
|---|---|---|
| `R/data_clean.R` | `fd_check_input()`, `fd_clean_tacsat()`, `fd_clean_eflalo()`, `fd_revert_tacsat()`, `fd_revert_eflalo()` | Pre-processing & name revert; R-only (not duckdb-compatible) |
| `R/data_flag.R` | `fd_flag_tacsat()`, `fd_flag_trips()`, `fd_flag_events()`, `fd_flag_eflalo()` | QC / labelling; R-only (not duckdb-compatible) |
| `R/tidy_eflalo.R` | `fd_trips()`, `fd_events()`, `fd_tidy_eflalo()` | Extraction / decomposition helpers |
| `R/trail_steps.R` | `fd_step_time()`, `fd_interval_seconds()` | Ping interval calculation |
| `R/add_to_pings.R` | `fd_add_trips()`, `fd_add_events()`, `fd_check_events_join()` | Ping enrichment: trip and event joins |
| `R/gear.R` | `fd_benthis_lookup()`, `fd_add_gearwidth()`, `fd_add_sa()` | Gear width prediction and swept area |
| `R/geo.R` | `d2ir()`, `fd_calc_csq()`, `csq2lonlat()`, `csq_area()`, `fd_add_sf()` | Coordinate/spatial utilities; `d2ir()` and `fd_calc_csq()` are dbplyr-compatible; `fd_add_sf()` is R-only |
| `R/state.R` | `fd_add_state()` | Ping state classification (fishing vs. steaming) — stub |
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
| `.pid` | `.pid` (**not** renamed — `fd_translate()` maps `.pid → .pid`; name is stable) |

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
| `LE_ID` | `lid` |
| `LE_CDAT` | `date` |
| `LE_GEAR` | `gear` |
| `LE_MSZ` | `mesh` |
| `LE_RECT` | `ir` |
| `LE_DIV` | `fao` |
| `LE_MET` | `met6` |
| `.eid` | `.eid` (**not** renamed — `fd_translate()` does not touch it; used as the internal event row key by `fd_events()` and `fd_flag_eflalo()`) |
| `.tid` | `.tid` (**not** renamed — avoids clash with `FT_REF → tid`) |
| `t1`, `t2`, `.tsrc`, `LE_STIME`, `LE_ETIME`, `LE_KG_*`, `LE_EURO_*` | unchanged |

**Naming note**: `FT_REF` and `.tid` previously both mapped to `"tid"` in `field_definitions`. Resolved: `.tid` now maps `new = ".tid"` in `DATASET_field_definitions.R`, making the rename a no-op — `FT_REF` cleanly becomes `tid` and `.tid` stays `.tid`.

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

All check functions are **R-only** (`sf` joins, `duplicated()` not duckdb-compatible; marked with inline comments).

All four functions share a `no_hands` parameter:
- `no_hands = TRUE` (**default, production**): failing records are filtered out and the check column is dropped before returning
- `no_hands = FALSE` (**diagnostic**): all records are returned with the check column appended

### `fd_flag_tacsat(tacsat, minimum_interval_seconds = 30, areas, ports, no_hands = TRUE)`
- Expects output of `fd_clean_tacsat()` — uses new column names (`lon`, `lat`, `vid`, `cid`, `time`, `speed`)
- Computes `.intv` (seconds since last ping via `fd_step_time()`, grouped by `vid`)
- When `no_hands = FALSE`: adds `.checks` and `.intv`; checks 00–08 plus `"ok"`:
  - `"00 missing coordinates"`: `lon`/`lat` is `NA` — split out before spatial ops, rejoined with this label
  - 01–08: area, duplicate, interval, harbour, missing country ID/vessel ID/datetime/speed checks
- When `no_hands = TRUE`: returns only passing rows; both `.checks` and `.intv` are dropped

### `fd_flag_trips(trips, no_hands = TRUE)`
- Input: trips data frame from `fd_trips()` — uses new column names (`cid`, `vid`, `T1`, `T2`, `length`, `kw`)
- When `no_hands = FALSE`: adds `.tchecks`; checks 01–09 plus `"ok"`:

| Check | Label |
|---|---|
| 01 | `"01 departure missing"` — `T1` is `NA` |
| 02 | `"02 arrival missing"` — `T2` is `NA` |
| 03 | `"03 new years trip"` — `year(T1) == year(T2) - 1` (trip crosses year boundary) |
| 04 | `"04 departure after arrival"` — `T1 > T2` |
| 05 | `"05 departure equals arrival"` — `T1 == T2` |
| 06 | `"06 next departure before current arrival"` — temporal overlap (lead) |
| 07 | `"07 previous arrival after current departure"` — temporal overlap (lag) |
| 08 | `"08 no vessel length"` — `length` is `NA` |
| 09 | `"09 no engine power"` — `kw` is `NA` |

- When `no_hands = TRUE`: returns only passing trips; `.tchecks` dropped
- Grouped by `cid, vid`; overlap checks use `lead()`/`lag()` within group

### `fd_flag_events(events, no_hands = TRUE, gear = NULL, met6 = NULL)`
- Input: events data frame from `fd_events()` — uses new column names (`lid`, `date`, `gear`, `met6`, `t1`, `t2`)
- When `no_hands = FALSE`: adds `.echecks`; checks 01–08 plus `"ok"`:

| Check | Label |
|---|---|
| 01 | `"01 duplicate event id and catch date"` — same `lid` + `date`; ⚠️ this checks the stated event ID (`lid`) not the semantic event key (`.tid × gear × date × ir`) — see Outstanding Work |
| 02 | `"02 gear (metier 4) invalid"` — skipped if `gear = NULL` |
| 03 | `"03 metier 6 invalid"` — skipped if `met6 = NULL` |
| 04–08 | `t1`/`t2` temporal checks — only applied when those columns are present **and** `.tsrc != "dummy"`; dummy times are synthetic placeholders and carry no real temporal information |

- Overlap detection (check 08) uses **cumulative-max of `t2`** within each trip (`.tid` group) rather than lead/lag-of-1, handling cascading overlaps in a single pass
- Events are sorted by `.tid, t1` at the start of the function before any checks are applied
- ⚠️ `.data$gear` / `.data$met6` / `.data$date` pronouns used in `case_when()` to avoid name shadowing
- ⚠️ Catch-date range checks are NOT performed here; use `fd_flag_eflalo()` for that
- ⚠️ Check 08 (overlap) may produce false positives for static gears with simultaneous deployments
- ⚠️ Multiple rows with the same `.tid × gear × date × ir` (soft duplicates, different catch values) are not detected here — this is a known gap, see Outstanding Work

### `fd_flag_eflalo(eflalo, no_hands = TRUE, gear = NULL, met6 = NULL)`
An orchestrating wrapper — does not re-implement any check logic itself. Instead:
1. Runs `fd_flag_trips(no_hands = FALSE)` on `fd_trips(eflalo)` → joins `.tchecks` back via `.tid`
2. Runs `fd_flag_events(no_hands = FALSE, gear, met6)` on `fd_events(eflalo)` → joins `.echecks` back via `.eid`
3. Composes `.checks` in priority order:
   - Trip failure → inherit trip label (propagates to all events on that trip)
   - Event failure → inherit event label
   - `"catch date before departure"` — `date < as_date(T1)` (cross-level; requires full eflalo)
   - `"catch date after arrival"` — `date > as_date(T2)` (cross-level; requires full eflalo)
   - `"ok"`
4. Drops `.tchecks` and `.echecks`; applies `no_hands` filter

**Numbering note:** `.checks` labels are inherited verbatim from sub-functions, so the same number prefix (e.g. `"07"`) can appear from both `fd_flag_trips` and `fd_flag_events`. Labels are always self-describing, so this is not ambiguous in practice.

**⚠️ Duplicate records and `fd_events()`:** `fd_events()` errors if the eflalo data frame contains exact duplicate rows. Consequently, the `"01 duplicate event id and catch date"` check in `fd_flag_events` cannot trigger through `fd_flag_eflalo`. If upstream data may have exact duplicates, call `dplyr::distinct(eflalo)` before `fd_flag_eflalo()`, or use `fd_flag_events()` directly on `fd_events()` output.

**Note:** The `year` parameter that appeared in earlier versions was never implemented and has been removed.

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

### `csq_area(csq, resolution = NULL)`
Returns the geodetic area (km²) of a c-square cell using a spherical-Earth approximation.

- Area formula: `resolution² × cos(lat × π/180) × 111.1942²`, where `lat` is the cell-centre latitude from `csq2lonlat()`
- `resolution` can be supplied explicitly or inferred automatically from `nchar(csq)`:

| `nchar(csq)` | Resolution |
|---|---|
| 4  | 10°   |
| 6  | 5°    |
| 8  | 1°    |
| 10 | 0.5°  |
| 12 | 0.1°  |
| 14 | 0.05° |
| 16 | 0.01° |

- All codes in a vector must share the same resolution; supply `resolution` explicitly if that cannot be guaranteed
- Returns `NA` where `csq` is `NA`
- **R-only** (calls `csq2lonlat()`)

### `fd_add_sf(ais, shape)`
Spatially joins an `sf` polygon layer onto AIS/VMS pings. Converts `ais` to an `sf` point object (using `lon` / `lat`, CRS 4326) if not already `sf`, then applies `sf::st_join()`. S2 geometry is disabled for the duration of the call and restored on exit.
- `shape` must be an `sf` object (stops with an error otherwise)
- Row-count guard: stops if the join inflates the row count (i.e. `shape` contains overlapping polygons producing a one-to-many match)
- **Returns** an `sf` object with the same row count as `ais`, augmented with columns from `shape`
- ⚠️ Error message on row-count failure is currently a placeholder (`"Screeeeeam"`); needs improvement
- **R-only**

## `fd_step_time()` and `fd_interval_seconds()` (`R/trail_steps.R`)

### `fd_step_time(datetime, weight = c(1, 0), fill_na = TRUE)`
Computes time interval (seconds) between consecutive pings as a weighted blend of backward and forward differences. Used internally by `fd_flag_tacsat()` and `fd_interval_seconds()`. Call within `group_by(vid)` + `mutate()` (vessel grouping column is now `vid` after `fd_clean_tacsat()`).

### `fd_interval_seconds(time, probs = 0.975)`
Computes ping intervals via `fd_step_time()`, then caps any value exceeding the `probs` quantile of the computed intervals. Intended to be called within `group_by(.tid)` + `mutate()` during the processing stage to produce the `.intv` column used by `fd_add_sa()`.

| Parameter | Default | Notes |
|---|---|---|
| `time` | — | POSIXct datetime vector, sorted chronologically within groups |
| `probs` | `0.975` | Quantile used as the upper cap (scalar in `[0, 1]`) |

## `R/gear.R` — Gear width and swept area

All three functions carry `@source` attribution to the ICES VMS and Logbook Data Call workflow (https://github.com/ices-eg/ICES-VMS-and-Logbook-Data-Call). Requires `sfdSAR` and `icesVMS` (optional dependencies).

### `fd_benthis_lookup(kw_name = "kw", oal_name = "length")`
Fetches the RCG métier reference list from GitHub (`ices-eg/RCGs`) and joins it with BENTHIS gear-width parameters from `icesVMS::get_benthis_parameters()`. The `gearCoefficient` sentinel values (`"avg_kw"`, `"avg_oal"`) are replaced with the actual column names (`kw_name`, `oal_name`) so that `sfdSAR::predict_gear_width()` can address them directly.

- **Returns**: data frame keyed on `Metier_level6` with columns: `benthisMet`, `avKw`, `avLoa`, `avFspeed`, `subsurfaceProp`, `gearWidth`, `firstFactor`, `secondFactor`, `gearModel`, `gearCoefficient`, `contactModel`.
- ⚠️ Requires internet access at runtime.

### `fd_add_gearwidth(x, met_name = "met6", oal_name = "length", kw_name = "kw")`
Predicts gear contact width (km) for each VMS ping using the BENTHIS model via `sfdSAR::predict_gear_width()` and appends `.gearwidth`. Fill priority:

1. User-supplied `LE_GEARWIDTH` column (if present and not `NA`)
2. Model prediction (metres → km)
3. BENTHIS lookup-table default (`gearWidth`)

- **Returns**: `x` with one additional column `.gearwidth` (numeric, km); `NA` where unavailable.
- Calls `fd_benthis_lookup()` internally; requires internet access at runtime.

### `fd_add_sa(x, gear_name = "gear", intv_name = ".intv", gearwidth_name = ".gearwidth", speed_name = "speed")`
Calculates swept area (km²) per VMS ping via `sfdSAR::predict_surface_contact()`. Dispatch by gear type:

| Gear | Model | Notes |
|---|---|---|
| `SDN` | `danish_seine_contact()` | Rope-loop geometry |
| `SSC` | `scottish_seine_contact()` | Rope-loop geometry with splitting-phase multiplier |
| All others | `trawl_contact()` | `SA = gear_width × fishing_hours × fishing_speed × 1.852` |

- `intv_name` column is expected in **seconds**; the function divides by 3600 internally.
- An intermediate `.model` column is created during dispatch and dropped before returning.
- **Returns**: `x` with one additional column `.sa` (numeric, km²); `NA` where gear width or speed unavailable.
- Typical usage: chain after `fd_add_gearwidth()` in a pipeline.

---

## `R/state.R` — Ping state classification

### `fd_add_state(ais, speed_table)` ⚠️ stub
Classifies each VMS ping as `"fishing"` or `"something else"` based on whether its speed falls within the gear-specific thresholds in `speed_table`.

- `speed_table`: a data frame with columns `gear`, `target`, `s1` (lower speed threshold, knots), `s2` (upper speed threshold, knots)
- Joins `speed_table` to `ais` (by `gear`/`target`; join key not yet explicitly enforced), evaluates `dplyr::between(speed, s1, s2)`, drops `s1`/`s2` before returning
- **Returns**: `ais` with a `state` character column appended
- ⚠️ The function is a working stub: the join key, the fallback label (`"something else"`), and parameter documentation are all provisional

---

## `R/add_to_pings.R` — Ping enrichment

### `fd_add_trips(ais, trips, cn = "tid", remove = TRUE)`

Joins VMS/AIS pings (`ais`) with trip windows (`trips`) by vessel identity and time overlap.

- `ais`: output of `fd_clean_tacsat()` — requires `cid`, `vid`, `time`
- `trips`: output of `fd_trips()` — requires `cid`, `vid`, `tid`, `T1`, `T2`
- `cn`: columns to carry across from `trips`; `"tid"` and `".tid"` are always included; extras validated before the join
- Row-count guard stops with an informative message if overlapping trips cause a ping to match more than one trip (directs user to `fd_flag_trips()`)

### `fd_add_events(ais, events, resolve = FALSE)`

Joins pings (after `fd_add_trips()`) with fishing events by `.tid` and time interval (`between(time, t1, t2)`). All event columns are carried across; pings outside any event window receive `NA`.

- `ais`: output of `fd_add_trips()` — requires `.tid` and `time`
- `events`: output of `fd_events()` / `fd_flag_events()` — requires `.tid`, `t1`, `t2`
- Intended relationship is many-to-one: each ping should fall within at most one event window per trip
- Row-count guard stops with an informative error if any ping matches more than one event, directing to `fd_check_events_join()` and suggesting `resolve = TRUE`
- `resolve = FALSE` (default): stops on any conflict
- `resolve = TRUE`: attempts automatic resolution of dummy-time conflicts before joining — for each `.tid × date` group with multiple dummy events, keeps the one with the highest `LE_KG_TOT` (first record by `.eid` on ties); non-dummy events are never dropped; a message reports how many events were removed. If conflicts persist after resolution (non-dummy overlapping windows), the function still errors.
- ⚠️ `resolve = TRUE` requires a `.tsrc` column in `events`; stops with an informative error if absent
- ⚠️ Events with `.tsrc = "dummy"` span the full day (`t1 = 00:01`, `t2 = 23:59`). If multiple events share the same date within a trip, every ping on that date will match all of them — a many-to-many conflict the guard will catch; use `resolve = TRUE` for automatic handling

### `fd_check_events_join(ais, events)`

Developer diagnostic for `fd_add_events()` join conflicts. Performs the join without a relationship constraint and returns only the rows where a ping matched more than one event (each such ping appears once per matched event).

- Makes no assumptions about the *cause* of the conflict — surfaces whatever produces the bloat (overlapping real times, identical dummy windows, soft duplicates, etc.)
- Prints a summary message: number of affected pings and trips, plus a hint to use `resolve = TRUE` if dummy-time events are the cause
- Returns an empty tibble invisibly (with a message) when no conflicts exist
- Typical usage after `fd_add_events()` errors:
  ```r
  conflicts <- fd_check_events_join(ais2, events)
  conflicts |> count(.tid, t1, t2, sort = TRUE)   # which windows conflict?
  conflicts |> distinct(.tid, t1, t2, .eid)        # which events share a window?
  ```

## `R/tidy_eflalo.R` — Trip / Event decomposition

Contains three functions. `fd_flag_trips()` and `fd_flag_events()` live in `R/data_flag.R`.

### `fd_trips(eflalo)`
- Selects `.tid, vid, flt, cid, length, kw, gt, tid, cid1, hid1, T1, cid2, hid2, T2`; returns distinct rows (one row per trip)
- Requires `.tid` added (but not renamed) by `fd_clean_eflalo()`

### `fd_events(eflalo)`
- Selects `.eid, lid, date`, optional event coords (`lat1, lon1, lat2, lon2`) and gear columns (`gear, mesh, ir, fao, met6`), `starts_with("LE_")` (catches `LE_STIME`, `LE_ETIME`, `LE_KG_*`, `LE_EURO_*`), optional `t1, t2, .tsrc`, and `.tid`
- Errors with a helpful message if rows decrease after `distinct()` — this catches exact duplicate rows (all selected columns identical), but does **not** detect the softer violation where multiple rows share the same `.tid × gear × date × ir` with different catch values (see Outstanding Work)
- Requires `.eid` and `.tid` from `fd_clean_eflalo()` (both are internal integer identifiers that are **not** renamed by `fd_translate()`)
- `t1`, `t2`, `.tsrc` are derived by `fd_clean_eflalo()` (not here) and passed through. Derivation logic (uses raw column names before translate):

| `.tsrc` | Condition | `t1` | `t2` |
|---|---|---|---|
| `"data"` | All three present; `LE_STIME ≤ LE_ETIME` | `date` + `LE_STIME` | `date` + `LE_ETIME` |
| `"next day"` | All three present; `LE_STIME > LE_ETIME` | `date` + `LE_STIME` | `(date + 1)` + `LE_ETIME` |
| `"dummy"` | `date` present; one or both times `NA` | `date 00:01` | `date 23:59` |
| `NA` | `date` is `NA` | `NA` | `NA` |

### `fd_tidy_eflalo(eflalo)`
- Convenience wrapper returning `list(trips = fd_trips(eflalo), events = fd_events(eflalo))`

## Typical Pipeline

The pipeline has three stages: **pre-processing**, **processing**, and **submission**. Pre-processing is complete. Processing functions are partially implemented (`fd_add_state()` is a working stub; `fd_add_sf()` is implemented). Submission functions are not yet implemented.

The eflalo data is split into `trips` and `events` early and kept separate throughout. The cleaned VMS data is conventionally named `ais`.

The flag functions support a "user interference" pattern: call with `no_hands = FALSE` to retain the check column, inspect failures, then filter and drop it manually. This is the intended interactive workflow. For fully automated pipelines, the `no_hands = TRUE` default handles filtering and column removal in one step.

```r
library(sf)
library(arrow)
library(tidyverse)
library(osfd)

# Spatial assets required by fd_flag_tacsat()
ports <- read_sf("...") |> select(port = pid)   # point layer, buffered to 3 km internally
areas <- read_sf("data-raw/ices_areas.gpkg") |> select(area = Area_27)

# Fishing speed lookup used in processing stage (gear + target → speed thresholds s1, s2)
state_lookup <- read_parquet("...") |> select(gear, target, s1, s2)

# Raw data
eflalo <- read_parquet("data-raw/eflalo_IS.parquet")
tacsat <- read_parquet("data-raw/tacsat_IS.parquet")

# ── Pre-processing ────────────────────────────────────────────────────────────

# VMS pings → ais
ais <- tacsat |>
  fd_clean_tacsat() |>
  fd_flag_tacsat(areas = areas, ports = ports, no_hands = FALSE)
ais |> count(.checks, sort = TRUE)             # inspect failures
ais <- filter(ais, .checks == "ok") |> select(-.checks)

# Logbook → trips + events (clean once, decompose twice)
eflalo_clean <- fd_clean_eflalo(eflalo)

trips <- eflalo_clean |>
  fd_trips() |>
  fd_flag_trips(no_hands = FALSE)
trips |> count(.tchecks, sort = TRUE)          # inspect failures
trips <- filter(trips, .tchecks == "ok") |> select(-.tchecks)

events <- eflalo_clean |>
  fd_events() |>
  fd_flag_events(no_hands = FALSE)
events |> count(.echecks, sort = TRUE)         # inspect failures
events <- filter(events, .echecks == "ok") |> select(-.echecks)

# ── Processing (partially pending) ───────────────────────────────────────────

ais2 <- ais |>
  fd_add_trips(trips, cn = c("tid", "length", "kw", "gt", ".tid")) |>
  fd_add_events(events) |>
  fd_add_state(state_lookup) |>   # stub — classifies pings as fishing/steaming
  filter(state == "fishing") |>
  group_by(.tid) |>
  mutate(.intv = fd_interval_seconds(time)) |>
  ungroup() |>
  fd_add_gearwidth() |>
  fd_add_sa() |>
  fd_add_sf(eusm) |>              # spatial join to habitat layer
  mutate(csq = fd_calc_csq(lon, lat))

# ── Submission (pending) ──────────────────────────────────────────────────────

ais2 |> fd_final_tests() |> fd_aggregate() |> fd_export_table1()
ais2 |> fd_final_tests() |> fd_aggregate() |> fd_export_table2()
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

No test files exist yet. The `tests/testthat/` directory is empty.

## Outstanding Work

- [ ] Implement catch distribution (`fd_split_among_pings()`) — see `_articles/catch-distribution.Rmd` for design notes
- [ ] Post-distribution helpers: catch-per-unit-effort, ecosystem indicators (swept area implemented: `fd_add_gearwidth()` + `fd_add_sa()`)
- [ ] **`fd_add_state()` needs hardening**: finalise join key (currently relies on implicit `by`), replace placeholder label `"something else"`, add proper Roxygen documentation
- [ ] **`fd_add_sf()` error message**: replace `stop("Screeeeeam")` with an informative message explaining the row-count inflation and suggesting `largest = TRUE` or polygon pre-dissolution
- [ ] Write tests (`tests/testthat/`) — priority cases: `fd_flag_trips()` overlap detection, `fd_flag_events()` cascading overlap with real times and dummy-time skip, `fd_flag_eflalo()` end-to-end label propagation
- [ ] **Multiple events per day (soft duplicates)**: when `.tsrc = "dummy"`, downstream code assumes one event per `.tid × gear × date × ir`. If multiple rows share that key, `fd_add_events()` will error. **Partial resolution implemented**: `fd_add_events(resolve = TRUE)` now auto-resolves dummy-time conflicts at join time by keeping the highest `LE_KG_TOT` event per `.tid × date` group. **Remaining gap**: detection and resolution should happen earlier, in `fd_flag_events()`, using a `.tid × gear × date × ir` duplicate check, so that bad data is surfaced and cleaned before the processing stage rather than silently resolved at join time. The current check 01 only catches `lid × date` duplicates.
- [ ] **Exact duplicate rows and `fd_events()`**: `fd_events()` errors on exact duplicate rows (all selected columns identical), so the `"01 duplicate event id and catch date"` check in `fd_flag_events` cannot trigger through `fd_flag_eflalo`. If upstream data may have exact duplicates, call `dplyr::distinct(eflalo)` before `fd_flag_eflalo()`, or use `fd_flag_events()` directly.



### Completed

- [x] `fd_add_sf()` added to `R/geo.R`: spatially joins an sf polygon layer onto pings, with S2-toggle and row-count guard.
- [x] `fd_add_state()` stub added to `R/state.R`: joins speed thresholds and classifies pings as `"fishing"` / `"something else"`.
- [x] `fd_interval_seconds()` added to `R/trail_steps.R`: wraps `fd_step_time()` and caps values at the `probs` quantile. Fixed typo `max_seonds` → `max_seconds` in earlier draft.
- [x] `R/gear.R` created with three new functions: `fd_benthis_lookup()`, `fd_add_gearwidth()`, `fd_add_sa()`. Adapted from the ICES VMS and Logbook Data Call workflow; `data.table` replaced with `dplyr` throughout.
- [x] `fd_clean_tacsat()` and `fd_clean_eflalo()`: column names translated from ICES ALLCAPS to short lowercase via `fd_translate()`. All internal references in `data_flag.R` and `tidy_eflalo.R` updated accordingly.
- [x] `fd_revert_tacsat()` and `fd_revert_eflalo()` implemented; reconstruct split date/time columns (`SI_DATE`/`SI_TIME`, `FT_DDAT`/`FT_DTIME`, `FT_LDAT`/`FT_LTIME`) from their POSIXct counterparts via `format()`
- [x] `fd_flag_trips()` and `fd_flag_events()` moved from `tidy_eflalo.R` to `data_flag.R` — all check functions now co-located
- [x] `gear`/`met6` defaults in `fd_flag_events()` and `fd_flag_eflalo()` changed from live `icesVocab::getCodeList()` calls to `NULL` (skipped by default); avoids network requests on every call
- [x] `fd_flag_tacsat()` grouping simplified to `group_by(vid)`; docs corrected
- [x] `fd_events()` error message made actionable
- [x] `LE_CDAT` added to required cols in `fd_clean_eflalo()`
- [x] `fd_add_trips()` updated to accept output of `fd_clean_tacsat()` / `fd_trips()` directly (short lowercase names). `tid` always carried across; `cn` adds optional extra columns. Row-count guard catches overlapping trips.
- [x] Resolved `.tid`/`FT_REF → tid` naming conflict in `dictionary`: `.tid` maps `new = ".tid"`; `FT_REF → tid` is unambiguous.
- [x] Records with `NA` coordinates in `fd_flag_tacsat()`: pre-check guard added; NA-coord records labelled `"00 missing coordinates"` and rejoined after spatial processing.
- [x] `no_hands` parameter added to all four `fd_flag_*` functions. `TRUE` (default): filter to passing records and drop the check column. `FALSE`: retain all records with check column for diagnostics.
- [x] `fd_flag_trips()` check 03 added: `"03 new years trip"` (year boundary crossing); existing checks 03–08 renumbered to 04–09.
- [x] `fd_flag_eflalo()` rewritten as an orchestrator: delegates all trip-level checks to `fd_flag_trips()` (joined via `.tid`) and all event-level checks to `fd_flag_events()` (joined via `.eid`); adds two cross-level catch-date checks that require the full joined eflalo. Removed the unimplemented `year` parameter.
- [x] `fd_flag_events()` fixed: temporal checks 04–08 now skipped when `.tsrc == "dummy"` (synthetic placeholder times carry no real temporal information; applying overlap detection to them incorrectly flagged all events sharing the same date). A `has_times` guard also handles the case where `t1`/`t2`/`.tsrc` are entirely absent.
- [x] `fd_add_events()` implemented: joins pings to events by `.tid` + `between(time, t1, t2)`; row-count guard errors with an actionable message directing to `fd_check_events_join()` if a ping matches more than one event.
- [x] `fd_check_events_join()` added: developer diagnostic that performs the unconstrained join and returns only the bloated rows (pings matched to multiple events), with a summary message. No assumptions about cause.
- [x] `csq_area()` added to `R/geo.R`: computes c-square cell area (km²) using a spherical-Earth approximation. Resolution inferred automatically from code length or supplied explicitly via `resolution` parameter.
- [x] `fd_add_events()` gained `resolve` parameter (`FALSE` by default): when `TRUE`, automatically resolves dummy-time conflicts by keeping the highest `LE_KG_TOT` event per `.tid × date` group before joining. `fd_check_events_join()` message updated to mention `resolve = TRUE`.
- [x] Package-wide documentation review completed; all issues fixed:
  - `fd_check_input()` `@param dictionary` — filled in from placeholder
  - `fd_clean_eflalo()` `@param eflalo` — `dictionary` → `fd_dictionary`
  - `fd_flag_tacsat()` `@param ports` — removed false default claim; now states it is required
  - `fd_flag_tacsat()` `@return` — corrected: `.intv` is dropped (not kept) when `no_hands = TRUE`
  - `fd_add_trips()` `@param cn` — corrected default from `"tid"` to `c("tid", ".tid")`
  - `fd_add_state()` — replaced placeholder title and `xxx` params with proper documentation
  - `harbours` data doc — corrected class (`sf` → tibble) and column count (5 → 4)
  - `fd_dictionary` data doc — corrected first column name (`field` → `old`), added `new` column, corrected count (7 → 8)
  - `data.R` `@source` (×3) — fixed typo `DATASET_vnstools.R` → `DATASET_vmstools.R`
  - `DESCRIPTION` — added `icesVocab` to `Suggests`; removed `stringr` (unused in `R/` source)
- [x] Line-count analysis comparing osfd vs. ICES datacall scripts: osfd `R/` has ~768 real code lines vs. ~1,912 in the datacall scripts (~2.4× more). Overhead in datacall: year-loop boilerplate, inline QC matrices, file I/O, activity-detection logic.
- [x] Comparison article created: `vignettes/articles/osfd_vs_datacall.Rmd` — covers six architectural differences: package vs. scripts, data model (trips/events decomposition), column naming, QC flagging (`no_hands`), VMS–logbook linking (dplyr interval joins vs. `mergeEflalo2Tacsat()`/`trip_assign()`), activity classification (speed-threshold lookup vs. mixture models), and catch distribution (pending `fd_split_among_pings()`).
- [x] pkgdown site configuration created: `_pkgdown.yml` (Bootstrap 5, navbar, article groups, reference index). `DESCRIPTION` updated with `URL: https://einarhjorleifsson.github.io/osfd`. All three articles in `vignettes/articles/` given proper vignette preambles. `ices-rectangle-bug.Rmd` renamed to `ices_rectangle_bug.Rmd` for pkgdown compatibility.
- [x] `trip_assign()` compartmentalized into `_R/trip_assign.R` (outside the package, to avoid data.table/vmstools dependencies). Original logic preserved exactly; decomposed into five named sub-functions: `ta_multi_trips()`, `ta_pass1()`, `ta_pass2()`, `ta_pass3()`, and the main `trip_assign()` orchestrator. All external calls given `package::` prefixes. Known quirks (fragile `get(col)` naming chain in Pass 2, `str(e)` debug artifact, `tz2` scoping in Pass 3, `valid_metiers` free variable) preserved with inline documentation notes.
- [x] `tz2` scoping bug fixed in `ta_pass3()` in `_R/trip_assign.R`: `tz2` was only defined inside the `if (nrow(tz[is.na(get(col))]) > 0)` block; when Pass 1 resolved all pings (no NAs remained), the block was never entered and the final `rbind(tz, tz2)` failed with `object 'tz2' not found`. Fixed by initialising `tz2 <- data.frame()` before the `if`-block. Bug was latent in the original ICES datacall `0_global.R` because real data almost always leaves some pings unresolved.
- [x] `vignettes/articles/technical_merging.Rmd` updated: removed erroneous `LE_RECT` column from the three `tacsatp_c*` failure-case tribbles (it is a logbook attribute assigned during the merge, not present beforehand); added `SI_DATIM` (POSIXct timestamps) to each tribble so pings are distinct and survive `unique()` in `ta_pass1()`; appended a final printed output block to each of the three failure cases (Case 1: Pass 3 catch-weight fallback loses a minority combination; Case 2: phantom combinations — pings assigned a gear × rectangle combination that never appeared in the logbook on the ping date; Case 3: cross-day contamination — Pass 3 picks the wrong rectangle because catch from a different day inflates the trip total).
- [x] Case 4 added to `vignettes/articles/technical_merging.Rmd`: demonstrates the duplication bug in `ta_pass3()` (ICES datacall [issue #52](https://github.com/ices-eg/ICES-VMS-and-Logbook-Data-Call/issues/52)). When a trip has a mix of ambiguous and unambiguous days, `ta_pass3` collects all pings from any trip with a NA ping (not just the NA pings), causing resolved pings to appear in both `tz` and `tz2`; the final `rbind(tz, tz2)` duplicates them. A minimal tribble (4 columns eflalo, 3 columns tacsat) reproduces the 2-ping → 3-row inflation. Bug documented as a comment above `ta_pass3()` in `_R/trip_assign.R`; function code left unchanged.
- [x] Case 5 added to `vignettes/articles/technical_merging.Rmd`: shows that the Case 4 duplication survives sequential column processing (`LE_GEAR` then `LE_RECT`). The `unique()` call inside `ta_pass1` collapses inherited duplicates before Pass 3 re-inflates, so the row count does not compound — but it is never repaired. The final `tacsatp` retains the inflated count regardless of how many columns are processed.
- [x] Case 6 added to `vignettes/articles/technical_merging.Rmd`: demonstrates that the Pass 3 duplication bug also fires on **transit-day pings** (pings within the trip window with no matching logbook date). With 3 pings across fishing day 1, transit day 2, and fishing day 3, Pass 3 produces 5 rows. Ping 1 appears twice with **contradictory gear values** (OTB from Pass 1 and OTM from Pass 3 overwrite), making this more severe than Case 4.
