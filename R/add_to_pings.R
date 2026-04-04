
#' Add Trip Information to Vessel Tracking Data
#'
#' Joins vessel tracking positions (VMS/AIS) with trip-level information from
#' the logbook based on vessel identity and time overlap. Each position record
#' is matched to the trip active at that timestamp; positions outside any trip
#' window receive `NA` for the trip columns.
#'
#' @param ais A data frame of vessel tracking positions as returned by
#'   `fd_clean_tacsat()`. Must contain `cid`, `vid`, and `time` (POSIXct).
#' @param trips A data frame of fishing trips as returned by `fd_trips()`.
#'   Must contain `cid`, `vid`, `tid`, `T1`, and `T2`.
#' @param cn Character vector of additional column names from `trips` to carry
#'   across to `ais`. `tid` and `.tid` is always included. `cid` and `vid` are implicit
#'   join keys; `T1` and `T2` are used for the time-overlap join and removed
#'   when `remove = TRUE`. Default: `"tid"`.
#' @param remove Logical. If `TRUE` (default), removes `T1` and `T2` from the
#'   output after the join.
#'
#' @return `ais` with `tid` (and any additional `cn` columns) appended.
#'   Positions that fall outside any trip window have `NA` for those columns.
#'
#' @details
#' A many-to-one left join: each position is matched to at most one trip based
#' on vessel (`cid`, `vid`) and timestamp (`time` between `T1` and `T2`). Only
#' the columns in `cn` (plus the join keys and `T1`/`T2`) are taken from
#' `trips`, so extra trip columns do not bleed into the output.
#'
#' @seealso [fd_trips()] to extract the trip table from a cleaned eflalo data
#'   frame, [fd_clean_tacsat()] for the expected input format of `ais`.
#'
#' @examples
#' \dontrun{
#' ais   <- fd_clean_tacsat(tacsat_raw)
#' trips <- fd_clean_eflalo(eflalo_raw) |> fd_trips()
#' ais   <- fd_add_trips(ais, trips)
#'
#' # Carry additional vessel metadata across
#' ais <- fd_add_trips(ais, trips, cn = c("tid", "length", "kw", "gt"))
#' }
#'
#' @export
fd_add_trips <- function(ais, trips, cn = c("tid", ".tid"), remove = TRUE) {

  # tid and .tid ar always required; add it if the user forgot
  cn <- unique(c("tid", ".tid", cn))

  # Validate: required columns in ais
  required_ais <- c("cid", "vid", "time")
  missing_ais  <- required_ais[!required_ais %in% names(ais)]
  if (length(missing_ais) > 0)
    stop("Required column(s) missing from `ais`: ",
         paste(missing_ais, collapse = ", "), call. = FALSE)

  # Validate: required columns in trips
  required_trips <- c("cid", "vid", "T1", "T2", cn)
  missing_trips  <- required_trips[!required_trips %in% names(trips)]
  if (length(missing_trips) > 0)
    stop("Column(s) not found in `trips`: ",
         paste(missing_trips, collapse = ", "), call. = FALSE)

  rows <- nrow(ais)

  trip_data <- trips |>
    dplyr::select(cid, vid, dplyr::all_of(cn), T1, T2) |>
    dplyr::distinct()

  ais <- ais |>
    dplyr::left_join(trip_data,
                     by = dplyr::join_by(cid, vid, dplyr::between(time, T1, T2)))

  if (remove) ais <- ais |> dplyr::select(-c(T1, T2))

  if (rows != nrow(ais))
    stop("Row count changed after join: a ping matched more than one trip. ",
         "Run fd_flag_trips() on your trips table and filter overlapping trips ",
         "before calling fd_add_trips().", call. = FALSE)

  return(ais)
}

#' Title
#'
#' @param ais xxx
#' @param events xxx
#'
#' @returns xxx
#' @export
#'
fd_add_events <- function(ais, events) {
  ais |>
    dplyr::left_join(events,
                     by = dplyr::join_by(.tid,
                                         dplyr::between(time, t1, t2)),
                     relationship = "many-to-one")
}
