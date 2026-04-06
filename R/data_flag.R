# ── TACSAT checks ──────────────────────────────────────────────────────────────

#' Single-pass TACSAT quality checks
#'
#' @description
#' Adds a `.checks` column to a TACSAT data frame in a single `case_when()` pass.
#' Each record is labelled with the first failing check, or `"ok"` if it passes
#' all of them. Also computes an `.intv` column (time in seconds since the
#' previous ping for the same vessel) which is used by the interval threshold
#' check and is useful downstream.
#'
#' Expects a data frame as returned by `fd_clean_tacsat()` — `lon` (`SI_LONG`) and
#' `lat` (`SI_LATI`) are plain numeric columns at this stage. Data must be sorted
#' by `vid` (`VE_REF`) and `time` (`SI_DATIM`), which `fd_clean_tacsat()` handles.
#' The function converts to `sf` internally for spatial operations, then drops
#' geometry before returning.
#'
#' By default (`no_hands = TRUE`) the function filters out failing records and
#' drops `.checks` before returning — suitable for production pipelines where
#' the cleaned result is all that is needed. Set `no_hands = FALSE` to retain
#' all records with the `.checks` label, which is useful for interactive
#' diagnostics:
#' ```r
#' tacsat |>
#'   fd\_flag\_tacsat(no_hands = FALSE) |>
#'   dplyr::count(.checks)
#' ```
#'
#' Checks are performed in the following order and return the first failure:
#' \describe{
#'   \item{`"00 missing coordinates"`}{`lon` or `lat` is `NA` — checked first because
#'     `NA` coordinates would cause `sf::st_as_sf()` to error. These records are
#'     separated before spatial processing and rejoined with this label.}
#'   \item{`"01 point out of (ices) area"`}{Record falls outside the specified area of interest}
#'   \item{`"02 duplicate"`}{Duplicate of a previous record with the same vessel, position, and timestamp}
#'   \item{`"03 time interval too short"`}{Time since previous ping (per vessel) is less than `minimum_interval_seconds`}
#'   \item{`"04 in harbour"`}{Record location falls within a harbour buffer zone (3 km radius)}
#'   \item{`"05 no country id"`}{`cid` (`VE_COU`) is `NA`}
#'   \item{`"06 no vessel id"`}{`vid` (`VE_REF`) is `NA`}
#'   \item{`"07 no datetime"`}{`time` (`SI_DATIM`) is `NA`}
#'   \item{`"08 no speed"`}{`speed` (`SI_SP`) is `NA`}
#'   \item{`"ok"`}{All checks passed}
#' }
#'
#' **Note:** This function is R-only. `sf` spatial joins, `base::duplicated()`,
#' and `fd_step_time()` are not compatible with lazy/DuckDB backends.
#'
#' @param tacsat A TACSAT data frame as returned by `fd_clean_tacsat()`. Must
#'   contain `cid` (`VE_COU`), `vid` (`VE_REF`), `time` (`SI_DATIM`, POSIXct),
#'   `lon` (`SI_LONG`), `lat` (`SI_LATI`), and `speed` (`SI_SP`).
#' @param minimum_interval_seconds Numeric. Minimum permitted time interval
#'   between consecutive pings for the same vessel, in **seconds**. Default: 30.
#' @param areas A spatial object (sf) containing the area of interest. Records outside this area
#'   fail the check.
#' @param ports A spatial object (sf) containing port locations. If not
#'   already an sf object, it should have `lon` and `lat` columns. Ports are
#'   automatically buffered to 3 km radius and converted to Web Mercator
#'   (EPSG:3857) for accurate distance calculations before being transformed
#'   back to WGS84 (EPSG:4326). Default: `osfd::harbours`.
#' @param no_hands Logical. Controls whether failing records are automatically
#'   removed from the output. When `TRUE` (default, production mode), records
#'   where `.checks != "ok"` are filtered out and the `.checks` column is
#'   dropped before returning. When `FALSE` (diagnostic mode), all records are
#'   returned with `.checks` and `.intv` appended so you can inspect failures.
#'
#' @return
#'   * `no_hands = TRUE` (default): The input data frame filtered to passing
#'     records only, with `.intv` appended and `.checks` dropped.
#'   * `no_hands = FALSE`: The full input data frame (geometry dropped) with
#'     two new columns appended:
#'     \describe{
#'       \item{`.checks`}{Character. First failing check label, or `"ok"`.}
#'       \item{`.intv`}{Numeric. Time interval in seconds since the previous
#'         ping for the same vessel.}
#'     }
#'
#' @examples
#' \dontrun{
#' # Production: get only clean pings
#' osfd::tacsat |>
#'   fd_clean_tacsat() |>
#'   fd_flag_tacsat()
#'
#' # Diagnostic: inspect all check labels
#' osfd::tacsat |>
#'   fd_clean_tacsat() |>
#'   fd_flag_tacsat(no_hands = FALSE) |>
#'   dplyr::count(.checks)
#' }
#'
#' @export
fd_flag_tacsat <- function(tacsat,
                           minimum_interval_seconds = 30,
                           areas,
                           ports,
                           no_hands = TRUE) {

  if(missing(ports)) stop("Need ports")
  if(missing(areas)) stop("Need areas")

  if (!inherits(ports, "sf")) {
    ports <-
      ports |>
      sf::st_as_sf(coords = c("lon", "lat"),
                   crs = 4326) |>
      sf::st_transform(crs = 3857) |>
      sf::st_buffer(dist = 3000) |>
      sf::st_transform(crs = 4326) |>
      dplyr::mutate(.in_harbour = TRUE) |>
      dplyr::select(.in_harbour)
  } else {
    ports <-
      ports |>
      dplyr::mutate(.in_harbour = TRUE) |>
      dplyr::select(.in_harbour)
  }

  # NOTE: sf::st_as_sf(), sf::st_join(), base::duplicated(), and fd_step_time()
  # are R-only; not duckdb-compatible

  # Pre-check: st_as_sf() errors on NA coordinates. Split, label, and rejoin.
  na_coords  <- dplyr::filter(tacsat,  is.na(lon) | is.na(lat))
  tacsat_ok  <- dplyr::filter(tacsat, !is.na(lon) & !is.na(lat))

  flagged <- tacsat_ok |>
    sf::st_as_sf(coords = c("lon", "lat"),
                 crs = 4326,
                 remove = FALSE) |>
    sf::st_join(areas |> dplyr::mutate(.in = TRUE) |> dplyr::select(.in)) |>
    sf::st_join(ports) |>
    dplyr::group_by(vid) |>
    dplyr::mutate(.intv = fd_step_time(time)) |>
    dplyr::ungroup() |>
    dplyr::mutate(
      .checks = dplyr::case_when(
        is.na(.in)                                                              ~ "01 point out of (ices) area",
        # NOTE: duplicated() is not duckdb-compatible
        duplicated(paste(cid, vid, lon, lat, time))                             ~ "02 duplicate",
        !is.na(.intv) & .intv < minimum_interval_seconds                        ~ "03 time interval too short",
        .in_harbour == TRUE                                                     ~ "04 in harbour",
        is.na(cid)                                                              ~ "05 no country id",
        is.na(vid)                                                              ~ "06 no vessel id",
        is.na(time)                                                             ~ "07 no datetime",
        is.na(speed)                                                            ~ "08 no speed",
        .default = "ok")) |>
    dplyr::select(-c(.in_harbour, .in)) |>
    sf::st_drop_geometry()

  if (nrow(na_coords) > 0) {
    na_coords <- dplyr::mutate(na_coords,
                               .checks = "00 missing coordinates",
                               .intv   = NA_real_)
    flagged <- dplyr::bind_rows(na_coords, flagged) |>
      dplyr::arrange(.pid)
  }

  if (no_hands == TRUE) {
    flagged <- flagged |>
      dplyr::filter(.checks == "ok") |>
      dplyr::select(-c(.checks, .intv))
  }

  return(flagged)
}


# ── EFLALO checks ──────────────────────────────────────────────────────────────

#' Check for Temporal Overlaps in Fishing Trips
#'
#' Validates the temporal sequence of fishing trips for each vessel by checking
#' for overlapping or out-of-sequence departure and arrival times. This function
#' is typically applied after extracting trips with \code{\link{fd_trips}}.
#'
#' By default (`no_hands = TRUE`) the function filters out failing trips and
#' drops `.tchecks` before returning — suitable for production pipelines. Set
#' `no_hands = FALSE` to retain all trips with the `.tchecks` label for
#' interactive diagnostics:
#' ```r
#' trips |>
#'   fd\_flag\_trips(no_hands = FALSE) |>
#'   dplyr::count(.tchecks)
#' ```
#'
#' Checks are performed in the following order and return the first failure:
#' \describe{
#'   \item{`"01 departure missing"`}{`T1` (`FT_DDATIM`) is `NA`}
#'   \item{`"02 arrival missing"`}{`T2` (`FT_LDATIM`) is `NA`}
#'   \item{`"03 new years trip"`}{Departure year is exactly one less than landing year — the trip crosses a year boundary, which is typically a data error}
#'   \item{`"04 departure after arrival"`}{`T1 > T2` — time travel not supported}
#'   \item{`"05 departure equals arrival"`}{`T1 == T2` — a trip of zero duration}
#'   \item{`"06 next departure before current arrival"`}{Temporal overlap: the next trip departs before this one lands}
#'   \item{`"07 previous arrival after current departure"`}{Temporal overlap: the previous trip's landing is after this departure}
#'   \item{`"08 no vessel length"`}{`length` (`VE_LEN`) is `NA` (informational — required for gear width and swept area)}
#'   \item{`"09 no engine power"`}{`kw` (`VE_KW`) is `NA` (informational — gear width falls back to lookup table defaults)}
#'   \item{`"ok"`}{All checks passed}
#' }
#'
#' @param trips A data frame containing fishing trip data with at minimum the
#'   following columns: `cid` (`VE_COU`, vessel country), `vid` (`VE_REF`, vessel
#'   reference), `T1` (`FT_DDATIM`, departure date/time), `T2` (`FT_LDATIM`,
#'   landing date/time), `length` (`VE_LEN`), and `kw` (`VE_KW`). Typically
#'   produced by \code{\link{fd_trips}}. Input must be sorted by `T1` within
#'   each vessel (handled by `fd_clean_eflalo()`).
#' @param no_hands Logical. Controls whether failing trips are automatically
#'   removed from the output. When `TRUE` (default, production mode), trips
#'   where `.tchecks != "ok"` are filtered out and the `.tchecks` column is
#'   dropped before returning. When `FALSE` (diagnostic mode), all trips are
#'   returned with `.tchecks` appended so you can inspect failures.
#'
#' @return
#'   * `no_hands = TRUE` (default): The input data frame filtered to passing
#'     trips only, with `.tchecks` dropped.
#'   * `no_hands = FALSE`: The full input data frame with a `.tchecks`
#'     character column appended (first failing check label, or `"ok"`).
#'
#' @seealso
#'   \code{\link{fd_trips}} for extracting trip-level data,
#'   \code{\link{fd_flag_events}} for event-level checks,
#'   \code{\link{fd_tidy_eflalo}} for extracting both trips and events in one call.
#'
#' @examples
#' \dontrun{
#' # Production: get only valid trips
#' trips <- fd_trips(eflalo) |> fd_flag_trips()
#'
#' # Diagnostic: inspect all check labels
#' fd_trips(eflalo) |>
#'   fd_flag_trips(no_hands = FALSE) |>
#'   dplyr::filter(.tchecks != "ok")
#' }
#'
#' @export
fd_flag_trips <- function(trips, no_hands = TRUE) {
  trips <-
    trips |>
    dplyr::group_by(cid, vid) |>
    dplyr::mutate(
      .tchecks = dplyr::case_when(
        is.na(T1)                                         ~ "01 departure missing",
        is.na(T2)                                         ~ "02 arrival missing",
        lubridate::year(T1) == lubridate::year(T2) - 1L  ~ "03 new years trip",
        T1 > T2                                           ~ "04 departure after arrival",
        T1 == T2                                          ~ "05 departure equals arrival",
        T2 > dplyr::lead(T1)                              ~ "06 next departure before current arrival",
        dplyr::lag(T2) > T1                               ~ "07 previous arrival after current departure",
        is.na(.data$length)                               ~ "08 no vessel length",
        is.na(kw)                                         ~ "09 no engine power",
        .default = "ok")) |>
    dplyr::ungroup()

  if (no_hands == TRUE) {
    trips <- trips |>
      dplyr::filter(.tchecks == "ok") |>
      dplyr::select(-.tchecks)
  }

  return(trips)
}


#' Check Fishing Events for Data Quality Issues
#'
#' @description
#' Adds an `.echecks` column to an events data frame (as returned by
#' \code{\link{fd_events}}) with the first failing quality check for each row,
#' or `"ok"` if all checks pass.
#'
#' By default (`no_hands = TRUE`) the function filters out failing events and
#' drops `.echecks` before returning — suitable for production pipelines. Set
#' `no_hands = FALSE` to retain all events with the `.echecks` label for
#' interactive diagnostics:
#' ```r
#' events |>
#'   fd\_flag\_events(no_hands = FALSE) |>
#'   dplyr::count(.echecks)
#' ```
#'
#' Checks are performed in the following order and return the first failure:
#' \describe{
#'   \item{`"01 duplicate event id and catch date"`}{Duplicate of a previous row with the same `lid` (`LE_ID`) and `date` (`LE_CDAT`)}
#'   \item{`"02 gear (metier 4) invalid"`}{`gear` (`LE_GEAR`) is not in the supplied `gear` vector (skipped if `gear = NULL`)}
#'   \item{`"03 metier 6 invalid"`}{`met6` (`LE_MET`) is not in the supplied `met6` vector (skipped if `met6 = NULL`)}
#'   \item{`"04 start time missing"`}{`t1` is `NA` (only checked when `t1`/`t2` are present)}
#'   \item{`"05 end time missing"`}{`t2` is `NA`}
#'   \item{`"06 start time after end time"`}{`t1 > t2`}
#'   \item{`"07 start time equals end time"`}{`t1 == t2`}
#'   \item{`"08 overlaps with a previous event"`}{`t1` falls before the cumulative
#'     maximum of all preceding `t2` values within the trip — detects all cascading
#'     overlaps in a single pass, not just adjacent ones}
#'   \item{`"ok"`}{All checks passed}
#' }
#'
#' Checks 04–08 apply only when `t1`, `t2`, and `.tsrc` columns are present
#' **and** `.tsrc != "dummy"`. Dummy times (`t1 = 00:01`, `t2 = 23:59`) are
#' synthetic placeholders created when `LE_STIME`/`LE_ETIME` are absent — they
#' carry no real temporal information, so overlap detection against them would
#' produce meaningless failures. Events are sorted by `t1` within each trip
#' before the overlap check is applied. Check 08 may produce false positives for
#' static gears where simultaneous deployments are valid.
#'
#' **Note:** Catch-date range checks (`date` (`LE_CDAT`) vs. trip departure/arrival)
#' are not performed here because events are separated from trips at this stage.
#' Those checks are available in \code{\link{fd_flag_eflalo}} when working with
#' the full joined EFLALO data frame.
#'
#' @param events A data frame of fishing events as returned by
#'   \code{\link{fd_events}}. Must contain `lid` (`LE_ID`), `date` (`LE_CDAT`),
#'   `gear` (`LE_GEAR`), and `met6` (`LE_MET`). If `t1` and `t2` are present,
#'   temporal checks 04–08 are also applied.
#' @param no_hands Logical. Controls whether failing events are automatically
#'   removed from the output. When `TRUE` (default, production mode), events
#'   where `.echecks != "ok"` are filtered out and the `.echecks` column is
#'   dropped before returning. When `FALSE` (diagnostic mode), all events are
#'   returned with `.echecks` appended so you can inspect failures.
#' @param gear Character vector of valid ICES gear codes (metier level 4).
#'   Obtain via `icesVocab::getCodeList("GearType")$Key`. If `NULL` (default),
#'   the gear check is skipped.
#' @param met6 Character vector of valid ICES metier level 6 codes.
#'   Obtain via `icesVocab::getCodeList("Metier6_FishingActivity")$Key`. If
#'   `NULL` (default), the metier check is skipped.
#'
#' @return
#'   * `no_hands = TRUE` (default): The input data frame filtered to passing
#'     events only, with `.echecks` dropped.
#'   * `no_hands = FALSE`: The full input data frame with an `.echecks`
#'     character column appended (first failing check label, or `"ok"`).
#'
#' @seealso \code{\link{fd_events}}, \code{\link{fd_flag_trips}},
#'   \code{\link{fd_flag_eflalo}}
#'
#' @examples
#' \dontrun{
#' # Production: get only valid events
#' events <- fd_events(eflalo) |> fd_flag_events()
#'
#' # Diagnostic: inspect all check labels
#' fd_events(eflalo) |>
#'   fd_flag_events(no_hands = FALSE) |>
#'   dplyr::count(.echecks)
#' }
#'
#' @export
fd_flag_events <- function(events,
                           no_hands = TRUE,
                           gear = NULL,
                           met6 = NULL) {
  has_times <- all(c("t1", "t2", ".tsrc") %in% names(events))

  # NOTE: duplicated() is not duckdb-compatible
  if (has_times) events <- dplyr::arrange(events, .tid, t1)

  events <- events |>
    dplyr::group_by(.tid) |>
    dplyr::mutate(
      # Cumulative max of t2 — only meaningful when real times exist.
      # NAs in t2 are replaced with -Inf so they don't propagate through cummax.
      .prev_max_t2 = if (has_times) {
        dplyr::lag(cummax(dplyr::if_else(is.na(t2), -Inf, as.numeric(t2))))
      } else {
        NA_real_
      },
      # Non-temporal checks: always applied
      .echecks = dplyr::case_when(
        base::duplicated(paste(lid, .data$date))   ~ "01 duplicate event id and catch date",
        !is.null(gear) & !.data$gear %in% gear     ~ "02 gear (metier 4) invalid",
        !is.null(met6) & !.data$met6 %in% met6     ~ "03 metier 6 invalid",
        .default = "ok"
      )
    )

  # Temporal checks (04-08): only when real (non-dummy) times are present.
  # Dummy times (00:01 / 23:59) are synthetic placeholders — overlap detection
  # against them would incorrectly flag all events sharing the same date.
  if (has_times) {
    events <- events |>
      dplyr::mutate(
        .echecks = dplyr::case_when(
          .echecks != "ok"                                               ~ .echecks,
          .data$.tsrc == "dummy"                                         ~ "ok",
          is.na(t1)                                                      ~ "04 start time missing",
          is.na(t2)                                                      ~ "05 end time missing",
          t1 > t2                                                        ~ "06 start time after end time",
          t1 == t2                                                       ~ "07 start time equals end time",
          # Single-pass overlap detection: flag any event whose t1 falls before
          # the latest t2 of all preceding events (cummax). This correctly handles
          # cascading overlaps that lead/lag-of-1 misses.
          # NOTE: may produce false positives for static gears with simultaneous deployments
          !is.na(.prev_max_t2) & !is.infinite(.prev_max_t2) &
            as.numeric(t1) < .prev_max_t2                               ~ "08 overlaps with a previous event",
          .default = "ok"
        )
      )
  }

  events <- events |>
    dplyr::select(-.prev_max_t2) |>
    dplyr::ungroup()

  if (no_hands == TRUE) {
    events <- events |>
      dplyr::filter(.echecks == "ok") |>
      dplyr::select(-.echecks)
  }

  return(events)
}


#' EFLALO quality checks
#'
#' @description
#' An orchestrating wrapper that applies \code{\link{fd_flag_trips}} and
#' \code{\link{fd_flag_events}} to a full EFLALO data frame, then composes their
#' results into a single `.checks` column. Trip-level failures take priority over
#' event-level failures; two cross-level checks (catch date vs. trip window) are
#' added that cannot be performed in either sub-function alone.
#'
#' Assumes `T1` (`FT_DDATIM`), `T2` (`FT_LDATIM`, POSIXct), and `date`
#' (`LE_CDAT`, Date) are already present — run `fd_clean_eflalo()` first.
#'
#' By default (`no_hands = TRUE`) failing records are filtered out and `.checks`
#' is dropped. Set `no_hands = FALSE` to retain all records with `.checks` for
#' diagnostics:
#' ```r
#' osfd::eflalo |>
#'   fd\_clean\_eflalo() |>
#'   fd\_flag\_eflalo(no_hands = FALSE) |>
#'   dplyr::count(.checks)
#' ```
#'
#' **Trip-level checks** (see \code{\link{fd_flag_trips}} for full details):
#' \describe{
#'   \item{`"01 departure missing"` … `"09 no engine power"`}{Propagated verbatim
#'     from \code{\link{fd_flag_trips}}; all events belonging to a failing trip
#'     inherit the trip's label.}
#' }
#'
#' **Event-level checks** (see \code{\link{fd_flag_events}} for full details):
#' \describe{
#'   \item{`"01 duplicate event id and catch date"` … `"08 overlaps with a previous event"`}{
#'     Propagated verbatim from \code{\link{fd_flag_events}}; applied only to
#'     events whose trip passed all trip-level checks.}
#' }
#'
#' **Cross-level checks** (require both trip and event info; only applied when
#' both trip and event pass):
#' \describe{
#'   \item{`"catch date before departure"`}{`date` (`LE_CDAT`) precedes `T1` (`FT_DDATIM`)}
#'   \item{`"catch date after arrival"`}{`date` (`LE_CDAT`) is later than `T2` (`FT_LDATIM`)}
#' }
#'
#' **Note on duplicates:** \code{\link{fd_events}} errors if the events data frame
#' contains exact duplicate rows. If your data may have duplicates, run
#' `dplyr::distinct()` on `eflalo` before calling this function, or use
#' \code{\link{fd_flag_events}} directly on the output of \code{\link{fd_events}}.
#'
#' @param eflalo A data frame in EFLALO format as returned by `fd_clean_eflalo()`.
#'   Must contain `.tid`, `.eid`, `cid` (`VE_COU`), `vid` (`VE_REF`), `length`
#'   (`VE_LEN`), `kw` (`VE_KW`), `gt` (`VE_TON`), `tid` (`FT_REF`), `T1`
#'   (`FT_DDATIM`, POSIXct), `T2` (`FT_LDATIM`, POSIXct), `date` (`LE_CDAT`,
#'   Date), `gear` (`LE_GEAR`), and `met6` (`LE_MET`).
#' @param no_hands Logical. Controls whether failing records are automatically
#'   removed from the output. When `TRUE` (default, production mode), records
#'   where `.checks != "ok"` are filtered out and `.checks` is dropped. When
#'   `FALSE` (diagnostic mode), all records are returned with `.checks` appended.
#' @param gear Character vector of valid ICES gear codes (metier level 4).
#'   Passed to \code{\link{fd_flag_events}}.
#'   Obtain via `icesVocab::getCodeList("GearType")$Key`. If `NULL` (default),
#'   the gear check is skipped.
#' @param met6 Character vector of valid ICES metier level 6 codes.
#'   Passed to \code{\link{fd_flag_events}}.
#'   Obtain via `icesVocab::getCodeList("Metier6_FishingActivity")$Key`. If
#'   `NULL` (default), the metier check is skipped.
#'
#' @return
#'   * `no_hands = TRUE` (default): The input data frame filtered to passing
#'     records only, with `.checks` dropped.
#'   * `no_hands = FALSE`: The full input data frame with a `.checks` character
#'     column appended (first failing check label, or `"ok"`).
#'
#' @seealso \code{\link{fd_flag_trips}}, \code{\link{fd_flag_events}},
#'   \code{\link{fd_trips}}, \code{\link{fd_events}}
#'
#' @examples
#' \dontrun{
#' # Production: get only clean records
#' osfd::eflalo |>
#'   fd_clean_eflalo() |>
#'   fd_flag_eflalo()
#'
#' # Diagnostic: inspect all check labels
#' osfd::eflalo |>
#'   fd_clean_eflalo() |>
#'   fd_flag_eflalo(no_hands = FALSE) |>
#'   dplyr::count(.checks)
#' }
#'
#' @export
fd_flag_eflalo <- function(eflalo,
                           no_hands = TRUE,
                           gear = NULL,
                           met6 = NULL) {

  # Trip-level flags — joined back via the internal trip id (.tid)
  .tchecks_df <-
    eflalo |>
    fd_trips() |>
    fd_flag_trips(no_hands = FALSE) |>
    dplyr::select(.tid, .tchecks)

  # Event-level flags — joined back via the internal event id (.eid)
  .echecks_df <-
    eflalo |>
    fd_events() |>
    fd_flag_events(no_hands = FALSE, gear = gear, met6 = met6) |>
    dplyr::select(.eid, .echecks)

  result <-
    eflalo |>
    dplyr::left_join(.tchecks_df, by = ".tid") |>
    dplyr::left_join(.echecks_df, by = ".eid") |>
    dplyr::mutate(
      .checks = dplyr::case_when(
        # Trip-level failures propagate to all events on that trip
        .tchecks != "ok"                            ~ .tchecks,
        # Event-level failures (only reached if trip passed)
        .echecks != "ok"                            ~ .echecks,
        # Cross-level: catch date vs. trip window (requires full eflalo)
        .data$date < lubridate::as_date(T1)         ~ "catch date before departure",
        .data$date > lubridate::as_date(T2)         ~ "catch date after arrival",
        .default = "ok"
      )
    ) |>
    dplyr::select(-.tchecks, -.echecks)

  if (no_hands == TRUE) {
    result <- result |>
      dplyr::filter(.checks == "ok") |>
      dplyr::select(-.checks)
  }

  return(result)
}
