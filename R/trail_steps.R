
#' Trail step time
#'
#' @description
#' Computes the time interval (in seconds) between consecutive pings.
#' Use a weighted blend of time since the previous ping and time to the next ping.
#'
#' **Chronological order is the responsibility of the caller**.
#'
#' **Grouping must be done by the caller.** This function operates on a single
#' datetime vector; use it within [dplyr::mutate()] after grouping.
#'
#' @param datetime A POSIXct datetime vector, should be sorted chronologically within groups.
#' @param weight Numeric vector of length 2: weights for the backward and
#'   forward time differences respectively. Normalised to sum to 1. Default
#'   `c(1, 0)` assigns the full interval backward (time since the last ping).
#' @param fill_na Logical. If `TRUE`, boundary `NA`s (first ping has no backward
#'   diff; last ping has no forward diff) are filled with the available
#'   one-sided value. Default `TRUE`.
#'
#' @return A numeric vector (seconds) of the same length as `datetime`.
#'
#' @examples
#' \dontrun{
#' # After fd_clean_tacsat() the datetime column is `time` and vessel id is `vid`
#' tacsat |>
#'   dplyr::group_by(vid) |>
#'   dplyr::mutate(.intv = fd_step_time(time)) |>
#'   dplyr::ungroup()
#'
#' # equal forward/backward blend, fill boundary NAs
#' tacsat |>
#'   dplyr::group_by(vid) |>
#'   dplyr::mutate(.intv = fd_step_time(time, weight = c(0.5, 0.5), fill_na = TRUE)) |>
#'   dplyr::ungroup()
#' }
#'
#' @export
fd_step_time <- function(datetime, weight = c(1, 0), fill_na = TRUE) {
  if (length(weight) != 2 || any(is.na(weight)) || sum(weight) == 0)
    stop("`weight` must be a numeric vector of length 2 with a positive sum")

  weight <- weight / sum(weight)

  # Compute backward and forward differences
  diff_back <- as.numeric(difftime(datetime, dplyr::lag(datetime), units = "secs"))
  diff_fwd  <- as.numeric(difftime(dplyr::lead(datetime), datetime, units = "secs"))

  # Weighted blend
  intv <- if (weight[2] == 0) {
    diff_back
  } else if (weight[1] == 0) {
    diff_fwd
  } else {
    weight[1] * diff_back + weight[2] * diff_fwd
  }

  # Fill boundary NAs if requested
  if (fill_na) {
    intv <- tidyr::fill(
      data.frame(.intv = intv),
      .intv,
      .direction = "downup"
    )$.intv
  }

  return(intv)
}

#' Ping interval in seconds, with an upper cap
#'
#' @description
#' Computes the time interval (in seconds) between consecutive pings via
#' [fd_step_time()], then caps any value that exceeds the `probs` quantile of
#' the computed intervals.
#'
#' **Chronological order and grouping are the responsibility of the caller.**
#' Call this function inside [dplyr::mutate()] after [dplyr::group_by()] on
#' the trip identifier.
#'
#' @param time A POSIXct datetime vector, sorted chronologically within any
#'   potential groups.
#' @param probs Numeric scalar in `[0, 1]`. The quantile of the computed
#'   intervals used as the upper cap. Default `0.975`.
#'
#' @return A numeric vector of ping intervals (seconds), the same length as
#'   `time`, with values capped at the `probs` quantile.
#'
#' @examples
#' \dontrun{
#' ais |>
#'   dplyr::group_by(.tid) |>
#'   dplyr::mutate(.intv = fd_interval_seconds(time)) |>
#'   dplyr::ungroup()
#'
#' # Use 99th percentile as the cap
#' ais |>
#'   dplyr::group_by(.tid) |>
#'   dplyr::mutate(.intv = fd_interval_seconds(time, probs = 0.99)) |>
#'   dplyr::ungroup()
#' }
#'
#' @export
fd_interval_seconds <- function(time, probs = 0.975) {

  dt_sec <- fd_step_time(time)
  max_seconds <- stats::quantile(dt_sec, probs = probs, na.rm = TRUE)
  dt_sec <- ifelse(dt_sec > max_seconds, max_seconds, dt_sec)

  return(dt_sec)
}
