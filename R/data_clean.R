# -- Input validation ----------------------------------------------------------

#' Validate a TACSAT or EFLALO data frame against the field definitions
#'
#' @description
#' Checks a raw TACSAT or EFLALO data frame against the `dictionary`
#' dictionary before cleaning. Three things are checked:
#'
#' 1. **Required fields** -- stops with an informative error if any are absent.
#' 2. **Optional fields** -- emits a message listing any that are absent
#'    (processing continues).
#' 3. **Coercion safety** -- warns if converting a field to its target R type
#'    (numeric or Date) would silently introduce new `NA` values, indicating
#'    malformed values in the raw data.
#'
#' The function returns `data` invisibly, so it can be used in a pipe directly
#' upstream of `fd_clean_tacsat()` / `fd_clean_eflalo()`, or called standalone
#' as a preflight check.
#'
#' Species-level catch columns (`LE_KG_<SP>`, `LE_EURO_<SP>`) are not checked.
#'
#' @param data A data frame in TACSAT or EFLALO format (raw, before cleaning).
#' @param which Character. Which format to validate against: `"tacsat"` or
#'   `"eflalo"`.
#' @param dictionary xxx
#'
#' @return `data`, invisibly.
#'
#' @seealso [fd_dictionary] for the underlying dictionary,
#'   [fd_clean_tacsat()] and [fd_clean_eflalo()] which call this internally.
#'
#' @examples
#' \dontrun{
#' # Standalone preflight check
#' fd_check_input(tacsat_raw, "tacsat")
#'
#' # In a pipe (check then clean in one step)
#' tacsat <- tacsat_raw |>
#'   fd_check_input("tacsat") |>
#'   fd_clean_tacsat()
#' }
#'
#' @export
fd_check_input <- function(data, which = c("tacsat", "eflalo"), dictionary = fd_dictionary) {
  which <- match.arg(which)

  # Non-derived, non-pattern rows for this table
  defs <- dictionary |>
    dplyr::filter(table == which, !derived, !grepl("<", old))

  # 1. Required fields -> hard stop
  req     <- defs |> dplyr::filter(required) |> dplyr::pull(old)
  missing <- req[!req %in% names(data)]
  if (length(missing) > 0)
    stop("Required column(s) missing in ", which, ": ",
         paste(missing, collapse = ", "), call. = FALSE)

  # 2. Optional fields -> message only
  opt         <- defs |> dplyr::filter(!required) |> dplyr::pull(old)
  missing_opt <- opt[!opt %in% names(data)]
  if (length(missing_opt) > 0)
    message("Optional column(s) absent from ", which, " (will be skipped): ",
            paste(missing_opt, collapse = ", "))

  # 3. Coercion safety checks for fields present in data
  present <- defs |> dplyr::filter(old %in% names(data))

  # dbl: warn if as.numeric() would introduce new NAs
  dbl_fields <- present |> dplyr::filter(type == "dbl") |> dplyr::pull(old)
  for (f in dbl_fields) {
    x <- data[[f]]
    if (!is.numeric(x)) {
      n_new <- sum(is.na(suppressWarnings(as.numeric(x)))) - sum(is.na(x))
      if (n_new > 0)
        warning("`", f, "`: coercing to numeric will introduce ", n_new,
                " new NA(s) -- check for non-numeric values", call. = FALSE)
    }
  }

  # date: warn if lubridate::dmy() would introduce new NAs
  date_fields <- present |> dplyr::filter(type == "date") |> dplyr::pull(old)
  for (f in date_fields) {
    x <- data[[f]]
    if (!inherits(x, "Date")) {
      n_new <- sum(is.na(lubridate::dmy(x, quiet = TRUE))) - sum(is.na(x))
      if (n_new > 0)
        warning("`", f, "`: parsing as Date (DD/MM/YYYY) will introduce ", n_new,
                " new NA(s) -- check for malformed dates", call. = FALSE)
    }
  }

  invisible(data)
}


# -- Setup functions -----------------------------------------------------------

#' Validate, coerce and prepare TACSAT data
#'
#' @description
#' One call to rule them all (for TACSAT, at least). Does the following in order:
#'
#' 1. Validates required columns and checks for coercion problems via
#'    `fd_check_input()`.
#' 2. Coerces `SI_LATI`, `SI_LONG`, `SI_SP`, and `SI_HE` to numeric.
#' 3. Parses `SI_DATE` + `SI_TIME` into a single `SI_DATIM` POSIXct column and
#'    drops the originals -- because two columns are strictly worse than one.
#' 4. Sorts by `VE_REF` then `SI_DATIM` -- the order that interval calculations
#'    downstream depend on.
#' 5. Adds `.pid` (integer row identifier).
#' 6. Translates column names to short lowercase equivalents via
#'    `fd_translate()` -- see the return section for the mapping.
#'
#' After this call, `SI_DATE` and `SI_TIME` are gone (unless `remove = FALSE`).
#'
#' **Note:** This function is R-only. `paste()`, `lubridate::dmy_hms()`, and
#' `dplyr::row_number()` are not compatible with lazy/DuckDB backends.
#'
#' @param tacsat A data frame in TACSAT format. See `fd_check_input()` /
#'   `fd_dictionary` for the full list of required and optional fields.
#' @param remove Logical. If `TRUE` (default), the raw date/time columns
#'   `SI_DATE` and `SI_TIME` are dropped once `SI_DATIM` has been constructed.
#'   Set to `FALSE` to retain the originals.
#'
#' @return A data frame sorted by vessel and datetime, with column names
#'   translated to short lowercase:
#'   \describe{
#'     \item{`.pid`}{Integer row identifier.}
#'     \item{`cid`}{Vessel flag country (`VE_COU`).}
#'     \item{`vid`}{Vessel identifier (`VE_REF`).}
#'     \item{`lat`}{Latitude (`SI_LATI`).}
#'     \item{`lon`}{Longitude (`SI_LONG`).}
#'     \item{`time`}{POSIXct timestamp (UTC), parsed from `SI_DATE` + `SI_TIME` (`SI_DATIM`).}
#'     \item{`speed`}{Instantaneous speed in knots (`SI_SP`).}
#'     \item{`heading`}{Instantaneous heading in degrees (`SI_HE`).}
#'   }
#'   `SI_DATE` and `SI_TIME` are removed by default.
#'
#' @seealso [fd_check_input()] for the preflight validation step.
#'
#' @examples
#' \dontrun{
#' tacsat <- fd_clean_tacsat(tacsat)
#' }
#'
#' @export
fd_clean_tacsat <- function(tacsat, remove = TRUE) {

  fd_check_input(tacsat, "tacsat")

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

  tacsat <- fd_translate(tacsat, fd_dictionary |> dplyr::filter(table == "tacsat"))
  return(tacsat)
}


#' Validate and coerce EFLALO columns
#'
#' @description
#' Checks that the required vessel, trip, and event columns are present in an
#' EFLALO data frame (via `fd_check_input()`), then gets the types right so
#' nothing downstream has to guess: numeric columns are coerced to numeric;
#' `FT_DDATIM` and `FT_LDATIM` are constructed from the raw date/time string
#' columns; and `LE_CDAT` is re-parsed from its character form (`"DD/MM/YYYY"`)
#' to an R Date.
#'
#' Two internal key columns are also added:
#' \describe{
#'   \item{`.eid`}{Integer row number -- a stable event identifier for downstream joins.}
#'   \item{`.tid`}{Integer trip identifier via `dplyr::consecutive_id()` on all
#'     trip-defining columns.}
#' }
#'
#' Event-level datetimes are derived from `LE_CDAT`, `LE_STIME`, and `LE_ETIME`
#' (the latter two are character `"HH:MM"` in the raw file) if both are present:
#' \describe{
#'   \item{`t1`}{Event start (POSIXct, UTC).}
#'   \item{`t2`}{Event end (POSIXct, UTC).}
#'   \item{`.tsrc`}{How `t1`/`t2` were derived -- `"data"`, `"next day"`,
#'     `"dummy"`, or `NA`.}
#' }
#'
#' **Note:** This function is R-only. `paste()`, `lubridate::dmy_hms()`,
#' `lubridate::dmy()`, `lubridate::ymd_hm()`, `row_number()`, and
#' `consecutive_id()` are not compatible with lazy/DuckDB backends.
#'
#' @param eflalo A data frame in EFLALO format. See `fd_check_input()` /
#'   `dictionary` for the full list of required and optional fields.
#' @param remove Logical. If `TRUE` (default), the raw date/time columns
#'   `FT_DDAT`, `FT_DTIME`, `FT_LDAT`, and `FT_LTIME` are dropped once
#'   `FT_DDATIM` / `FT_LDATIM` have been constructed. `LE_CDAT` is kept but
#'   coerced from character to Date. Set to `FALSE` to retain the originals.
#'
#' @return The input `eflalo` as a tibble with column names translated to short
#'   lowercase via `fd_translate()`. Key columns:
#'   \describe{
#'     \item{`.tid`}{Integer trip identifier (positioned before `vid`).}
#'     \item{`vid`}{Vessel identifier (`VE_REF`).}
#'     \item{`cid`}{Vessel flag country (`VE_COU`).}
#'     \item{`length`}{Vessel length (`VE_LEN`).}
#'     \item{`kw`}{Engine power (`VE_KW`).}
#'     \item{`gt`}{Vessel tonnage (`VE_TON`).}
#'     \item{`tid`}{Fishing trip reference (`FT_REF`).}
#'     \item{`T1`}{POSIXct departure datetime (UTC) (`FT_DDATIM`).}
#'     \item{`T2`}{POSIXct landing datetime (UTC) (`FT_LDATIM`).}
#'     \item{`.eid`}{Integer row identifier (positioned before `lid`).}
#'     \item{`lid`}{Log event identifier (`LE_ID`).}
#'     \item{`date`}{Catch date, re-parsed from `"DD/MM/YYYY"` (`LE_CDAT`).}
#'     \item{`gear`}{Gear code (`LE_GEAR`).}
#'     \item{`mesh`}{Mesh size (`LE_MSZ`).}
#'     \item{`ir`}{ICES statistical rectangle (`LE_RECT`).}
#'     \item{`t1`}{POSIXct event start (UTC), if `LE_STIME`/`LE_ETIME` present.}
#'     \item{`t2`}{POSIXct event end (UTC), if `LE_STIME`/`LE_ETIME` present.}
#'     \item{`.tsrc`}{Derivation source for `t1`/`t2`, if `LE_STIME`/`LE_ETIME` present.}
#'   }
#'   Numeric columns (`VE_KW`, `VE_LEN`, `VE_TON`, `LE_MSZ`, all `KG`/`EURO`
#'   columns) are coerced to numeric. If `remove = TRUE`, the raw date/time
#'   columns (`FT_DDAT`, `FT_DTIME`, `FT_LDAT`, `FT_LTIME`, `LE_STIME`,
#'   `LE_ETIME`) are absent from the output.
#'
#' @seealso [fd_check_input()] for the preflight validation step.
#'
#' @examples
#' \dontrun{
#' eflalo <- fd_clean_eflalo(eflalo)
#' eflalo <- fd_clean_eflalo(eflalo, remove = FALSE) # keep the raw columns
#' }
#'
#' @export
fd_clean_eflalo <- function(eflalo, remove = TRUE) {

  fd_check_input(eflalo, "eflalo")

  numeric_cols <- c(
    "VE_KW", "VE_LEN", "VE_TON", "LE_MSZ",
    grep("KG|EURO", names(eflalo), value = TRUE)
  )

  # NOTE: paste(), lubridate::dmy_hms(), lubridate::dmy(), row_number(), and
  # consecutive_id() are R-only; not duckdb-compatible
  eflalo <- eflalo |>
    dplyr::mutate(
      dplyr::across(dplyr::all_of(numeric_cols), as.numeric),
      LE_CDAT   = lubridate::dmy(LE_CDAT)
    ) |>
    dplyr::mutate(
      FT_DDATIM = lubridate::dmy_hms(paste(FT_DDAT, FT_DTIME), tz = "UTC"),
      .before = FT_DDAT) |>
    dplyr::mutate(
      FT_LDATIM = lubridate::dmy_hms(paste(FT_LDAT, FT_LTIME), tz = "UTC"),
      .before = FT_LDAT
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
  # partial NAs -- case_when selects the correct string per row.
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
        t2 = lubridate::ymd_hm(.t2_str, tz = "UTC", quiet = TRUE),
        .after = LE_CDAT
      ) |>
      dplyr::select(-.t1_str, -.t2_str)
  }

  if (remove) eflalo <- dplyr::select(eflalo, -c(LE_STIME, LE_ETIME))

  dict_ef <- fd_dictionary |> dplyr::filter(table == "eflalo")
  eflalo <- fd_translate(eflalo, dict_ef)
  return(eflalo)
}


# -- Revert functions ----------------------------------------------------------

#' Revert TACSAT column names to ICES originals
#'
#' @description
#' Translates the short lowercase column names produced by `fd_clean_tacsat()`
#' back to their original ICES ALLCAPS equivalents (e.g. `vid → VE_REF`,
#' `time → SI_DATIM`). Only columns that are actually present in `tacsat` are
#' renamed; any extra columns are left untouched.
#'
#' `SI_DATE` (`"DD/MM/YYYY"`) and `SI_TIME` (`"HH:MM"`) are reconstructed from
#' `SI_DATIM` if that column is present, and placed immediately after it.
#'
#' @param tacsat A data frame as returned by `fd_clean_tacsat()`.
#'
#' @return `tacsat` with ICES ALLCAPS column names where applicable, and
#'   `SI_DATE` / `SI_TIME` restored from `SI_DATIM`.
#'
#' @seealso [fd_clean_tacsat()], [fd_translate()]
#'
#' @examples
#' \dontrun{
#' tacsat_orig <- fd_revert_tacsat(tacsat)
#' }
#'
#' @export
fd_revert_tacsat <- function(tacsat) {
  dict <- fd_dictionary |> dplyr::filter(table == "tacsat")
  out <- fd_translate(tacsat, dict, from = "new", to = "old")

  if ("SI_DATIM" %in% names(out)) {
    out <- out |>
      dplyr::mutate(
        SI_DATE = format(SI_DATIM, "%d/%m/%Y"),
        SI_TIME = format(SI_DATIM, "%H:%M"),
        .after = SI_DATIM
      )
  }

  out
}


#' Revert EFLALO column names to ICES originals
#'
#' @description
#' Translates the short lowercase column names produced by `fd_clean_eflalo()`
#' back to their original ICES ALLCAPS equivalents (e.g. `vid → VE_REF`,
#' `T1 → FT_DDATIM`). Only columns that are actually present in `eflalo` are
#' renamed; any extra columns are left untouched.
#'
#' `FT_DDAT` / `FT_DTIME` and `FT_LDAT` / `FT_LTIME` are reconstructed from
#' `FT_DDATIM` and `FT_LDATIM` respectively, if those columns are present, and
#' placed immediately after their source column.
#'
#' @param eflalo A data frame as returned by `fd_clean_eflalo()`.
#'
#' @return `eflalo` with ICES ALLCAPS column names where applicable, and
#'   `FT_DDAT` / `FT_DTIME` / `FT_LDAT` / `FT_LTIME` restored from the
#'   corresponding datetime columns.
#'
#' @seealso [fd_clean_eflalo()], [fd_translate()]
#'
#' @examples
#' \dontrun{
#' eflalo_orig <- fd_revert_eflalo(eflalo)
#' }
#'
#' @export
fd_revert_eflalo <- function(eflalo) {
  dict <- fd_dictionary |> dplyr::filter(table == "eflalo")
  out <- fd_translate(eflalo, dict, from = "new", to = "old")

  if ("FT_DDATIM" %in% names(out)) {
    out <- out |>
      dplyr::mutate(
        FT_DDAT  = format(FT_DDATIM, "%d/%m/%Y"),
        FT_DTIME = format(FT_DDATIM, "%H:%M"),
        .after = FT_DDATIM
      )
  }

  if ("FT_LDATIM" %in% names(out)) {
    out <- out |>
      dplyr::mutate(
        FT_LDAT  = format(FT_LDATIM, "%d/%m/%Y"),
        FT_LTIME = format(FT_LDATIM, "%H:%M"),
        .after = FT_LDATIM
      )
  }

  out
}
