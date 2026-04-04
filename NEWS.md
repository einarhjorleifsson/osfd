# osfd 0.0.0.9000

Development version. Functions and interfaces are subject to change.

---

## Data

- Added `dictionary`: a data dictionary covering all TACSAT2 and EFLALO2
  fields, used to drive validation and column name translation throughout the
  package.
- Icelandic fleet VMS and logbook data stored as parquet files in `data-raw/`
  (`tacsat_IS.parquet`, `eflalo_IS.parquet`) for use in development and testing.

---

## Preprocessing (`R/data_clean.R`)

### Validation

**`fd_check_input(data, which)`** — preflight validator for raw TACSAT or EFLALO
data frames. Checks required fields (hard stop), optional fields (message), and
coercion safety (warns if numeric/date conversion would silently introduce NAs).
Pipeable; called internally by both clean functions.

### Clean

**`fd_clean_tacsat(tacsat, remove = TRUE)`**

- Coerces `SI_LATI`, `SI_LONG`, `SI_SP`, `SI_HE` to numeric.
- Combines `SI_DATE` + `SI_TIME` into a single `SI_DATIM` POSIXct column (UTC);
  source columns dropped by default (`remove = TRUE`).
- Adds `.pid` (integer row identifier); sorts by vessel × datetime.
- Translates column names to short lowercase convention:
  `VE_COU → cid`, `VE_REF → vid`, `SI_LATI → lat`, `SI_LONG → lon`,
  `SI_SP → speed`, `SI_HE → heading`, `SI_DATIM → time`.

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
  `LE_DIV → fao`, `LE_MET → met6`, and others.

### Revert

**`fd_revert_tacsat(tacsat)`** — reverses the name translation from
`fd_clean_tacsat()`, restoring ICES ALLCAPS column names. Reconstructs
`SI_DATE` (`"DD/MM/YYYY"`) and `SI_TIME` (`"HH:MM"`) from `SI_DATIM` via
`format()`. Only present columns are renamed; extras pass through unchanged.

**`fd_revert_eflalo(eflalo)`** — reverses the name translation from
`fd_clean_eflalo()`. Reconstructs `FT_DDAT` / `FT_DTIME` from `FT_DDATIM` and
`FT_LDAT` / `FT_LTIME` from `FT_LDATIM` via `format()`. `.tid` is not
renamed (excluded to avoid clash with `FT_REF → tid`).

---

## QC / Flagging (`R/data_flag.R`)

All flag functions follow a no-filter convention: they add a labelled check
column and leave filtering to the caller.

**`fd_flag_tacsat(tacsat, minimum_interval_seconds, area, harbours)`**

- Computes `.intv` (ping interval in seconds) via `fd_step_time()`, grouped by
  vessel (`vid`).
- Adds `.checks` column with labels 01–08 or `"ok"`:
  duplicate pings, impossible coordinates, pings outside area, pings in harbour,
  sub-minimum intervals, etc.

**`fd_flag_trips(trips)`** — flags trip-level problems in the output of
`fd_trips()`: missing/invalid timestamps, `T1 > T2`, `T1 == T2`, temporal
overlaps, missing vessel metadata. Adds `.tchecks` (labels 01–08 or `"ok"`).

**`fd_flag_events(events, gear = NULL, met6 = NULL)`** — flags event-level
problems in the output of `fd_events()`. Adds `.echecks` (labels 01–09 or
`"ok"`):

- 01: duplicate event id and catch date
- 02–03: invalid gear / metier codes (skipped if `gear`/`met6 = NULL`)
- 04–08: `t1`/`t2` temporal checks — missing, inverted, overlap (applied only
  when `t1`/`t2` columns are present, i.e. `LE_STIME`/`LE_ETIME` were in the
  raw data)

Overlap detection (check 08) uses a cumulative-max-of-`t2` algorithm rather
than lead/lag-of-1, so all cascading overlaps within a trip are resolved in a
single `fd_flag_events()` call. Events are sorted by `t1` within each trip
before checks are applied.

**`fd_flag_eflalo(eflalo, year = NULL, gear = NULL, met6 = NULL)`** — combines
trip and event checks on a full eflalo data frame. Delegates trip overlap
detection to `fd_trips()` + `fd_flag_trips()` internally. Adds `.checks`
(labels 01–12 or `"ok"`).

---

## Decomposition (`R/tidy_eflalo.R`)

**`fd_trips(eflalo)`** — extracts one row per trip from a cleaned eflalo data
frame (uses `.tid` added by `fd_clean_eflalo()`).

**`fd_events(eflalo)`** — extracts event-level rows (catch date, gear,
rectangle, catch columns). Errors informatively if duplicate events are
detected.

**`fd_tidy_eflalo(eflalo)`** — convenience wrapper returning
`list(trips = ..., events = ...)`.

---

## Trip Assignment (`R/analysis.R`)

**`fd_add_trips(tacsat, eflalo, cn, remove)`** — joins trip-level metadata from
eflalo onto tacsat pings by vessel identity and time overlap. Each ping is
matched to the trip active at that timestamp; pings outside any trip window
receive `NA`. Currently expects ICES ALLCAPS column names (pre-translation or
post-revert).

---

## Utilities

**`fd_translate(d, dictionary, from, to)`** (`R/utils.R`) — renames columns of
a data frame or lazy tibble using a lookup dictionary. Used internally by all
clean and revert functions; also exported for direct use.

**`d2ir(lon, lat, sub)`** (`R/geo.R`) — converts decimal degree coordinates to
ICES statistical rectangles. dbplyr-compatible.

**`fd_calc_csq(lon, lat, degrees)`** (`R/geo.R`) — encodes decimal-degree
coordinates as a c-square code (c-squares spec v1.1, Rees 2005). Supports all
standard resolutions (`10`, `5`, `1`, `0.5`, `0.1`, `0.05`, `0.01`); returns
`NA_character_` for `NA` inputs. ~2× faster and ~65% lower memory than the
vmstools `CSquare()` equivalent (no intermediate 3D array). dbplyr-compatible.

**`csq2lonlat(csq, degrees)`** (`R/geo.R`) — decodes a c-square code to the
centre coordinates (`lat`, `lon`) of the cell at the requested resolution.
Returns exact cell centres; R-only (returns a `data.frame`).

**`fd_step_time(datetime, weight, fill_na)`** (`R/trail_steps.R`) — computes
ping-to-ping time intervals as a weighted blend of backward and forward
differences. Used internally by `fd_flag_tacsat()`.
