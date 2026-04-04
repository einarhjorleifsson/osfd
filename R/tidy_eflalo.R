#' Extract Distinct Fishing Trips from EFLALO Data
#'
#' Extract trip level structure from the EFLALO.
#'
#' @param eflalo A data frame as returned by `fd_clean_eflalo()`. Must include
#'   the renamed vessel columns (`vid`, `flt`, `cid`, `length`, `kw`, `gt`),
#'   trip columns (`tid`, `cid1`, `hid1`, `T1`, `cid2`, `hid2`, `T2`), and the
#'   internal `.tid` key added by `fd_clean_eflalo()`.
#'
#' @return A data frame with one row per distinct trip:
#'   \describe{
#'     \item{.tid}{Internal integer trip identifier (from `fd_clean_eflalo()`)}
#'     \item{vid}{Vessel identifier (`VE_REF`)}
#'     \item{flt}{Fleet segment (`VE_FLT`)}
#'     \item{cid}{Vessel flag country (`VE_COU`)}
#'     \item{length}{Vessel overall length, m (`VE_LEN`)}
#'     \item{kw}{Engine power, kW (`VE_KW`)}
#'     \item{gt}{Vessel tonnage (`VE_TON`)}
#'     \item{tid}{Fishing trip reference (`FT_REF`)}
#'     \item{cid1}{Departure country (`FT_DCOU`)}
#'     \item{hid1}{Departure harbour (`FT_DHAR`)}
#'     \item{T1}{Trip departure datetime, POSIXct UTC (`FT_DDATIM`)}
#'     \item{cid2}{Landing country (`FT_LCOU`)}
#'     \item{hid2}{Landing harbour (`FT_LHAR`)}
#'     \item{T2}{Trip landing datetime, POSIXct UTC (`FT_LDATIM`)}
#'   }
#'
#' @details
#' This function deduplicates rows to extract the unique trip-level structure
#' from EFLALO data. Each row in the output represents a distinct combination
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
    dplyr::select(.tid, vid, flt, cid, `length`, kw, gt,
                  tid, cid1, hid1, T1, cid2, hid2, T2) |>
    dplyr::distinct()
}


#' Isolate Fishing Events from EFLALO Data
#'
#' Selects fishing event variables from an EFLALO dataset and raises an error
#' if the row count decreases after deduplication. For trip-level data, see
#' \code{\link{fd_trips}}.
#'
#' @param eflalo A data frame as returned by `fd_clean_eflalo()`. Must include
#'   `.eid` (`.eid`), `lid` (`LE_ID`), `date` (`LE_CDAT`), gear columns
#'   (`gear`, `mesh`, `ir`, `fao`, `met6`), and the `.tid` internal key. If
#'   `fd_clean_eflalo()` was run first, `t1`, `t2`, and `.tsrc` (event
#'   datetimes derived from `date` (`LE_CDAT`) / `LE_STIME` / `LE_ETIME`) will
#'   already be present and are passed through.
#'
#' @return A data frame containing fishing events with:
#'   \describe{
#'     \item{.eid}{Row identifier (`.eid`)}
#'     \item{lid}{Log event identifier (`LE_ID`)}
#'     \item{date}{Catch date, Date (`LE_CDAT`)}
#'     \item{lat1, lon1, lat2, lon2}{Event start/end coordinates, if present (`LE_SLAT`, `LE_SLON`, `LE_ELAT`, `LE_ELON`)}
#'     \item{gear}{Gear code, metier level 4 (`LE_GEAR`)}
#'     \item{mesh}{Mesh size, mm (`LE_MSZ`)}
#'     \item{ir}{ICES statistical rectangle (`LE_RECT`)}
#'     \item{fao}{ICES division (`LE_DIV`)}
#'     \item{met6}{Metier level 6 (`LE_MET`)}
#'     \item{LE_STIME, LE_ETIME}{Event start/end time strings, if present (unchanged)}
#'     \item{LE_KG_*, LE_EURO_*}{Species catch weight and value columns (unchanged)}
#'     \item{t1, t2, .tsrc}{Event datetimes and their derivation source, if present}
#'     \item{.tid}{Internal trip identifier (unchanged)}
#'   }
#'
#' @seealso
#'   \code{\link{fd_clean_eflalo}} for the upstream step that derives `t1`,
#'   `t2`, and `.tsrc`,
#'   \code{\link{fd_trips}} for extracting trip-level data,
#'   \code{\link{fd_tidy_eflalo}} for extracting both trips and events in one call.
#'
#' @examples
#' \dontrun{
#'   events <- fd_events(eflalo)
#'   events |> dplyr::count(.tsrc)
#' }
#'
#' @export
fd_events <- function(eflalo) {

  rows <- nrow(eflalo)
  events <- eflalo |>
    dplyr::select(
      .eid, lid, .data$date,
      dplyr::any_of(c("t1", "t2", ".tsrc")),
      dplyr::any_of(c("lat1", "lon1", "lat2", "lon2",
                      "gear", "mesh", "ir", "fao", "met6")),
      dplyr::starts_with("LE_"),    # catches LE_STIME, LE_ETIME, LE_KG_*, LE_EURO_*
      .tid
    ) |>
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
#' @param eflalo A data frame as returned by `fd_clean_eflalo()`. Must include
#'   the renamed vessel and trip columns (`vid`, `tid`, `T1`, `T2`, etc.), event
#'   columns (`.eid`, `lid`, `date`, `gear`, etc.), and the `.tid` internal key.
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
