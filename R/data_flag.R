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
#' **This function never filters.** Filtering is deliberately left to the caller:
#' ```r
#' tacsat |>
#'   fd\_flag\_tacsat() |>
#'   dplyr::filter(.checks == "ok")
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
#' @param area A spatial object (sf) containing the area of interest. If `NULL`
#'   (default), the function uses `osfd::ices_areas`. Records outside this area
#'   fail the check.
#' @param harbours A spatial object (sf) containing harbour locations. If not
#'   already an sf object, it should have `lon` and `lat` columns. Harbours are
#'   automatically buffered to 3 km radius and converted to Web Mercator
#'   (EPSG:3857) for accurate distance calculations before being transformed
#'   back to WGS84 (EPSG:4326). Default: `osfd::harbours`.
#'
#' @return The input data frame (with geometry dropped) with two new columns
#'   appended:
#'   \describe{
#'     \item{`.checks`}{Character. First failing check label, or `"ok"`.}
#'     \item{`.intv`}{Numeric. Time interval in seconds since the previous ping
#'       for the same vessel.}
#'   }
#'
#' @examples
#' \dontrun{
#' osfd::tacsat |>
#'   fd_clean_tacsat() |>
#'   fd_flag_tacsat() |>
#'   dplyr::count(.checks)
#' }
#'
#' @export
fd_flag_tacsat <- function(tacsat,
                            minimum_interval_seconds = 30,
                            area = osfd::ices_areas,
                            harbours = osfd::harbours) {

  if (!inherits(harbours, "sf")) {
    harbours <-
      harbours |>
      sf::st_as_sf(coords = c("lon", "lat"),
                   crs = 4326) |>
      sf::st_transform(crs = 3857) |>
      sf::st_buffer(dist = 3000) |>
      sf::st_transform(crs = 4326) |>
      dplyr::mutate(.in_harbour = TRUE) |>
      dplyr::select(.in_harbour)
  } else {
    harbours <-
      harbours |>
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
    sf::st_join(area |> dplyr::mutate(.in = TRUE) |> dplyr::select(.in)) |>
    sf::st_join(harbours) |>
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
    flagged <- dplyr::bind_rows(na_coords, flagged)
  }

  flagged
}


# ── EFLALO checks ──────────────────────────────────────────────────────────────

#' Check for Temporal Overlaps in Fishing Trips
#'
#' Validates the temporal sequence of fishing trips for each vessel by checking
#' for overlapping or out-of-sequence departure and arrival times. This function
#' is typically applied after extracting trips with \code{\link{fd_trips}}.
#'
#' **This function never filters.** Filtering is deliberately left to the caller:
#' ```r
#' trips |>
#'   fd\_flag\_trips() |>
#'   dplyr::filter(.tchecks == "ok")
#' ```
#'
#' Checks are performed in the following order and return the first failure:
#' \describe{
#'   \item{`"01 departure missing"`}{`T1` (`FT_DDATIM`) is `NA`}
#'   \item{`"02 arrival missing"`}{`T2` (`FT_LDATIM`) is `NA`}
#'   \item{`"03 departure after arrival"`}{`T1 > T2` — time travel not supported}
#'   \item{`"04 departure equals arrival"`}{`T1 == T2` — a trip of zero duration}
#'   \item{`"05 next departure before current arrival"`}{Temporal overlap: the next trip departs before this one lands}
#'   \item{`"06 previous arrival after current departure"`}{Temporal overlap: the previous trip's landing is after this departure}
#'   \item{`"07 no vessel length"`}{`length` (`VE_LEN`) is `NA` (informational — required for gear width and swept area)}
#'   \item{`"08 no engine power"`}{`kw` (`VE_KW`) is `NA` (informational — gear width falls back to lookup table defaults)}
#'   \item{`"ok"`}{All checks passed}
#' }
#'
#' @param trips A data frame containing fishing trip data with at minimum the
#'   following columns: `cid` (`VE_COU`, vessel country), `vid` (`VE_REF`, vessel
#'   reference), `T1` (`FT_DDATIM`, departure date/time), `T2` (`FT_LDATIM`,
#'   landing date/time), `length` (`VE_LEN`), and `kw` (`VE_KW`). Typically
#'   produced by \code{\link{fd_trips}}. Input must be sorted by `T1` within
#'   each vessel (handled by `fd_clean_eflalo()`).
#'
#' @return The input data frame with a `.tchecks` character column appended.
#'
#' @seealso
#'   \code{\link{fd_trips}} for extracting trip-level data,
#'   \code{\link{fd_flag_events}} for event-level checks,
#'   \code{\link{fd_tidy_eflalo}} for extracting both trips and events in one call.
#'
#' @examples
#' \dontrun{
#'   trips <- fd_trips(eflalo)
#'   trips_checked <- fd_flag_trips(trips)
#'   dplyr::filter(trips_checked, !grepl("^ok", .tchecks))
#' }
#'
#' @export
fd_flag_trips <- function(trips) {
  trips |>
    dplyr::group_by(cid, vid) |>
    dplyr::mutate(
      .tchecks = dplyr::case_when(
        is.na(T1)                                ~ "01 departure missing",
        is.na(T2)                                ~ "02 arrival missing",
        T1 > T2                                  ~ "03 departure after arrival",
        T1 == T2                                 ~ "04 departure equals arrival",
        T2 > dplyr::lead(T1)                     ~ "05 next departure before current arrival",
        dplyr::lag(T2) > T1                      ~ "06 previous arrival after current departure",
        is.na(.data$length)                      ~ "07 no vessel length",
        is.na(kw)                                ~ "08 no engine power",
        .default = "ok")) |>
    dplyr::ungroup()
}


#' Check Fishing Events for Data Quality Issues
#'
#' @description
#' Adds an `.echecks` column to an events data frame (as returned by
#' \code{\link{fd_events}}) with the first failing quality check for each row,
#' or `"ok"` if all checks pass.
#'
#' **This function never filters.** Filtering is deliberately left to the caller:
#' ```r
#' events |>
#'   fd\_flag\_events() |>
#'   dplyr::filter(.echecks == "ok")
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
#' Checks 04–08 apply only when `t1` and `t2` columns are present (derived by
#' `fd_clean_eflalo()` from `LE_STIME`/`LE_ETIME`). Events are sorted by `t1`
#' within each trip before the overlap check is applied. Check 08 may produce
#' false positives for static gears where simultaneous deployments are valid.
#'
#' **Note:** Catch-date range checks (`date` (`LE_CDAT`) vs. trip departure/arrival)
#' are not performed here because events are separated from trips at this stage.
#' Those checks are available in \code{\link{fd_flag_eflalo}} when working with
#' the full joined EFLALO data frame.
#'
#' @param events A data frame of fishing events as returned by
#'   \code{\link{fd_events}}. Must contain `lid` (`LE_ID`), `date` (`LE_CDAT`),
#'   `gear` (`LE_GEAR`), and `met6` (`LE_MET`). If `t1` and `t2` are present,
#'   temporal checks 04–09 are also applied.
#' @param gear Character vector of valid ICES gear codes (metier level 4).
#'   Obtain via `icesVocab::getCodeList("GearType")$Key`. If `NULL` (default),
#'   the gear check is skipped.
#' @param met6 Character vector of valid ICES metier level 6 codes.
#'   Obtain via `icesVocab::getCodeList("Metier6_FishingActivity")$Key`. If
#'   `NULL` (default), the metier check is skipped.
#'
#' @return The input data frame with an `.echecks` character column appended.
#'
#' @seealso \code{\link{fd_events}}, \code{\link{fd_flag_trips}},
#'   \code{\link{fd_flag_eflalo}}
#'
#' @examples
#' \dontrun{
#' events <- fd_events(eflalo)
#' events_checked <- fd_flag_events(events)
#' events_checked |> dplyr::count(.echecks)
#' }
#'
#' @export
fd_flag_events <- function(events,
                            gear = NULL,
                            met6 = NULL) {
  # NOTE: duplicated() is not duckdb-compatible
  events |>
    dplyr::arrange(.tid, t1) |>
    dplyr::group_by(.tid) |>
    dplyr::mutate(
      # Cumulative max of t2 before the current row (numeric seconds).
      # NAs in t2 are replaced with -Inf so they don't propagate through cummax.
      .prev_max_t2 = dplyr::lag(
        cummax(dplyr::if_else(is.na(t2), -Inf, as.numeric(t2)))
      ),
      .echecks = dplyr::case_when(
        base::duplicated(paste(lid, .data$date))                         ~ "01 duplicate event id and catch date",
        !is.null(gear) & !.data$gear %in% gear                          ~ "02 gear (metier 4) invalid",
        !is.null(met6) & !.data$met6 %in% met6                          ~ "03 metier 6 invalid",
        is.na(t1)                                                        ~ "04 start time missing",
        is.na(t2)                                                        ~ "05 end time missing",
        t1 > t2                                                          ~ "06 start time after end time",
        t1 == t2                                                         ~ "07 start time equals end time",
        # Single-pass overlap detection: flag any event whose t1 falls before
        # the latest t2 of all preceding events (cummax). This correctly handles
        # cascading overlaps that lead/lag-of-1 misses.
        # NOTE: may produce false positives for static gears with simultaneous deployments
        !is.na(.prev_max_t2) & !is.infinite(.prev_max_t2) &
          as.numeric(t1) < .prev_max_t2                                  ~ "08 overlaps with a previous event",
        .default = "ok"
      )
    ) |>
    dplyr::select(-.prev_max_t2) |>
    dplyr::ungroup()
}


#' Single-pass EFLALO quality checks
#'
#' @description
#' Adds a `.checks` column to an EFLALO data frame in a single `case_when()` pass.
#' Each record is labelled with the first failing check, or `"ok"` if it passes
#' all of them.
#'
#' **This function never filters.** Filtering is deliberately left to the caller:
#' ```r
#' osfd::eflalo |>
#'   fd\_clean\_eflalo() |>
#'   fd\_flag\_eflalo() |>
#'   dplyr::filter(.checks == "ok")
#' ```
#'
#' The function assumes `T1` (`FT_DDATIM`), `T2` (`FT_LDATIM`, POSIXct), and
#' `date` (`LE_CDAT`, Date) are already present — run `fd_clean_eflalo()` first
#' and it handles all of that so you don't have to.
#'
#' Trip overlap detection is delegated to \code{\link{fd_flag_trips}} (via
#' \code{\link{fd_trips}}), then joined back to flag individual events whose
#' trip is overlapping.
#'
#' Checks are performed in the following order and return the first failure:
#' \describe{
#'   \item{`"01 duplicated events"`}{Duplicate row with the same `vid` (`VE_REF`), `lid` (`LE_ID`), and `date` (`LE_CDAT`)}
#'   \item{`"02 impossible time"`}{`T1` (`FT_DDATIM`) or `T2` (`FT_LDATIM`) is `NA`}
#'   \item{`"03 new years trip"`}{Departure year is exactly one less than landing year (trip crosses year boundary)}
#'   \item{`"04 departure after arrival"`}{`T1 > T2` — time travel not supported}
#'   \item{`"05 departure equals arrival"`}{`T1 == T2` — a trip of zero duration}
#'   \item{`"06 overlapping trips"`}{`T1` falls before `T2` of the previous trip for the same vessel}
#'   \item{`"07 gear (metier 4) invalid"`}{`gear` (`LE_GEAR`) not in `gear` vector (skipped if `gear = NULL`)}
#'   \item{`"08 metier 6 invalid"`}{`met6` (`LE_MET`) not in `met6` vector (skipped if `met6 = NULL`)}
#'   \item{`"09 catch date before departure"`}{`date` (`LE_CDAT`) precedes `T1` (`FT_DDATIM`) (informational)}
#'   \item{`"10 catch date after arrival"`}{`date` (`LE_CDAT`) is later than `T2` (`FT_LDATIM`) (informational)}
#'   \item{`"11 no vessel length"`}{`length` (`VE_LEN`) is `NA` (informational)}
#'   \item{`"12 no engine power"`}{`kw` (`VE_KW`) is `NA` (informational)}
#'   \item{`"ok"`}{All checks passed}
#' }
#'
#' Checks 09–12 are informational: they flag records that may warrant review
#' but are not necessarily errors. Use `dplyr::filter(.checks == "ok")` to
#' exclude all flagged records, or inspect specific check labels as needed.
#'
#' @param eflalo A data frame in EFLALO format as returned by `fd_clean_eflalo()`.
#'   Must contain `cid` (`VE_COU`), `vid` (`VE_REF`), `length` (`VE_LEN`),
#'   `kw` (`VE_KW`), `gt` (`VE_TON`), `tid` (`FT_REF`), `T1` (`FT_DDATIM`,
#'   POSIXct), `T2` (`FT_LDATIM`, POSIXct), `lid` (`LE_ID`), `date` (`LE_CDAT`,
#'   Date), `gear` (`LE_GEAR`), and `met6` (`LE_MET`).
#' @param year Integer. Submission year. When supplied, records with `T1`
#'   (`FT_DDATIM`) before 1 January of this year are flagged. If `NULL` (default),
#'   the check is skipped.
#' @param gear Character vector of valid ICES gear codes (metier level 4).
#'   Obtain via `icesVocab::getCodeList("GearType")$Key`. If `NULL` (default),
#'   the gear check is skipped.
#' @param met6 Character vector of valid ICES metier level 6 codes.
#'   Obtain via `icesVocab::getCodeList("Metier6_FishingActivity")$Key`. If
#'   `NULL` (default), the metier check is skipped.
#'
#' @return The input data frame with a `.checks` character column appended.
#'
#' @examples
#' \dontrun{
#' osfd::eflalo |>
#'   fd_clean_eflalo() |>
#'   fd_flag_eflalo() |>
#'   dplyr::count(.checks)
#' }
#'
#' @export
fd_flag_eflalo <- function(eflalo,
                            year = NULL,
                            gear = NULL,
                            met6 = NULL) {

  # Build trip-level overlap flags and join back to event rows
  trips <-
    eflalo |>
    fd_trips() |>
    fd_flag_trips() |>
    dplyr::mutate(.overlap = (.tchecks != "ok")) |>
    dplyr::select(cid, vid, `length`, kw, gt, tid, T1, T2, .overlap)

  eflalo |>
    dplyr::left_join(trips,
                     by = dplyr::join_by(cid, vid, length, kw, gt, tid, T1, T2)) |>
    dplyr::mutate(
      .checks = dplyr::case_when(
        # NOTE: duplicated() is not duckdb-compatible
        base::duplicated(paste(vid, lid, .data$date))                           ~ "01 duplicated events",
        is.na(T1) | is.na(T2)                                                   ~ "02 impossible time",
        lubridate::year(T1) == (lubridate::year(T2) - 1L)                       ~ "03 new years trip",
        T1 > T2                                                                  ~ "04 departure after arrival",
        T1 == T2                                                                 ~ "05 departure equals arrival",
        .overlap == TRUE                                                         ~ "06 overlapping trips",
        !is.null(gear) & !.data$gear %in% gear                                  ~ "07 gear (metier 4) invalid",
        !is.null(met6) & !.data$met6 %in% met6                                  ~ "08 metier 6 invalid",
        .data$date < lubridate::as_date(T1)                                     ~ "09 catch date before departure",
        .data$date > lubridate::as_date(T2)                                     ~ "10 catch date after arrival",
        is.na(.data$length)                                                      ~ "11 no vessel length",
        is.na(kw)                                                                ~ "12 no engine power",
        .default = "ok"
      )
    ) |>
    dplyr::select(-.overlap)
}
