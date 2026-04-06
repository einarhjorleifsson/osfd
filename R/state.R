#' Title
#'
#' @param ais xxx
#' @param speed_table xxx
#'
#' @returns tibble
#' @export
#'
fd_add_state <- function(ais, speed_table) {
  ais |>
    dplyr::left_join(speed_table) |>
    dplyr::mutate(state = dplyr::case_when(dplyr::between(speed, s1, s2) ~ "fishing",
                                           .default = "something else")) |>
    dplyr::select(-c(s1, s2))
}
