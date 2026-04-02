#' Validate, coerce and prepare TACSAT data
#'
#' @description
#' One call to rule them all (for TACSAT, at least). Does the following in order:
#'
#' 1. Checks that all required columns are present.
#' 2. Coerces `SI_LATI`, `SI_LONG`, `SI_SP`, and `SI_HE` to numeric.
#' 3. Parses `SI_DATE` + `SI_TIME` into a single `SI_DATIM` POSIXct column and
#'    drops the originals — because two columns are strictly worse than one.
#' 4. Sorted by `VE_REF` then `SI_DATIM` — the order that interval calculations
#'    downstream depend on.
#'
#' After this call, `SI_DATE` and `SI_TIME` are gone (unless `remove = FALSE`).
#'
#' **Note:** This function is R-only. `paste()`, `lubridate::dmy_hms()`, and
#' `dplyr::row_number()` inside `arrange()` + `mutate()` are not compatible with
#' lazy/DuckDB backends.
#'
#' @param tacsat A data frame in TACSAT format. Must contain `VE_COU`, `VE_REF`,
#'   `SI_DATE`, `SI_TIME`, `SI_LATI`, `SI_LONG`, `SI_SP`, and `SI_HE`.
#' @param remove Logical. If `TRUE` (default), the raw date/time columns
#'   `SI_DATE` and `SI_TIME` are dropped once `SI_DATIM` has been constructed.
#'   Set to `FALSE` to retain the originals.
#'
#' @return A data frame sorted by `VE_REF` and `SI_DATIM`, with:
#'   \describe{
#'     \item{`.pid`}{Integer row identifier (added for downstream diagnostics).}
#'     \item{`SI_DATIM`}{POSIXct timestamp (UTC) parsed from `SI_DATE` + `SI_TIME`.}
#'   }
#'   `SI_DATE` and `SI_TIME` are removed by default.
#'
#' @examples
#' \dontrun{
#' tacsat <- fd_clean_tacsat(tacsat)
#' }
#'
#' @export
fd_clean_tacsat <- function(tacsat, remove = TRUE) {
  required_cols <- c("VE_COU", "VE_REF", "SI_DATE", "SI_TIME",
                     "SI_LATI", "SI_LONG", "SI_SP", "SI_HE")
  missing <- required_cols[!required_cols %in% names(tacsat)]
  if (length(missing) > 0)
    stop("Column(s) missing in tacsat: ", paste(missing, collapse = ", "))

  # NOTE: paste(), lubridate::dmy_hms(), and row_number() are R-only; not duckdb-compatible
  tacsat <-
    tacsat |>
    dplyr::mutate(
      dplyr::across(dplyr::all_of(c("SI_LATI", "SI_LONG", "SI_SP", "SI_HE")), as.numeric),
      SI_DATIM = lubridate::dmy_hms(paste(SI_DATE, SI_TIME), tz = "UTC"),
      .before = SI_DATE
    ) |>
    dplyr::arrange(VE_REF, SI_DATIM) |>
    dplyr::mutate(.pid = dplyr::row_number(),
                  .before = VE_COU)

  if (remove) tacsat <- tacsat |> dplyr::select(-c(SI_DATE, SI_TIME))

  return(tacsat)
}


#' Validate and coerce EFLALO columns
#'
#' @description
#' Checks that the required vessel, trip, and catch columns are present in an
#' EFLALO data frame, then gets the types right so nothing downstream has to
#' guess: numeric columns are coerced to numeric; `FT_DDATIM` and `FT_LDATIM`
#' are constructed from the raw date/time string columns; and `LE_CDAT` is
#' re-parsed from its character form (`"DD/MM/YYYY"`) to an R Date.
#'
#' Two internal key columns are also added:
#' \describe{
#'   \item{`.eid`}{Integer row number — a stable event identifier for downstream joins.}
#'   \item{`.tid`}{Integer trip identifier via `dplyr::consecutive_id()` on all
#'     trip-defining columns.}
#' }
#'
#' Event-level datetimes are derived from `LE_CDAT`, `LE_STIME`, and `LE_ETIME`
#' (the latter two are character `"HH:MM"` in the raw file):
#' \describe{
#'   \item{`t1`}{Event start (POSIXct, UTC).}
#'   \item{`t2`}{Event end (POSIXct, UTC).}
#'   \item{`.tsrc`}{How `t1`/`t2` were derived — `"data"`, `"next day"`,
#'     `"dummy"`, or `NA`. See Details.}
#' }
#'
#' **Note:** This function is R-only. `paste()`, `lubridate::dmy_hms()`,
#' `lubridate::dmy()`, `lubridate::ymd_hm()`, `row_number()`, and
#' `consecutive_id()` are not compatible with lazy/DuckDB backends.
#'
#' @param eflalo A data frame in EFLALO format. Must contain `VE_KW`, `VE_LEN`,
#'   `VE_TON`, `LE_MSZ`, `LE_CDAT`, `FT_DDAT`, `FT_DTIME`, `FT_LDAT`, and
#'   `FT_LTIME`. `LE_STIME` and `LE_ETIME` (`"HH:MM"` character) are used if
#'   present.
#' @param remove Logical. If `TRUE` (default), the raw date/time columns
#'   `FT_DDAT`, `FT_DTIME`, `FT_LDAT`, and `FT_LTIME` are dropped once
#'   `FT_DDATIM` / `FT_LDATIM` have been constructed. `LE_CDAT` is kept but
#'   coerced from character to Date. Set to `FALSE` to retain the originals.
#'
#' @return The input `eflalo` as a tibble with:
#'   \describe{
#'     \item{`.eid`}{Integer row identifier (positioned before `LE_ID`).}
#'     \item{`.tid`}{Integer trip identifier (positioned before `VE_REF`).}
#'     \item{`FT_DDATIM`}{POSIXct departure datetime (UTC).}
#'     \item{`FT_LDATIM`}{POSIXct landing datetime (UTC).}
#'     \item{`LE_CDAT`}{Date, re-parsed from `"DD/MM/YYYY"` character.}
#'     \item{`t1`}{POSIXct event start (UTC).}
#'     \item{`t2`}{POSIXct event end (UTC).}
#'     \item{`.tsrc`}{Character. Derivation source for `t1`/`t2`:
#'       `"data"` (both times present, same day),
#'       `"next day"` (start > end, so `t2` rolls to next day),
#'       `"dummy"` (`LE_CDAT` present but one/both times `NA`; `t1 = 00:01`, `t2 = 23:59`),
#'       or `NA` (`LE_CDAT` itself is `NA`).}
#'   }
#'   Numeric columns (`VE_KW`, `VE_LEN`, `VE_TON`, `LE_MSZ`, all `KG`/`EURO`
#'   columns) are coerced to numeric. If `remove = TRUE`, the raw date/time
#'   columns are absent.
#'
#' @examples
#' \dontrun{
#' eflalo <- fd_clean_eflalo(eflalo)
#' eflalo <- fd_clean_eflalo(eflalo, remove = FALSE) # keep the raw columns
#' }
#'
#' @export
fd_clean_eflalo <- function(eflalo, remove = TRUE) {

  required_cols <- c(
    "VE_KW", "VE_LEN", "VE_TON", "LE_MSZ", "LE_CDAT",
    "FT_DDAT", "FT_DTIME", "FT_LDAT", "FT_LTIME"
  )
  missing <- required_cols[!required_cols %in% names(eflalo)]
  if (length(missing) > 0)
    stop("Column(s) missing in eflalo: ", paste(missing, collapse = ", "))

  numeric_cols <- c(
    "VE_KW", "VE_LEN", "VE_TON", "LE_MSZ",
    grep("KG|EURO", names(eflalo), value = TRUE)
  )

  # NOTE: paste(), lubridate::dmy_hms(), lubridate::dmy(), row_number(), and
  # consecutive_id() are R-only; not duckdb-compatible
  eflalo <- eflalo |>
    dplyr::mutate(
      dplyr::across(dplyr::all_of(numeric_cols), as.numeric),
      FT_DDATIM = lubridate::dmy_hms(paste(FT_DDAT, FT_DTIME), tz = "UTC"),
      FT_LDATIM = lubridate::dmy_hms(paste(FT_LDAT, FT_LTIME), tz = "UTC"),
      LE_CDAT   = lubridate::dmy(LE_CDAT)
    ) |>
    dplyr::arrange(VE_COU, VE_REF, FT_DDATIM, FT_LDATIM, LE_CDAT) |>
    dplyr::mutate(.eid = dplyr::row_number(),
                  .before = LE_ID) |>
    dplyr::mutate(
      # NOTE: consecutive_id() is not duckdb-compatible
      .tid = dplyr::consecutive_id(VE_REF, VE_FLT, VE_COU, VE_LEN, VE_KW, VE_TON, FT_REF,
                                   FT_DCOU, FT_DHAR, FT_DDATIM,
                                   FT_LCOU, FT_LHAR, FT_LDATIM),
      .before = VE_REF
    )

  if (remove) eflalo <- dplyr::select(eflalo, -c(FT_DDAT, FT_DTIME, FT_LDAT, FT_LTIME))

  # Derive event datetimes from LE_CDAT + LE_STIME/LE_ETIME.
  # Build intermediate date-time strings first so lubridate never receives
  # partial NAs — case_when selects the correct string per row.
  # NOTE: paste() and lubridate::ymd_hm() are R-only; not duckdb-compatible
  if (all(c("LE_STIME", "LE_ETIME") %in% names(eflalo))) {
    eflalo <- eflalo |>
      dplyr::mutate(
        .tsrc = dplyr::case_when(
          is.na(LE_CDAT)                         ~ NA_character_,
          is.na(LE_STIME) | is.na(LE_ETIME)      ~ "dummy",
          LE_STIME <= LE_ETIME                    ~ "data",
          LE_STIME > LE_ETIME                     ~ "next day"
        ),
        .t1_str = dplyr::case_when(
          is.na(LE_CDAT)                         ~ NA_character_,
          is.na(LE_STIME) | is.na(LE_ETIME)      ~ paste(LE_CDAT, "00:01"),
          .default                               = paste(LE_CDAT, LE_STIME)
        ),
        .t2_str = dplyr::case_when(
          is.na(LE_CDAT)                         ~ NA_character_,
          is.na(LE_STIME) | is.na(LE_ETIME)      ~ paste(LE_CDAT, "23:59"),
          LE_STIME <= LE_ETIME                    ~ paste(LE_CDAT, LE_ETIME),
          LE_STIME > LE_ETIME                     ~ paste(LE_CDAT + 1L, LE_ETIME)
        ),
        t1 = lubridate::ymd_hm(.t1_str, tz = "UTC", quiet = TRUE),
        t2 = lubridate::ymd_hm(.t2_str, tz = "UTC", quiet = TRUE)
      ) |>
      dplyr::select(-.t1_str, -.t2_str)
  }

  return(eflalo)
}
