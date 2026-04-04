#' Translate column names of a data frame or lazy tibble using a dictionary
#'
#' This function allows renaming column names in an input object (a `data.frame` or `tbl_lazy`)
#' by translating them with a user-supplied dictionary. Users can choose to translate
#' column names from "old" to "new" or vice versa.
#'
#' @param d A `data.frame` or `tbl_lazy` object whose column names need to be translated.
#' @param dictionary A `data.frame` (or tibble) with at least two columns: `from` and `to`
#'   (default names are "old" and "new"). The `from` column contains the current column names
#'   in `d`, and the `to` column contains the new column names to translate to.
#' @param from A string specifying the column name in `dictionary` to use for current column
#'   name matching. Defaults to "old".
#' @param to A string specifying the column name in `dictionary` with new column names
#'   to translate to. Defaults to "new".
#'
#' @return An object of the same class as `d` with column names translated.
#'
#' @examples
#' # Example dictionary
#' dictionary <- data.frame(
#'     old = c("Ship", "SweepLngt"),
#'     new = c("Platform", "SweepLength")
#' )
#' # Example data
#' df <- data.frame(Ship = "26D4", SweepLngt = 110)
#'
#' fd_translate(df, dictionary)
#' @export
fd_translate <- function(d, dictionary, from = "old", to = "new") {
  # Input checks
  if (!inherits(d, c("data.frame", "tbl_lazy"))) {
    stop("`d` must be either a data.frame or a tbl_lazy object.")
  }

  if (!is.data.frame(dictionary)) {
    stop("`dictionary` must be a data.frame or tibble.")
  }

  if (!all(c(from, to) %in% colnames(dictionary))) {
    stop("`dictionary` must contain the specified `from` and `to` columns.")
  }

  # Perform the translation
  d <- dplyr::rename_with(d, .fn = function(col) {
    # Match column names in the 'from' column and translate to 'to' column
    new_names <- dictionary[[to]][match(col, dictionary[[from]])]
    # Keep original column names if there is no match
    ifelse(is.na(new_names), col, new_names)
  })
  return(d)
}

#' Spatially join an sf polygon layer onto AIS/VMS pings
#'
#' Converts `ais` to an `sf` point object (if not already) using columns `lon`
#' and `lat` (CRS 4326), then performs a spatial left join with `shape` via
#' [sf::st_join()]. A row-count guard stops if the join inflates the number of
#' rows, which would indicate a one-to-many match (overlapping polygons).
#'
#' @param ais Data frame or `sf` object of VMS/AIS pings. If not already `sf`,
#'   must contain columns `lon` and `lat`.
#' @param shape An `sf` polygon object to join onto `ais`.
#'
#' @return An `sf` object with the same number of rows as `ais`, augmented with
#'   columns from `shape`.
#'
#' @note The row-count guard stops with an uninformative message if `shape`
#'   contains overlapping polygons causing a one-to-many join. Consider
#'   using [sf::st_join()] with `largest = TRUE` or pre-dissolving overlaps
#'   if this is a concern.
fd_add_sf <- function(ais, shape) {

  if(!inherits(shape, "sf")) stop("Added file not a shapefile")

  rows <- nrow(ais)

  if (!inherits(ais, "sf")) {
    ais <-
      ais |>
      sf::st_as_sf(coords = c("lon", "lat"),
                   crs = 4326,
                   remove = FALSE)
  }


  ais <-
    ais |>
    sf::st_join(shape)

  if(nrow(ais) > rows) stop("Screeeeeam")

  return(ais)

}


