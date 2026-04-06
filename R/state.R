#' Classify VMS pings as fishing or non-fishing by speed threshold
#'
#' @description
#' Joins a speed-threshold lookup table onto VMS/AIS pings and classifies each
#' ping as `"fishing"` or `"something else"` based on whether its speed falls
#' within the gear-specific range `[s1, s2]`.
#'
#' **Note:** This function is a working stub. The join key between `ais` and
#' `speed_table` (currently implicit), the fallback label (`"something else"`),
#' and the parameter for controlling the join are all provisional and subject
#' to change.
#'
#' @param ais A data frame of VMS/AIS pings as returned by
#'   [fd_add_events()]. Must contain `speed` (knots) and whichever column
#'   in `speed_table` is used as the join key (typically `gear`).
#' @param speed_table A data frame with columns `gear`, `target` (fishing
#'   target assemblage), `s1` (lower speed threshold, knots), and `s2` (upper
#'   speed threshold, knots). Join to `ais` is currently implicit — ensure
#'   column names match.
#'
#' @return `ais` with a `state` character column appended: `"fishing"` where
#'   `speed` is within `[s1, s2]`, `"something else"` otherwise. Columns `s1`
#'   and `s2` are dropped before returning.
#'
#' @seealso [fd_add_events()] for the preceding join step.
#'
#' @export
#'
fd_add_state <- function(ais, speed_table) {
  ais |>
    dplyr::left_join(speed_table) |>
    dplyr::mutate(state = dplyr::case_when(dplyr::between(speed, s1, s2) ~ "fishing",
                                           .default = "something else")) |>
    dplyr::select(-c(s1, s2))
}
