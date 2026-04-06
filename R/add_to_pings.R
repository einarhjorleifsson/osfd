
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

#' Add Fishing Event Information to Vessel Tracking Data
#'
#' @description
#' Joins vessel tracking positions (VMS/AIS) with fishing event information from
#' the logbook based on the internal trip identifier (`.tid`) and a timestamp
#' overlap (`time` between `t1` and `t2`). All event columns are carried across;
#' pings that fall outside any event window receive `NA` for those columns.
#'
#' This function is intended to be called after \code{\link{fd_add_trips}}, which
#' adds `.tid` to the `ais` data frame.
#'
#' @param ais A data frame of vessel tracking positions after
#'   \code{\link{fd_add_trips}} has been applied. Must contain `.tid` and
#'   `time` (POSIXct).
#' @param events A data frame of fishing events as returned by
#'   \code{\link{fd_events}} (and typically filtered by
#'   \code{\link{fd_flag_events}}). Must contain `.tid`, `t1` (POSIXct), and
#'   `t2` (POSIXct).
#'
#' @return `ais` with all columns from `events` appended. Pings outside any
#'   event window have `NA` for event columns.
#'
#' @details
#' The join is keyed on `.tid` (internal trip identifier) and
#' `dplyr::between(time, t1, t2)`. The intended relationship is many-to-one:
#' each ping should fall within at most one event window per trip. If any ping
#' matches more than one event — because event windows overlap or share identical
#' dummy times (`t1 = 00:01`, `t2 = 23:59`) — the row count of `ais` increases
#' and the function stops with an informative error.
#'
#' Use \code{\link{fd_check_events_join}} to diagnose which pings and windows
#' are responsible before re-running.
#'
#' Note that `t1` and `t2` in the events table are derived by
#' \code{\link{fd_clean_eflalo}}: when real start/end times (`LE_STIME`/
#' `LE_ETIME`) are absent, both are set to synthetic placeholder values
#' (`00:01` and `23:59` on the catch date, `.tsrc = "dummy"`). These dummy
#' windows span the full day and will match every ping recorded on that date for
#' the trip — a valid approximation when events are unique per day, but a source
#' of many-to-many conflicts when multiple events share the same date.
#'
#' @seealso
#'   \code{\link{fd_add_trips}} for the preceding join step,
#'   \code{\link{fd_check_events_join}} for diagnosing join conflicts,
#'   \code{\link{fd_events}} and \code{\link{fd_flag_events}} for preparing the
#'   events input.
#'
#' @examples
#' \dontrun{
#' ais2 <- ais |>
#'   fd_add_trips(trips, cn = c("tid", "length", "kw", "gt", ".tid")) |>
#'   fd_add_events(events)
#'
#' # If fd_add_events() errors, diagnose with:
#' conflicts <- fd_check_events_join(ais2_pre, events)
#' conflicts |> dplyr::count(.tid, t1, t2, sort = TRUE)
#' }
#'
#' @export
fd_add_events <- function(ais, events) {
  rows <- nrow(ais)

  ais <- ais |>
    dplyr::left_join(events,
                     by = dplyr::join_by(.tid,
                                         dplyr::between(time, t1, t2)))

  if (nrow(ais) != rows)
    stop(
      "Row count increased after join: ",
      nrow(ais) - rows, " extra row(s) — one or more pings matched multiple events.\n",
      "Use fd_check_events_join() to identify the conflicting windows.",
      call. = FALSE
    )

  ais
}


#' Diagnose many-to-many conflicts before joining events to pings
#'
#' @description
#' Performs the same join as \code{\link{fd_add_events}} but **without** a
#' relationship constraint, then returns the subset of rows where a single ping
#' matched more than one event. Use this before calling `fd_add_events()` to
#' understand why it errors.
#'
#' The function is intentionally free-standing and makes no assumptions about
#' *why* the conflict arises — it simply surfaces whatever causes the bloat
#' (overlapping real times, identical dummy windows, soft duplicates, etc.).
#'
#' @param ais A data frame of vessel tracking positions after
#'   \code{\link{fd_add_trips}} has been applied. Must contain `.pid`, `.tid`,
#'   and `time`.
#' @param events A data frame of fishing events as returned by
#'   \code{\link{fd_events}} (and optionally \code{\link{fd_flag_events}}).
#'   Must contain `.tid`, `t1`, and `t2`.
#'
#' @return A tibble of the bloated join rows — i.e. only the pings that matched
#'   more than one event, with all event columns attached. Each such ping appears
#'   once per matched event. Returns an empty tibble (invisibly) with a message
#'   when no conflicts exist.
#'
#' @examples
#' \dontrun{
#' ais2 <- fd_add_trips(ais, trips, cn = c("tid", "length", "kw", "gt", ".tid"))
#'
#' conflicts <- fd_check_events_join(ais2, events)
#' conflicts |> dplyr::count(.tid, t1, t2, sort = TRUE)
#' conflicts |> dplyr::distinct(.tid, t1, t2, .eid)
#' }
#'
#' @seealso \code{\link{fd_add_events}}, \code{\link{fd_flag_events}}
#' @export
fd_check_events_join <- function(ais, events) {
  joined <- ais |>
    dplyr::left_join(
      events,
      by = dplyr::join_by(.tid, dplyr::between(time, t1, t2))
    )

  conflicts <- joined |>
    dplyr::group_by(.pid) |>
    dplyr::filter(dplyr::n() > 1) |>
    dplyr::ungroup()

  n_pings <- dplyr::n_distinct(conflicts$.pid)

  if (n_pings == 0) {
    message("No conflicts: every ping matches at most one event.")
    return(invisible(conflicts))
  }

  message(
    n_pings, " ping(s) matched more than one event across ",
    dplyr::n_distinct(conflicts$.tid), " trip(s). ",
    "fd_add_events() would fail.\n",
    "Inspect the returned tibble to understand the overlapping windows."
  )

  conflicts
}
