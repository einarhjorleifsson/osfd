# osfd 0.0.0.9000

Pre-release development version. Functions and interfaces are subject to change
without notice.

---

## Data

- Added `dictionary`: a data dictionary covering all TACSAT2 and EFLALO2
  fields, used to drive validation and column name translation throughout the
  package.
- Icelandic fleet VMS and logbook parquet files in `data-raw/`
  (`tacsat_IS.parquet`, `eflalo_IS.parquet`) serve as development and test data.

---

## Preprocessing (`R/data_clean.R`)

### Validation

**`fd_check_input(data, which)`** — preflight validator for raw TACSAT or
EFLALO data frames. Checks required fields (hard stop), optional fields
(message), and coercion safety (warns if numeric or date conversion would
silently introduce `NA`s). Pipeable; called internally by both clean functions
and exported for standalone use.

### Clean

**`fd_clean_tacsat(tacsat, remove = TRUE)`**

- Coerces `SI_LATI`, `SI_LONG`, `SI_SP`, `SI_HE` to numeric.
- Combines `SI_DATE` + `SI_TIME` into a single `SI_DATIM` POSIXct column (UTC);
  source columns dropped by default (`remove = TRUE`).
- Adds `.pid` (integer row identifier); sorts by vessel × datetime.
- Translates column names to short lowercase convention via `fd_translate()`:
  `VE_COU → cid`, `VE_REF → vid`, `SI_LATI → lat`, `SI_LONG → lon`,
  `SI_SP → speed`, `SI_HE → heading`, `SI_DATIM → time`. Dot-prefix columns
  (`.pid`) are not renamed.

**`fd_clean_eflalo(eflalo, remove = TRUE)`**

- Coerces numeric columns (`VE_KW`, `VE_LEN`, `VE_TON`, `LE_MSZ`, all
  `LE_KG_*` / `LE_EURO_*`).
- Combines `FT_DDAT` + `FT_DTIME` → `FT_DDATIM` and `FT_LDAT` + `FT_LTIME` →
  `FT_LDATIM` (POSIXct, UTC); source columns dropped by default.
- Parses `LE_CDAT` from `"DD/MM/YYYY"` character to R Date.
- If `LE_STIME` / `LE_ETIME` are present, derives `t1`, `t2`, `.tsrc` (event
  start/end datetimes with source label: `"data"`, `"next day"`, `"dummy"`, or
  `NA`).
- Adds `.eid` (integer row identifier) and `.tid` (trip identifier via
  `consecutive_id()`); sorts by vessel × trip × catch date.
- Translates column names to short lowercase convention:
  `VE_REF → vid`, `VE_COU → cid`, `VE_LEN → length`, `VE_KW → kw`,
  `VE_TON → gt`, `FT_REF → tid`, `FT_DDATIM → T1`, `FT_LDATIM → T2`,
  `LE_CDAT → date`, `LE_GEAR → gear`, `LE_MSZ → mesh`, `LE_RECT → ir`,
  `LE_DIV → fao`, `LE_MET → met6`, and others. `.eid` and `.tid` are not
  renamed (dot-prefix convention signals package-derived columns).

### Revert

**`fd_revert_tacsat(tacsat)`** — reverses the name translation from
`fd_clean_tacsat()`, restoring ICES ALLCAPS column names. Reconstructs
`SI_DATE` (`"DD/MM/YYYY"`) and `SI_TIME` (`"HH:MM"`) from `time` via
`format()`. Only present columns are renamed; extras pass through unchanged.

**`fd_revert_eflalo(eflalo)`** — reverses the name translation from
`fd_clean_eflalo()`. Reconstructs `FT_DDAT` / `FT_DTIME` from `T1` and
`FT_LDAT` / `FT_LTIME` from `T2` via `format()`. `.tid` passes through
unchanged.

---

## QC / Flagging (`R/data_flag.R`)

All flag functions share a `no_hands` parameter:

- `no_hands = TRUE` (default, production): failing records are filtered out and
  the check column is dropped before returning.
- `no_hands = FALSE` (diagnostic): all records are returned with the check
  column appended. Intended for interactive inspection — filter and drop
  manually once satisfied.

**`fd_flag_tacsat(tacsat, minimum_interval_seconds = 30, areas, ports, no_hands = TRUE)`**

- Computes `.intv` (ping interval in seconds) via `fd_step_time()`, grouped by
  vessel (`vid`).
- Records with missing coordinates (`lon`/`lat` is `NA`) are labelled
  `"00 missing coordinates"` before any spatial operations.
- Adds `.checks` with labels 00–08 or `"ok"`: missing coordinates, pings
  outside ICES area, duplicate timestamps, sub-minimum interval, pings in
  harbour, missing country / vessel id / datetime / speed.

**`fd_flag_trips(trips, no_hands = TRUE)`** — flags trip-level problems in the
output of `fd_trips()`. Adds `.tchecks` (labels 01–09 or `"ok"`):

| Label | Condition |
|---|---|
| 01 | departure missing (`T1` is `NA`) |
| 02 | arrival missing (`T2` is `NA`) |
| 03 | new years trip (trip crosses year boundary) |
| 04 | departure after arrival (`T1 > T2`) |
| 05 | departure equals arrival (`T1 == T2`) |
| 06 | next departure before current arrival |
| 07 | previous arrival after current departure |
| 08 | no vessel length |
| 09 | no engine power |

**`fd_flag_events(events, no_hands = TRUE, gear = NULL, met6 = NULL)`** — flags
event-level problems in the output of `fd_events()`. Adds `.echecks` (labels
01–08 or `"ok"`):

- 01: duplicate `lid` + catch date
- 02–03: invalid gear / metier codes (skipped when `gear`/`met6 = NULL`,
  avoiding network requests on every call)
- 04–08: `t1`/`t2` temporal checks (missing, inverted, overlap) — applied only
  when `t1`/`t2` are present **and** `.tsrc != "dummy"`; dummy times are
  synthetic placeholders and carry no real temporal information

Overlap detection (check 08) uses a cumulative-max-of-`t2` algorithm rather
than lead/lag-of-1, resolving all cascading overlaps in a single pass. Events
are sorted by `t1` within each trip before checks are applied.

**`fd_flag_eflalo(eflalo, no_hands = TRUE, gear = NULL, met6 = NULL)`** — an
orchestrating wrapper; does not re-implement check logic. Delegates to
`fd_flag_trips()` (joined via `.tid`) and `fd_flag_events()` (joined via
`.eid`), then applies two cross-level checks requiring the full joined frame:
`"catch date before departure"` and `"catch date after arrival"`. Composes a
single `.checks` column in priority order: trip failure → event failure →
cross-level failure → `"ok"`.

---

## Decomposition (`R/tidy_eflalo.R`)

**`fd_trips(eflalo)`** — extracts one row per trip from a cleaned eflalo data
frame (uses `.tid` added by `fd_clean_eflalo()`). Returns vessel metadata and
trip timestamps.

**`fd_events(eflalo)`** — extracts event-level rows (catch date, gear,
rectangle, catch columns, optional `t1`/`t2`/`.tsrc`). Errors informatively if
exact duplicate rows are detected after selection.

**`fd_tidy_eflalo(eflalo)`** — convenience wrapper returning
`list(trips = fd_trips(eflalo), events = fd_events(eflalo))`.

---

## Ping Enrichment (`R/add_to_pings.R`)

**`fd_add_trips(ais, trips, cn = "tid", remove = TRUE)`** — joins trip-level
metadata from `trips` (output of `fd_trips()`) onto VMS/AIS pings by vessel
identity and time overlap. `"tid"` and `".tid"` are always carried across;
additional columns controlled via `cn`. A row-count guard stops with an
informative error if overlapping trips cause any ping to match more than one
trip, directing the user to `fd_flag_trips()`.

**`fd_add_events(ais, events)`** — joins fishing events (output of
`fd_events()`) onto pings enriched by `fd_add_trips()`, matching on `.tid` and
`between(time, t1, t2)`. All event columns are carried across; pings outside
any event window receive `NA`. A row-count guard errors if any ping matches
more than one event, directing the user to `fd_check_events_join()`.

**`fd_check_events_join(ais, events)`** — developer diagnostic for
`fd_add_events()` join conflicts. Performs the unconstrained join and returns
only the rows where a ping matched more than one event. Prints a summary of
affected pings and trips. Returns an empty tibble (invisibly) when no conflicts
exist.

---

## Utilities

**`fd_translate(d, dictionary, from, to)`** (`R/utils.R`) — renames columns of
a data frame using a lookup dictionary. Used internally by all clean and revert
functions; also exported for direct use.

**`d2ir(lon, lat, sub)`** (`R/geo.R`) — converts decimal degree coordinates to
ICES statistical rectangles. dbplyr-compatible.

**`fd_calc_csq(lon, lat, degrees)`** (`R/geo.R`) — encodes decimal-degree
coordinates as a c-square code (c-squares spec v1.1, Rees 2005). Supports all
standard resolutions (`10`, `5`, `1`, `0.5`, `0.1`, `0.05`, `0.01`); returns
`NA_character_` for `NA` inputs. ~2× faster and ~65% lower memory than the
vmstools `CSquare()` equivalent (no intermediate 3D array). dbplyr-compatible.

**`csq2lonlat(csq, degrees)`** (`R/geo.R`) — decodes a c-square code to the
centre coordinates (`lat`, `lon`) of the cell at the requested resolution.
Returns exact cell centres (no Excel-era rounding offset). R-only.

**`fd_step_time(datetime, weight, fill_na)`** (`R/trail_steps.R`) — computes
ping-to-ping time intervals as a weighted blend of backward and forward
differences. Used internally by `fd_flag_tacsat()` and `fd_interval_seconds()`.

**`fd_interval_seconds(time, probs = 0.975)`** (`R/trail_steps.R`) — wraps
`fd_step_time()` and caps the resulting intervals at the `probs` quantile (default 97.5th percentile). Intended for use within `group_by(.tid) |> mutate()` to produce the `.intv` column used by `fd_add_sa()`.

---

## Gear width and swept area (`R/gear.R`)

Three new functions for the processing stage. All adapted from the ICES VMS and
Logbook Data Call workflow
(<https://github.com/ices-eg/ICES-VMS-and-Logbook-Data-Call>); `data.table`
replaced with `dplyr` throughout. Requires optional dependencies `sfdSAR` and
`icesVMS`.

**`fd_benthis_lookup(kw_name = "kw", oal_name = "length")`** — builds a lookup
table by fetching the RCG métier reference list from GitHub and joining it with
BENTHIS gear-width parameters from `icesVMS::get_benthis_parameters()`. The
`gearCoefficient` sentinel values (`"avg_kw"`, `"avg_oal"`) are replaced with
the actual column names supplied via `kw_name` and `oal_name`. Requires internet
access at runtime.

**`fd_add_gearwidth(x, met_name = "met6", oal_name = "length", kw_name = "kw")`**
— predicts gear contact width (km) for each VMS ping using the BENTHIS model
via `sfdSAR::predict_gear_width()` and appends `.gearwidth`. Fill priority:
user-supplied `LE_GEARWIDTH` → model prediction (m → km) → BENTHIS table
default. Returns `x` with `.gearwidth` appended.

**`fd_add_sa(x, gear_name = "gear", intv_name = ".intv", gearwidth_name = ".gearwidth", speed_name = "speed")`**
— calculates swept area (km²) per VMS ping via
`sfdSAR::predict_surface_contact()`. Dispatches by gear type: `SDN` (Danish
seine) → `danish_seine_contact()`; `SSC` (Scottish seine) →
`scottish_seine_contact()`; all other gears → `trawl_contact()`. The interval
column is expected in seconds; the function converts to hours internally.
Returns `x` with `.sa` appended.

---

## QC / Flagging updates (`R/data_flag.R`)

All four `fd_flag_*` functions now share a `no_hands` parameter:

- `no_hands = TRUE` (default, production): failing records are filtered out and
  the check column is dropped before returning.
- `no_hands = FALSE` (diagnostic): all records are returned with the check
  column appended for interactive inspection.

**`fd_flag_tacsat()`**

- Parameters renamed: `area` → `areas`, `harbours` → `ports`.
- Added `no_hands` parameter. When `TRUE`, both `.checks` and `.intv` are
  dropped; when `FALSE`, both are appended.
- NA-coordinate rows are re-sorted by `.pid` after rejoining.

**`fd_flag_trips()`**

- Added `no_hands` parameter.
- New check `"03 new years trip"`: flags trips where the departure year is
  exactly one less than the landing year.
- Existing checks renumbered: 03–08 → 04–09.

**`fd_flag_events()`**

- Added `no_hands` parameter; argument order is now `(events, no_hands = TRUE,
  gear = NULL, met6 = NULL)`.
- Temporal checks 04–08 are now skipped when `.tsrc == "dummy"` — synthetic
  `00:01`/`23:59` placeholder times carry no real temporal information. A
  `has_times` guard also handles the case where `t1`/`t2`/`.tsrc` are absent.

**`fd_flag_eflalo()`** — complete rewrite as an orchestrating wrapper

- Removed the `year` parameter (was never implemented).
- Added `no_hands` parameter.
- Delegates trip-level checks to `fd_flag_trips(no_hands = FALSE)` (joined via
  `.tid`) and event-level checks to `fd_flag_events(no_hands = FALSE)` (joined
  via `.eid`).
- Composes a single `.checks` column in priority order: trip failure → event
  failure → `"catch date before departure"` → `"catch date after arrival"` →
  `"ok"`.

---

## Ping enrichment updates (`R/add_to_pings.R`)

**`fd_add_events(ais, events)`** — fully implemented and documented

- Joins pings to events by `.tid` + `between(time, t1, t2)`.
- Row-count guard stops with an informative error if any ping matches more than
  one event, directing the user to `fd_check_events_join()`.

**`fd_check_events_join(ais, events)`** — new diagnostic function

- Performs the same join as `fd_add_events()` without a relationship constraint
  and returns only the rows where a ping matched more than one event.
- Prints a summary: number of affected pings and trips.
- Returns an empty tibble invisibly (with a message) when no conflicts exist.

---

## Spatial join (`R/geo.R`)

**`fd_add_sf(ais, shape)`** — new function

- Spatially left-joins an `sf` polygon layer (`shape`) onto VMS/AIS pings via
  `sf::st_join()`. Converts `ais` to an `sf` point object (CRS 4326) if not
  already `sf`.
- S2 geometry is disabled for the duration of the call and restored on exit.
- Row-count guard stops if overlapping polygons produce a one-to-many join.

---

## Ping state classification (`R/state.R`)

**`fd_add_state(ais, speed_table)`** — new stub function

- Joins `speed_table` (columns `gear`, `target`, `s1`, `s2` in knots) to `ais`
  and classifies each ping as `"fishing"` (speed within `[s1, s2]`) or
  `"something else"`. Drops `s1`/`s2` before returning.
- ⚠️ Working stub: join key, fallback label, and documentation are provisional.
