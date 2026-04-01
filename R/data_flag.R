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
#' Expects a data frame as returned by `fd_clean_tacsat()` — `SI_LONG` and
#' `SI_LATI` are plain numeric columns at this stage. Data must be sorted by
#' `VE_REF` and `SI_DATIM` (also handled by `fd_clean_tacsat()`). The function
#' converts to `sf` internally for spatial operations, then drops geometry before
#' returning.
#'
#' **This function never filters.** Filtering is deliberately left to the caller:
#' ```r
#' tacsat |>
#'   fd\_check\_tacsat() |>
#'   dplyr::filter(.checks == "ok")
#' ```
#'
#' Checks are performed in the following order and return the first failure:
#' \describe{
#'   \item{`"01 point out of (ices) area"`}{Record falls outside the specified area of interest}
#'   \item{`"02 duplicate"`}{Duplicate of a previous record with the same vessel, position, and timestamp}
#'   \item{`"03 time interval too short"`}{Time since previous ping (per vessel) is less than `minimum_interval_seconds`}
#'   \item{`"04 in harbour"`}{Record location falls within a harbour buffer zone (3 km radius)}
#'   \item{`"05 no country id"`}{`VE_COU` is `NA`}
#'   \item{`"06 no vessel id"`}{`VE_REF` is `NA`}
#'   \item{`"07 no datetime"`}{`SI_DATIM` is `NA`}
#'   \item{`"08 no speed"`}{`SI_SP` is `NA`}
#'   \item{`"ok"`}{All checks passed}
#' }
#'
#' **Note:** This function is R-only. `sf` spatial joins, `base::duplicated()`,
#' and `fd_step_time()` are not compatible with lazy/DuckDB backends. Checks
#' 05–08 (NA guards) come after the spatial operations; records with `NA`
#' coordinates will cause `sf::st_as_sf()` to error — pre-filter those upstream
#' if needed.
#'
#' @param tacsat A TACSAT data frame as returned by `fd_clean_tacsat()`. Must
#'   contain `VE_COU`, `VE_REF`, `SI_DATIM` (POSIXct), `SI_LONG`, `SI_LATI`,
#'   and `SI_SP`.
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
  tacsat |>
    sf::st_as_sf(coords = c("SI_LONG", "SI_LATI"),
                 crs = 4326,
                 remove = FALSE) |>
    sf::st_join(area |> dplyr::mutate(.in = TRUE) |> dplyr::select(.in)) |>
    sf::st_join(harbours) |>
    dplyr::group_by(VE_REF) |>
    dplyr::mutate(.intv = fd_step_time(SI_DATIM)) |>
    dplyr::ungroup() |>
    dplyr::mutate(
      .checks = dplyr::case_when(
        is.na(.in)                                                              ~ "01 point out of (ices) area",
        # NOTE: duplicated() is not duckdb-compatible
        duplicated(paste(VE_COU, VE_REF, SI_LONG, SI_LATI, SI_DATIM))          ~ "02 duplicate",
        !is.na(.intv) & .intv < minimum_interval_seconds                        ~ "03 time interval too short",
        .in_harbour == TRUE                                                     ~ "04 in harbour",
        is.na(VE_COU)                                                           ~ "05 no country id",
        is.na(VE_REF)                                                           ~ "06 no vessel id",
        is.na(SI_DATIM)                                                         ~ "07 no datetime",
        is.na(SI_SP)                                                            ~ "08 no speed",
        .default = "ok")) |>
    dplyr::select(-c(.in_harbour, .in)) |>
    sf::st_drop_geometry()
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
#'   fd\_check\_trips() |>
#'   dplyr::filter(.tchecks == "ok")
#' ```
#'
#' Checks are performed in the following order and return the first failure:
#' \describe{
#'   \item{`"01 departure missing"`}{`FT_DDATIM` is `NA`}
#'   \item{`"02 arrival missing"`}{`FT_LDATIM` is `NA`}
#'   \item{`"03 departure after arrival"`}{`FT_DDATIM > FT_LDATIM` — time travel not supported}
#'   \item{`"04 departure equals arrival"`}{`FT_DDATIM == FT_LDATIM` — a trip of zero duration}
#'   \item{`"05 next departure before current arrival"`}{Temporal overlap: the next trip departs before this one lands}
#'   \item{`"06 previous arrival after current departure"`}{Temporal overlap: the previous trip's landing is after this departure}
#'   \item{`"07 no vessel length"`}{`VE_LEN` is `NA` (informational — required for gear width and swept area)}
#'   \item{`"08 no engine power"`}{`VE_KW` is `NA` (informational — gear width falls back to lookup table defaults)}
#'   \item{`"ok"`}{All checks passed}
#' }
#'
#' @param trips A data frame containing fishing trip data with at minimum the
#'   following columns: `VE_COU` (vessel country), `VE_REF` (vessel reference),
#'   `FT_DDATIM` (departure date/time), `FT_LDATIM` (landing date/time),
#'   `VE_LEN`, and `VE_KW`. Typically produced by \code{\link{fd_trips}}.
#'   Input must be sorted by `FT_DDATIM` within each vessel (handled by
#'   `fd_clean_eflalo()`).
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
    dplyr::group_by(VE_COU, VE_REF) |>
    dplyr::mutate(
      .tchecks = dplyr::case_when(
        is.na(FT_DDATIM)                         ~ "01 departure missing",
        is.na(FT_LDATIM)                         ~ "02 arrival missing",
        FT_DDATIM > FT_LDATIM                    ~ "03 departure after arrival",
        FT_DDATIM == FT_LDATIM                   ~ "04 departure equals arrival",
        FT_LDATIM > dplyr::lead(FT_DDATIM)       ~ "05 next departure before current arrival",
        dplyr::lag(FT_LDATIM) > FT_DDATIM        ~ "06 previous arrival after current departure",
        is.na(VE_LEN)                            ~ "07 no vessel length",
        is.na(VE_KW)                             ~ "08 no engine power",
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
#'   fd\_check\_events() |>
#'   dplyr::filter(.echecks == "ok")
#' ```
#'
#' Checks are performed in the following order and return the first failure:
#' \describe{
#'   \item{`"01 duplicate event id and catch date"`}{Duplicate of a previous row with the same `LE_ID` and `LE_CDAT`}
#'   \item{`"02 gear (metier 4) invalid"`}{`LE_GEAR` is not in the supplied `gear` vector (skipped if `gear = NULL`)}
#'   \item{`"03 metier 6 invalid"`}{`LE_MET` is not in the supplied `met6` vector (skipped if `met6 = NULL`)}
#'   \item{`"ok"`}{All checks passed}
#' }
#'
#' **Note:** Catch-date range checks (`LE_CDAT` vs. trip departure/arrival) are
#' not performed here because events are separated from trips at this stage.
#' Those checks are available in \code{\link{fd_flag_eflalo}} when working with
#' the full joined EFLALO data frame.
#'
#' @param events A data frame of fishing events as returned by
#'   \code{\link{fd_events}}. Must contain `LE_ID`, `LE_CDAT`, `LE_GEAR`, and
#'   `LE_MET`.
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
  events |>
    dplyr::mutate(
      .echecks = dplyr::case_when(
        # NOTE: duplicated() is not duckdb-compatible
        base::duplicated(paste(LE_ID, LE_CDAT))    ~ "01 duplicate event id and catch date",
        !is.null(gear) & !LE_GEAR %in% gear        ~ "02 gear (metier 4) invalid",
        !is.null(met6) & !LE_MET %in% met6         ~ "03 metier 6 invalid",
        .default = "ok"))
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
#'   fd\_setup\_eflalo() |>
#'   fd\_check\_eflalo() |>
#'   dplyr::filter(.checks == "ok")
#' ```
#'
#' The function assumes `FT_DDATIM`, `FT_LDATIM` (POSIXct), and `LE_CDAT`
#' (Date) are already present — run `fd_clean_eflalo()` first and it handles
#' all of that so you don't have to.
#'
#' Trip overlap detection is delegated to \code{\link{fd_flag_trips}} (via
#' \code{\link{fd_trips}}), then joined back to flag individual events whose
#' trip is overlapping.
#'
#' Checks are performed in the following order and return the first failure:
#' \describe{
#'   \item{`"01 duplicated events"`}{Duplicate row with the same `VE_REF`, `LE_ID`, and `LE_CDAT`}
#'   \item{`"02 impossible time"`}{`FT_DDATIM` or `FT_LDATIM` is `NA`}
#'   \item{`"03 new years trip"`}{Departure year is exactly one less than landing year (trip crosses year boundary)}
#'   \item{`"04 departure after arrival"`}{`FT_DDATIM > FT_LDATIM` — time travel not supported}
#'   \item{`"05 departure equals arrival"`}{`FT_DDATIM == FT_LDATIM` — a trip of zero duration}
#'   \item{`"06 overlapping trips"`}{`FT_DDATIM` falls before `FT_LDATIM` of the previous trip for the same vessel}
#'   \item{`"07 gear (metier 4) invalid"`}{`LE_GEAR` not in `gear` vector (skipped if `gear = NULL`)}
#'   \item{`"08 metier 6 invalid"`}{`LE_MET` not in `met6` vector (skipped if `met6 = NULL`)}
#'   \item{`"09 catch date before departure"`}{`LE_CDAT` precedes `FT_DDATIM` (informational)}
#'   \item{`"10 catch date after arrival"`}{`LE_CDAT` is later than `FT_LDATIM` (informational)}
#'   \item{`"11 no vessel length"`}{`VE_LEN` is `NA` (informational)}
#'   \item{`"12 no engine power"`}{`VE_KW` is `NA` (informational)}
#'   \item{`"ok"`}{All checks passed}
#' }
#'
#' Labels prefixed `"ok - ..."` are informational. Records with these labels
#' survive `dplyr::filter(startsWith(.checks, "ok"))` but are dropped by
#' `dplyr::filter(.checks == "ok")` if you want to be strict.
#'
#' @param eflalo A data frame in EFLALO format. Must contain `VE_COU`, `VE_REF`,
#'   `VE_LEN`, `VE_KW`, `VE_TON`, `FT_REF`, `FT_DDATIM`, `FT_LDATIM` (POSIXct),
#'   `LE_ID`, `LE_CDAT` (Date), `LE_GEAR`, and `LE_MET`.
#'   Run `fd_clean_eflalo()` before calling this.
#' @param year Integer. Submission year. When supplied, records with
#'   `FT_DDATIM` before 1 January of this year are flagged. If `NULL` (default),
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
    dplyr::select(
      VE_COU, VE_REF, VE_LEN, VE_KW, VE_TON,
      FT_REF, FT_DDATIM, FT_LDATIM, .overlap)

  eflalo |>
    dplyr::left_join(trips,
                     by = dplyr::join_by(VE_COU, VE_REF, VE_LEN, VE_KW, VE_TON,
                                         FT_REF, FT_DDATIM, FT_LDATIM)) |>
    dplyr::mutate(
      .checks = dplyr::case_when(
        # NOTE: duplicated() is not duckdb-compatible
        base::duplicated(paste(VE_REF, LE_ID, LE_CDAT))                         ~ "01 duplicated events",
        is.na(FT_DDATIM) | is.na(FT_LDATIM)                                    ~ "02 impossible time",
        lubridate::year(FT_DDATIM) == (lubridate::year(FT_LDATIM) - 1L)         ~ "03 new years trip",
        FT_DDATIM > FT_LDATIM                                                   ~ "04 departure after arrival",
        FT_DDATIM == FT_LDATIM                                                  ~ "05 departure equals arrival",
        .overlap == TRUE                                                        ~ "06 overlapping trips",
        !is.null(gear) & !LE_GEAR %in% gear                                     ~ "07 gear (metier 4) invalid",
        !is.null(met6) & !LE_MET %in% met6                                      ~ "08 metier 6 invalid",
        LE_CDAT < lubridate::as_date(FT_DDATIM)                                 ~ "09 catch date before departure",
        LE_CDAT > lubridate::as_date(FT_LDATIM)                                 ~ "10 catch date after arrival",
        is.na(VE_LEN)                                                           ~ "11 no vessel length",
        is.na(VE_KW)                                                            ~ "12 no engine power",
        .default = "ok"
      )
    ) |>
    dplyr::select(-.overlap)
}
