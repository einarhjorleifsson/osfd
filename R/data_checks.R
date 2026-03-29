# ── TACSAT checks ──────────────────────────────────────────────────────────────

#' Single-pass TACSAT quality checks ("myway")
#'
#' @description
#' Adds a `checks` column to a TACSAT data frame in a single `case_when()` pass,
#' labelling each record with the first failing check or `"ok"` if it passes all
#' of them. Also computes an `INTV` column (time in seconds since the previous
#' ping for the same vessel) which is used by the interval threshold check and is
#' useful downstream.
#'
#' Expects a data frame as returned by `fd_tacsat_clean()` — `SI_LONG` and
#' `SI_LATI` are plain numeric columns at this stage. Data must be sorted by
#' `VE_REF` and `SI_DATIM` (also handled by `fd_tacsat_clean()`). Convert to
#' `sf` later in the pipeline when spatial operations are needed.
#'
#' **This function never filters.** Filtering is deliberately left to the caller:
#' ```r
#' tacsat |>
#'   fd_check_tacsat() |>
#'   dplyr::filter(checks == "ok")
#' ```
#'
#' Check labels (in priority order):
#' \describe{
#'   \item{`"00 1 no country id"`}{`VE_COU` is `NA`}
#'   \item{`"00 2 no vessel id"`}{`VE_REF` is `NA`}
#'   \item{`"00 3 no time"`}{`SI_DATIM` is `NA`}
#'   \item{`"00 4 no position"`}{`SI_LONG` or `SI_LATI` is `NA`}
#'   \item{`"00 5 no speed"`}{`SI_SP` is `NA`}
#'   \item{`"02 duplicates"`}{Duplicate of a previous record with the same vessel, position, and timestamp}
#'   \item{`"03 coordinates out of bound"`}{Longitude outside ±180 or latitude outside ±90}
#'   \item{`"04 time interval too short"`}{Time since previous ping (per vessel) is less than `it_min` seconds}
#'   \item{`"ok"`}{All checks passed}
#' }
#'
#' @param tacsat A TACSAT data frame as returned by `fd_tacsat_clean()`. Must
#'   contain `VE_COU`, `VE_REF`, `SI_DATIM` (POSIXct), `SI_LONG`, `SI_LATI`,
#'   and `SI_SP`.
#' @param it_min Numeric. Minimum permitted time interval between consecutive
#'   pings for the same vessel, in **seconds**. Default: `300` (5 minutes).
#' @param area A spatial containing area of interest. If NULL (default) no checking done.
#' @param harbour A spatial table containing list of harbours
#'
#' @return The input data frame with two new columns appended:
#'   \describe{
#'     \item{`INTV`}{Time since previous ping per vessel, in seconds. `NA` for
#'       the first ping of each vessel (or where `SI_DATIM` is `NA`).}
#'     \item{`checks`}{Character. First failing check label, or `"ok"`.}
#'   }
#'
#' @examples
#' \dontrun{
#' tacsat |>
#'   fd_clean_tacsat() |>
#'   fd_check_tacsat() |>
#'   dplyr::count(checks)
#' }
#'
#' @export
fd_check_tacsat <- function(tacsat, it_min = 5 * 60, area = ices_areas, harbour = harbours) {

  tacsat |>
    sf::st_as_sf(coords = c("SI_LONG", "SI_LATI"),
                 crs = 4326,
                 remove = FALSE) |>
    sf::st_join(area |> dplyr::mutate(.in = TRUE) |> dplyr::select(.in)) |>
    sf::st_join(harbour |>
                  sf::st_as_sf(coords = c("lon", "lat"),
                               crs = 4326) |>
                  sf::st_transform(crs = 3857) |>
                  sf::st_buffer(dist = 3000) |>
                  sf::st_transform(crs = 4326) |>
                  dplyr::mutate(.in_harbour = TRUE) |>
                  dplyr::select(.in_harbour)) |>
    dplyr::group_by(VE_COU, VE_REF) |>
    dplyr::mutate(
      .intv = c(NA_real_, diff(as.numeric(SI_DATIM)))
    ) |>
    dplyr::ungroup() |>
    dplyr::mutate(
      checks = dplyr::case_when(is.na(.in) ~ "01 point out of area",
                                duplicated(paste(VE_COU, VE_REF, SI_LONG, SI_LATI, SI_DATIM)) ~ "02 duplicate",
                                !is.na(.intv) & .intv < it_min         ~ "03 time interval too short",
                                .in_harbour == TRUE ~ "04 in harbour",
                                .default = "ok")) |>
    dplyr::select(-c(.in_harbour, .intv, .in)) |>
    sf::st_drop_geometry()
}


# ── EFLALO checks ──────────────────────────────────────────────────────────────

#' Single-pass EFLALO quality checks ("myway")
#'
#' @description
#' Adds a `checks` column to an EFLALO data frame in a single `case_when()` pass.
#' Each record is labelled with the first failing check, or `"ok"`. The
#' approach mirrors the "myway" design in
#' `documentation/dataflow_dplyr_thenduckdb.qmd`.
#'
#' **This function never filters.** Filtering is deliberately left to the caller:
#' ```r
#' eflalo |>
#'   fd_check_eflalo(iv_gear, iv_met6) |>
#'   dplyr::filter(startsWith(checks, "ok"))
#' ```
#' Note that some checks are labelled `"ok - ..."` (informational only) and will
#' survive a `startsWith(checks, "ok")` filter. Use exact matching if you want
#' to drop those too.
#'
#' The function assumes `FT_DDATIM`, `FT_LDATIM` (POSIXct), and `LE_CDAT`
#' (Date) are already present — run `fd_eflalo_clean()` first and it handles
#' all of that so you don't have to.
#'
#' Check labels (in priority order):
#' \describe{
#'   \item{`"01 duplicated events"`}{Duplicate of a previous row with the same `VE_REF`, `LE_ID`, and `LE_CDAT`}
#'   \item{`"02 impossible time"`}{`FT_DDATIM` or `FT_LDATIM` is `NA`}
#'   \item{`"03 new years trip"`}{Departure year is exactly one less than landing year (trip crosses year boundary)}
#'   \item{`"04 departure after arrival"`}{`FT_DDATIM` is strictly later than `FT_LDATIM` — time travel not supported}
#'   \item{`"05 departure equals arrival"`}{`FT_DDATIM == FT_LDATIM` — a trip of zero duration raises an eyebrow}
#'   \item{`"06 before submission year"`}{`FT_DDATIM` falls before 1 January of `year` (only checked when `year` is supplied)}
#'   \item{`"07 gear (metier 4) invalid"`}{`LE_GEAR` is not in `iv_gear` (if supplied)}
#'   \item{`"08 metier 6 invalid"`}{`LE_MET` is not in `iv_met6` (if supplied)}
#'   \item{`"09 no vessel length"`}{`VE_LEN` is `NA` — vessel length is required for gear width and swept area calculations}
#'   \item{`"10 no vessel tonnage"`}{`VE_TON` is `NA`}
#'   \item{`"ok - 11 no engine power"`}{`VE_KW` is `NA` (informational — gear width will fall back to lookup table defaults)}
#'   \item{`"ok - 12 no mesh size"`}{`LE_MSZ` is `NA` (informational)}
#'   \item{`"ok - 13 catch date before departure"`}{`LE_CDAT` precedes `FT_DDATIM` (informational)}
#'   \item{`"ok - 14 catch date after arrival"`}{`LE_CDAT` is later than `FT_LDATIM` (informational)}
#'   \item{`"ok"`}{All checks passed}
#' }
#'
#' Labels prefixed `"ok - ..."` are informational. Records with these labels survive
#' `dplyr::filter(startsWith(checks, "ok"))` but are dropped by
#' `dplyr::filter(checks == "ok")` if you want to be strict.
#'
#' Check "overlapping trips" is intentionally absent — it requires a
#' separate per-vessel pass. Use `fd_overlapping_trips()` for that.
#'
#' @param eflalo A data frame in EFLALO format. Must contain `VE_REF`, `LE_ID`,
#'   `LE_CDAT` (Date), `FT_DDATIM`, `FT_LDATIM`, `LE_GEAR`, and `LE_MET`.
#'   Run `fd_eflalo_clean()` before calling this.
#' @param gear Character vector of valid ICES gear codes (metier level 4).
#'   Obtain via `icesVocab::getCodeList("GearType")$Key`. If `NULL` (default),
#'   the gear check is skipped.
#' @param met6 Character vector of valid ICES metier level 6 codes.
#'   Obtain via `icesVocab::getCodeList("Metier6_FishingActivity")$Key`. If
#'   `NULL` (default), the metier check is skipped.
#' @param year Integer. Submission year. When supplied, records with
#'   `FT_DDATIM` before 1 January of this year are flagged as
#'   `"06 before submission year"`. If `NULL` (default), the check is skipped.
#'
#' @return The input data frame with a `checks` character column appended.
#'
#' @examples
#' \dontrun{
#' eflalo |>
#'   fd_clean_eflalo() |>
#'   dplyr::count(checks)
#' }
#'
#' @export
fd_eflalo_check <- function(eflalo,
                            year = NULL,
                            gear = icesVocab::getCodeList("GearType")$Key,
                            met6 = icesVocab::getCodeList("Metier6_FishingActivity")$Key) {

  # trip overlaps
  d <- eflalo |> fd_split_eflalo()
  d$trips <-
    d$trips |>
    dplyr::arrange(VE_COU, VE_REF, FT_REF, FT_DDATIM, FT_LDATIM) |>
    dplyr::group_by(VE_COU, VE_REF, FT_REF) |>
    dplyr::mutate(
      .overlap =
        dplyr::case_when(FT_LDATIM > dplyr::lead(FT_DDATIM) ~ TRUE,
                         .default = FALSE)) |>
    dplyr::ungroup()

  eflalo |>
    dplyr::left_join(d$trips,
              by = dplyr::join_by(VE_REF, VE_COU, VE_LEN, VE_KW, VE_TON, FT_REF, FT_DDATIM, FT_LDATIM)) |>
    dplyr::mutate(
      checks = dplyr::case_when(
        #                                                                ~ "01 - catch out of bound"
        base::duplicated(paste(VE_REF, LE_ID, LE_CDAT))                  ~ "02 - Remove non-unique event number",
        is.na(FT_DDATIM) | is.na(FT_LDATIM)                              ~ "03 - missing departure or arrival time",
        !is.null(year) & lubridate::year(FT_DDATIM) < year               ~ "04 - departure before submission year",
        lubridate::year(FT_DDATIM) == (lubridate::year(FT_LDATIM) - 1L)  ~ "04 - new years trip",
        FT_DDATIM > FT_LDATIM                                            ~ "05 - departure after arrival",
        FT_DDATIM == FT_LDATIM                                           ~ "05 - departure equals arrival",
        .overlap == TRUE                                                 ~ "06 - overlapping trips",
        !is.null(gear) & !LE_GEAR %in% gear                              ~ "07 - gear (metier 4) invalid",
        !is.null(met6) & !LE_MET %in% met6                               ~ "08 - metier 6 invalid",
        LE_CDAT < lubridate::as_date(FT_DDATIM)                          ~ "ok - catch date before departure",
        LE_CDAT > lubridate::as_date(FT_LDATIM)                          ~ "ok - catch date after arrival",
        is.na(VE_LEN)                                                    ~ "ok - no vessel length",
        is.na(VE_TON)                                                    ~ "ok - no vessel tonnage",
        is.na(VE_KW)                                                     ~ "ok - no engine power",
        is.na(LE_MSZ)                                                    ~ "ok - no mesh size",
        .default = "ok"
      )
    )
}


# ── fd_split_eflalo ────────────────────────────────────────────────────────────

#' Split EFLALO into trip and event tables
#'
#' @description
#' Splits an EFLALO data frame into two tidy tables:
#' \describe{
#'   \item{`trips`}{One row per fishing trip. Contains vessel characteristics
#'     and departure/landing datetimes.}
#'   \item{`events`}{One row per log event. Contains gear, catch, and date
#'     information.}
#' }
#'
#' Separating the two concerns up front makes downstream joins explicit and
#' SQL-compatible — no more wondering which column belongs to which level of
#' aggregation.
#'
#' The function expects `FT_DDATIM` and `FT_LDATIM` POSIXct columns to be
#' present (run `fd_eflalo_clean()` first if needed).
#'
#' @param eflalo A data frame in EFLALO format.
#'
#' @return A named list with two elements:
#'   \describe{
#'     \item{`trips`}{A tibble with columns `VE_COU`, `VE_REF`, `VE_LEN`,
#'       `VE_KW`, `VE_TON`, `FT_REF`, `FT_DDATIM`, `FT_LDATIM`. One row per
#'       unique trip (`VE_REF` × `FT_REF`).}
#'     \item{`events`}{A tibble with columns `VE_COU`, `VE_REF`, `FT_REF`,
#'       and all `LE_*` columns from the input.}
#'   }
#'
#' @examples
#' \dontrun{
#' parts  <- fd_split_eflalo(eflalo)
#' trips  <- parts$trips
#' events <- parts$events
#' }
#'
#' @export
fd_split_eflalo <- function(eflalo) {
  trips <- eflalo |>
    dplyr::select(
      VE_COU, VE_REF, VE_LEN, VE_KW, VE_TON,
      FT_REF, FT_DDATIM, FT_LDATIM
    ) |>
    dplyr::distinct(VE_COU, VE_REF, FT_REF, .keep_all = TRUE)

  events <- eflalo |>
    dplyr::select(
      VE_COU, VE_REF, FT_REF,
      dplyr::starts_with("LE_")
    )

  list(trips = trips, events = events)
}




