#' Extract Distinct Fishing Trips from EFLALO Data
#'
#' Extract trip level structure from the EFLALO.
#'
#' @param eflalo A data frame containing EFLALO data. Must include columns with
#'   prefixes `VE_` (vessel variables) and `FT_` (fishing trip variables), and
#'   the `.tid` column added by `fd_clean_eflalo()`.
#'
#' @return A data frame containing distinct combinations of vessel and trip variables:
#'   \describe{
#'     \item{.tid}{Internal trip identifier (from `fd_clean_eflalo()`)}
#'     \item{VE_REF}{Vessel reference identifier}
#'     \item{VE_FLT}{Vessel fleet segment}
#'     \item{VE_COU}{Vessel country}
#'     \item{VE_LEN}{Vessel length}
#'     \item{VE_KW}{Vessel power (kW)}
#'     \item{VE_TON}{Vessel tonnage}
#'     \item{FT_REF}{Fishing trip reference}
#'     \item{FT_DCOU}{Fishing trip departure country}
#'     \item{FT_DHAR}{Fishing trip departure harbour}
#'     \item{FT_DDATIM}{Fishing trip departure date/time}
#'     \item{FT_LCOU}{Fishing trip landing country}
#'     \item{FT_LHAR}{Fishing trip landing harbour}
#'     \item{FT_LDATIM}{Fishing trip landing date/time}
#'   }
#'
#' @details
#' This function deduplicates rows to extract the unique trip-level structure
#' from raw EFLALO data. Each row in the output represents a distinct combination
#' of vessel and trip attributes.
#'
#' @seealso
#'   \code{\link{fd_events}} for isolating event-level variables,
#'   \code{\link{fd_flag_trips}} for validating trip temporal sequences.
#'
#' @examples
#' \dontrun{
#'   trips <- fd_trips(eflalo)
#' }
#'
#' @export
fd_trips <- function(eflalo) {
  eflalo |>
    dplyr::select(.tid, VE_REF, VE_FLT, VE_COU, VE_LEN, VE_KW, VE_TON,
                  FT_REF, FT_DCOU, FT_DHAR, FT_DDATIM, FT_LCOU, FT_LHAR, FT_LDATIM) |>
    dplyr::distinct()
}


#' Isolate Fishing Events from EFLALO Data
#'
#' Selects fishing event variables from an EFLALO dataset. Raises an error if
#' the row count decreases after deduplication, which indicates non-distinct
#' events. For trip-level data, see \code{\link{fd_trips}}.
#'
#' @param eflalo A data frame containing EFLALO data. Must include columns with
#'   prefixes `VE_` (vessel), `FT_` (fishing trip), and `LE_` (fishing event),
#'   plus the `.eid` and `.tid` columns added by `fd_clean_eflalo()`.
#'
#' @return A data frame containing fishing events with `.eid`, all `LE_*`
#'   columns, and `.tid`. Each row should represent a distinct event; an error
#'   is raised if duplicates are detected.
#'
#' @details
#' All `LE_*` columns are retained, including `LE_KG_*` and `LE_EURO_*` species
#' catch columns. If you need species catch in long format, use
#' \code{\link{fd_tidy_eflalo}} instead.
#'
#' @seealso
#'   \code{\link{fd_trips}} for extracting trip-level data,
#'   \code{\link{fd_tidy_eflalo}} for extracting both trips and events in one call.
#'
#' @examples
#' \dontrun{
#'   events <- fd_events(eflalo)
#' }
#'
#' @export
fd_events <- function(eflalo) {

  rows <- nrow(eflalo)
  events <- eflalo |>
    dplyr::select(.eid, dplyr::starts_with("LE_"), .tid) |>
    dplyr::distinct()

  if (rows > nrow(events)) {
    stop(
      "Events are not distinct after deduplication. ",
      "Run fd_flag_eflalo() and filter duplicates before calling fd_events()."
    )
  }

  return(events)
}


#' Tidy and Structure EFLALO Data into Trips and Events
#'
#' Extracts and organizes EFLALO data into two complementary tables: fishing
#' trips and fishing events. This is a convenience wrapper around
#' \code{\link{fd_trips}} and \code{\link{fd_events}} that returns both
#' structured datasets in a single call.
#'
#' @param eflalo A data frame containing EFLALO data with vessel, trip, and
#'   event columns. Must include columns with prefixes `VE_` (vessel),
#'   `FT_` (fishing trip), and `LE_` (fishing event), plus `.eid` and `.tid`
#'   added by `fd_clean_eflalo()`.
#'
#' @return A list with two elements:
#'   \describe{
#'     \item{trips}{A data frame of distinct fishing trips (see \code{\link{fd_trips}}).}
#'     \item{events}{A data frame of distinct fishing events (see \code{\link{fd_events}}).
#'       An error is raised if events are not distinct.}
#'   }
#'
#' @seealso
#'   \code{\link{fd_trips}}, \code{\link{fd_events}},
#'   \code{\link{fd_flag_trips}}, \code{\link{fd_flag_events}}
#'
#' @examples
#' \dontrun{
#'   eflalo_tidy <- fd_tidy_eflalo(eflalo)
#'   trips  <- eflalo_tidy$trips
#'   events <- eflalo_tidy$events
#' }
#'
#' @export
fd_tidy_eflalo <- function(eflalo) {
  list(
    trips  = fd_trips(eflalo),
    events = fd_events(eflalo)
  )
}
