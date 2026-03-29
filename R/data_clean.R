# TASK 2.1 Clean TACSAT data (1.2) - see documentations/TASKS.md


#' Validate, coerce and prepare TACSAT data
#'
#' @description
#' One call to rule them all (for TACSAT, at least). Does the following in order:
#'
#' 1. Checks that all required columns are present.
#' 2. Coerces `SI_LATI`, `SI_LONG`, `SI_SP`, and `SI_HE` to numeric.
#' 3. Parses `SI_DATE` + `SI_TIME` into a single `SI_DATIM` POSIXct column and
#'    drops the originals — because two columns are strictly worse than one.
#' 4. Sorts by `VE_REF` then `SI_DATIM` — the order that interval calculations
#'    downstream depend on.
#'
#' After this call, `SI_DATE` and `SI_TIME` are gone; `SI_LONG` and `SI_LATI`
#' remain as plain numeric columns. Convert to `sf` later in the pipeline when
#' you actually need spatial operations.
#'
#' @param tacsat A data frame in TACSAT format. Must contain `VE_COU`, `VE_REF`,
#'   `SI_DATE`, `SI_TIME`, `SI_LATI`, `SI_LONG`, `SI_SP`, and `SI_HE`.
#' @param remove Logical. If `TRUE` (default), the raw date/time columns
#'   `SI_DATE` and `SI_TIME` are dropped once the
#'   combined `SI_DATIM` columns have been constructed. Life is
#'   too short to keep hauling around redundant columns that have already done
#'   their one job. Set to `FALSE` if you enjoy clutter.
#'
#' @return A data frame sorted by `VE_REF` and `SI_DATIM`, with `SI_DATIM`
#'   (POSIXct, UTC) added and the raw `SI_DATE` / `SI_TIME` columns removed by
#'   default.
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

  tacsat |>
    dplyr::mutate(
      dplyr::across(dplyr::all_of(c("SI_LATI", "SI_LONG", "SI_SP", "SI_HE")), as.numeric),
      SI_DATIM = lubridate::dmy_hms(paste(SI_DATE, SI_TIME), tz = "UTC"),
      .before = SI_DATE
    ) |>
    dplyr::select(-c(SI_DATE, SI_TIME)) |>
    dplyr::arrange(VE_REF, SI_DATIM)
}

# TASK 2.2 Clean EFLALO data (1.3) - see documentations/TASKS.md

#' Validate and coerce EFLALO columns
#'
#' @description
#' Checks that the required vessel, trip, and catch columns are present in an
#' EFLALO data frame, then gets the types right so nothing downstream has to
#' guess: numeric columns are coerced to numeric; `FT_DDATIM` and `FT_LDATIM`
#' are constructed from the raw date/time string columns; and `LE_CDAT` is
#' parsed from `"DD/MM/YYYY"` to Date. Call this before [fd_eflalo_checks()].
#'
#' Value-level sanity checks (missing vessel lengths, implausible engine power,
#' etc.) live in [fd_eflalo_checks()] — this function only concerns itself with
#' structure and type.
#'
#' @param eflalo A data frame in EFLALO format.
#' @param remove Logical. If `TRUE` (default), the raw date/time columns
#'   `FT_DDAT`, `FT_DTIME`, `FT_LDAT`, and `FT_LTIME` are dropped once the
#'   combined `FT_DDATIM` / `FT_LDATIM` columns have been constructed. Life is
#'   too short to keep hauling around redundant columns that have already done
#'   their one job. Set to `FALSE` if you enjoy clutter.
#'
#' @return The input `eflalo` as a tibble with numeric columns coerced and
#'   `FT_DDATIM` / `FT_LDATIM` added. If `remove = TRUE`, the now-redundant
#'   raw date/time columns are absent from the result.
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
    "VE_KW", "VE_LEN", "VE_TON", "LE_MSZ",
    "FT_DDAT", "FT_DTIME", "FT_LDAT", "FT_LTIME"
  )
  missing <- required_cols[!required_cols %in% names(eflalo)]
  if (length(missing) > 0)
    stop("Column(s) missing in eflalo: ", paste(missing, collapse = ", "))

  numeric_cols <- c(
    "VE_KW", "VE_LEN", "VE_TON", "LE_MSZ",
    grep("KG|EURO", names(eflalo), value = TRUE)
  )

  eflalo <- eflalo |>
    dplyr::mutate(dplyr::across(dplyr::all_of(numeric_cols), as.numeric))

  if ("LE_CDAT" %in% names(eflalo))
    eflalo <- dplyr::mutate(eflalo, LE_CDAT = lubridate::dmy(LE_CDAT))

  if (!"FT_DDATIM" %in% names(eflalo))
    eflalo <- eflalo |>
      dplyr::mutate(FT_DDATIM = lubridate::dmy_hm(paste(FT_DDAT, FT_DTIME), tz = "UTC"),
                    .before = FT_DDAT)

  if (!"FT_LDATIM" %in% names(eflalo))
    eflalo <- eflalo |>
      dplyr::mutate(FT_LDATIM = lubridate::dmy_hm(paste(FT_LDAT, FT_LTIME),  tz = "UTC"),
                    .before = FT_LDAT)

  if (remove)
    eflalo <- dplyr::select(eflalo, -c(FT_DDAT, FT_DTIME, FT_LDAT, FT_LTIME))

  return(eflalo)
}

