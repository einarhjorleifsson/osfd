#' Convert decimal degree coordinates to ICES statistical rectangle codes
#'
#' Converts longitude/latitude pairs to ICES statistical rectangle codes.
#' Per the ICES specification
#' (<https://www.ices.dk/data/maps/Pages/ICES-statistical-rectangles.aspx>),
#' latitudinal rows have 30' intervals (numbered from 01 at 36°N), and
#' longitudinal columns have 1° intervals — with zone A covering only
#' 44°W–40°W (codes A0–A3), after which zones B onwards each span a full 10°.
#'
#' A small offset (`1e-6`) is added to both inputs so that positions exactly on
#' a rectangle boundary are assigned to the eastern/northern rectangle,
#' matching the convention of `geo::d2ir`.
#'
#' All operations translate to SQL, making the function compatible with
#' [dplyr::mutate()] on both in-memory data frames and remote/lazy database
#' tables (e.g., DuckDB via `duckdbfs`).
#'
#' @param lon Numeric vector of longitudes (decimal degrees, WGS84).
#' @param lat Numeric vector of latitudes (decimal degrees, WGS84).
#' @param sub Logical scalar. If `TRUE`, appends a fifth character (1–9)
#'   identifying the sub-rectangle within the standard rectangle. The ICES
#'   sub-rectangle system divides each 1° × 0.5° rectangle into a 3 × 3 grid
#'   of 20' × 10' cells, numbered north-to-south within each west-to-east
#'   column:
#'   ```
#'   1  4  7
#'   2  5  8
#'   3  6  9
#'   ```
#'   Defaults to `FALSE`.
#'
#' @return A character vector of ICES rectangle codes (e.g., `"41E9"`), or
#'   five-character sub-rectangle codes (e.g., `"41E93"`) when `sub = TRUE`.
#'   Returns `NA` for positions outside the ICES statistical area
#'   (lat < 36, lat ≥ 85.5, lon ≤ -44, lon > 68.5).
#'
#' @examples
#' d2ir(-5.0, 63.2)            # "55E5"
#' d2ir(-5.0, 63.2, sub = TRUE) # "55E52" (middle-west sub-rectangle)
#' d2ir(-43.5, 64.0)           # "57A0"  (zone A: 4-degree sub-divisions)
#'
#' # Works inside mutate on local or lazy frames:
#' tibble::tibble(
#'   lon = c(-5.3, 10.1, -43.5),
#'   lat = c(63.2,  58.7,  64.0)
#' ) |>
#'   dplyr::mutate(ices_rect = d2ir(lon, lat))
#'
#' @export
d2ir <- function(lon, lat, sub = FALSE) {
  # Small nudge: boundary points fall into the eastern/northern rectangle
  lat <- lat + 1e-6
  lon <- lon + 1e-6

  outside <- lat < 36 | lat >= 85.5 | lon <= -44 | lon > 68.5

  # Two-digit zero-padded latitude index (0.5° bands, starting at 36°N)
  lat_num <- floor(lat * 2) - 71
  lat_str <- paste0(ifelse(lat_num < 10, "0", ""), lat_num)

  # Longitude zone letter (10° bands, skipping I)
  lon_letter <- dplyr::case_when(
    lon >= -50 & lon < -40 ~ "A",
    lon >= -40 & lon < -30 ~ "B",
    lon >= -30 & lon < -20 ~ "C",
    lon >= -20 & lon < -10 ~ "D",
    lon >= -10 & lon <   0 ~ "E",
    lon >=   0 & lon <  10 ~ "F",
    lon >=  10 & lon <  20 ~ "G",
    lon >=  20 & lon <  30 ~ "H",
    lon >=  30 & lon <  40 ~ "J",
    lon >=  40 & lon <  50 ~ "K",
    lon >=  50 & lon <  60 ~ "L",
    lon >=  60              ~ "M",
    .default = NA_character_
  )

  # Longitude digit within zone.
  # Zone A spans only ~4 degrees so uses 4° sub-divisions (digits 0-3);
  # all other zones span 10 degrees and use 1° sub-divisions (digits 0-9).
  lon_digit <- ifelse(
    lon >= -50 & lon < -40,
    floor(lon %% 4),
    floor(lon %% 10)
  )

  rect <- paste0(lat_str, lon_letter, lon_digit)

  if (sub) {
    # Sub-rectangle: divide each 1° × 0.5° cell into a 3 × 3 grid of 20' × 10'
    # cells, numbered N→S within each W→E column (1=NW ... 9=SE).
    col_0  <- floor((lon %% 1) * 3)         # 0 = west, 1 = middle, 2 = east
    row_0  <- 2 - floor((lat %% 0.5) * 6)   # 0 = north, 1 = middle, 2 = south
    sub_id <- col_0 * 3 + row_0 + 1
    rect   <- paste0(rect, sub_id)
  }

  ifelse(outside, NA_character_, rect)
}


#' Convert longitude/latitude to a c-square code
#'
#' Computes the c-square notation from decimal-degree coordinates at a
#' user-specified resolution. Based on the c-squares specification v1.1
#' (Rees, 2005).
#'
#' The implementation uses only `floor()`, `abs()`, `round()`, integer
#' arithmetic, `paste0()`, and `as.character()` / `as.integer()`. Despite each
#' of those primitives having a SQL analogue, `fd_calc_csq()` is an R function
#' and **cannot** be called inside [dplyr::mutate()] on a lazy DuckDB /
#' `duckdbfs` table — DuckDB will error because the function is not registered
#' as a SQL scalar function. For DuckDB-compatible spatial gridding at a single
#' resolution, use the midpoint formula (`lon %/% dx * dx + dx/2`) inline.
#'
#' The global quadrant encoding follows the WMO convention: 1 = NE, 3 = SE,
#' 5 = SW, 7 = NW.  Intermediate quadrant digits (1–4) encode whether the
#' latitude and longitude digits within each cycle are "low" (0–4) or "high"
#' (5–9): 1 = both low, 2 = lat low / lon high, 3 = lat high / lon low,
#' 4 = both high.
#'
#' @param lon Numeric vector of longitudes (decimal degrees, WGS84).
#' @param lat Numeric vector of latitudes  (decimal degrees, WGS84).
#' @param degrees Resolution. One of `10`, `5`, `1`, `0.5`, `0.1`, `0.05`,
#'   `0.01`. Default `0.05`.
#'
#' @return A character vector of c-square codes (e.g. `"7500:104:100:1"` at
#'   0.05°). Returns `NA_character_` where `lon` or `lat` is `NA`.
#'
#' @references <https://www.marine.csiro.au/csquares/spec1-1.htm>
#' @seealso [csq2lonlat()] for the inverse.
#' @examples
#' fd_calc_csq(-4, 50, 0.01)   # "7500:104:100:100"
#' fd_calc_csq(-4, 50, 0.05)   # "7500:104:100:1"
#' fd_calc_csq(-4, 50, 1)      # "7500:104"
#' fd_calc_csq(NA, 50, 0.05)   # NA
#'
#' # Works inside mutate on local or lazy frames:
#' tibble::tibble(lon = c(-4, 10), lat = c(50, 55)) |>
#'   dplyr::mutate(csq = fd_calc_csq(lon, lat, 0.05))
#'
#' @export
fd_calc_csq <- function(lon, lat, degrees = 0.05) {
  valid <- c(10, 5, 1, 0.5, 0.1, 0.05, 0.01)
  if (!degrees %in% valid)
    stop("`degrees` must be one of: ", paste(valid, collapse = ", "))
  if (length(lon) != length(lat))
    stop("`lon` and `lat` must have the same length")

  alon <- abs(lon)
  alat <- abs(lat)

  # Global quadrant digit: 1=NE, 3=SE, 5=SW, 7=NW
  gq <- 4 - (2 * floor(1 + lon / 200) - 1) * (2 * floor(1 + lat / 200) + 1)

  # --- Level 0: 10-degree cell (always 4 digits, e.g. "7500") ---
  g_lat <- floor(alat / 10)
  g_lon <- floor(alon / 10)
  r_lat <- round(alat - g_lat * 10, 7)
  r_lon <- round(alon - g_lon * 10, 7)
  code0 <- as.character(as.integer(gq * 1000 + g_lat * 100 + g_lon))

  if (degrees == 10) {
    return(ifelse(is.na(lon) | is.na(lat), NA_character_, code0))
  }

  # --- Level 1: 5-degree intermediate quadrant; 1-degree lat/lon digits ---
  # IQ digit: 1 = both low (<5), 2 = lat low/lon high, 3 = lat high/lon low, 4 = both high
  iq1    <- 2 * floor(r_lat / 5) + floor(r_lon / 5) + 1
  d1_lat <- floor(r_lat)
  d1_lon <- floor(r_lon)
  r1_lat <- round((r_lat - d1_lat) * 10, 7)
  r1_lon <- round((r_lon - d1_lon) * 10, 7)
  # 3-digit code (100–499): always 3 digits, no zero-padding needed
  code1  <- as.character(as.integer(iq1 * 100 + d1_lat * 10 + d1_lon))

  if (degrees == 5) {
    return(ifelse(is.na(lon) | is.na(lat), NA_character_,
                  paste0(code0, ":", iq1)))
  }
  if (degrees == 1) {
    return(ifelse(is.na(lon) | is.na(lat), NA_character_,
                  paste0(code0, ":", code1)))
  }

  # --- Level 2: 0.5-degree intermediate quadrant; 0.1-degree digits ---
  iq2    <- 2 * floor(r1_lat / 5) + floor(r1_lon / 5) + 1
  d2_lat <- floor(r1_lat)
  d2_lon <- floor(r1_lon)
  r2_lat <- round((r1_lat - d2_lat) * 10, 7)
  r2_lon <- round((r1_lon - d2_lon) * 10, 7)
  code2  <- as.character(as.integer(iq2 * 100 + d2_lat * 10 + d2_lon))

  if (degrees == 0.5) {
    return(ifelse(is.na(lon) | is.na(lat), NA_character_,
                  paste0(code0, ":", code1, ":", iq2)))
  }
  if (degrees == 0.1) {
    return(ifelse(is.na(lon) | is.na(lat), NA_character_,
                  paste0(code0, ":", code1, ":", code2)))
  }

  # --- Level 3: 0.05-degree intermediate quadrant; 0.01-degree digits ---
  iq3    <- 2 * floor(r2_lat / 5) + floor(r2_lon / 5) + 1
  d3_lat <- floor(r2_lat)
  d3_lon <- floor(r2_lon)
  code3  <- as.character(as.integer(iq3 * 100 + d3_lat * 10 + d3_lon))

  if (degrees == 0.05) {
    return(ifelse(is.na(lon) | is.na(lat), NA_character_,
                  paste0(code0, ":", code1, ":", code2, ":", iq3)))
  }
  # degrees == 0.01
  ifelse(is.na(lon) | is.na(lat), NA_character_,
         paste0(code0, ":", code1, ":", code2, ":", code3))
}


#' Convert c-square codes to longitude/latitude
#'
#' Decodes a c-square code and returns the centre coordinates of the cell at
#' the requested resolution. Based on the c-squares specification v1.1
#' (Rees, 2005).
#'
#' Unlike [fd_calc_csq()], this function uses `data.frame()` as its return type
#' and is therefore **not** compatible with `dplyr::mutate()` on lazy remote
#' tables. Call it on collected (in-memory) data.
#'
#' @param csq Character vector of c-square codes.
#' @param degrees Resolution at which to return the centre coordinate. Must be
#'   ≤ the resolution of the input codes. One of `10`, `5`, `1`, `0.5`, `0.1`,
#'   `0.05`, `0.01`. Default `0.05`.
#'
#' @return A data frame with columns `lat` and `lon` (decimal degrees, WGS84),
#'   giving the centre of the c-square cell at `degrees` resolution.
#'
#' @references <https://www.marine.csiro.au/csquares/spec1-1.htm>
#' @seealso [fd_calc_csq()] for the forward conversion.
#' @examples
#' csq2lonlat("7500:104:100:100", 0.01)   # lon = -4.005, lat = 50.005
#' csq2lonlat("7500:104:100:1",   0.05)   # lon = -4.025, lat = 50.025
#' csq2lonlat("7500:104",         1)      # lon = -4.5,   lat = 50.5
#' csq2lonlat("7500",             10)     # lon = -5,     lat = 55
#'
#' @export
csq2lonlat <- function(csq, degrees = 0.05) {
  valid <- c(10, 5, 1, 0.5, 0.1, 0.05, 0.01)
  if (!degrees %in% valid)
    stop("`degrees` must be one of: ", paste(valid, collapse = ", "))

  gq       <- as.integer(substr(csq, 1, 1))
  lat_tens <- as.numeric(substr(csq, 2, 2))   # single digit → 0-9
  lon_tens <- as.numeric(substr(csq, 3, 4))   # two digits   → 0-18

  # Latitude is positive for global quadrants 1 (NE) and 7 (NW)
  lat_sign <- ifelse(gq == 1L | gq == 7L,  1, -1)
  # Longitude is positive for global quadrants 1 (NE) and 3 (SE)
  lon_sign <- ifelse(gq == 1L | gq == 3L,  1, -1)

  lat0 <- lat_tens * 10
  lon0 <- lon_tens * 10

  if (degrees == 10) {
    return(data.frame(
      lat = (lat0 + 5) * lat_sign,
      lon = (lon0 + 5) * lon_sign
    ))
  }

  # Level 1 — 1-degree digits; 5-degree intermediate quadrant (IQ)
  iq1    <- as.integer(substr(csq,  6,  6))
  lat1   <- as.numeric(substr(csq,  7,  7))
  lon1   <- as.numeric(substr(csq,  8,  8))
  # IQ ≥ 3 → lat digit is "high" (≥ 5 within the 10-degree band)
  # IQ even → lon digit is "high"
  lat1_hi <- iq1 >= 3L
  lon1_hi <- iq1 %% 2L == 0L

  if (degrees == 5) {
    return(data.frame(
      lat = (lat0 + ifelse(lat1_hi, 5, 0) + 2.5) * lat_sign,
      lon = (lon0 + ifelse(lon1_hi, 5, 0) + 2.5) * lon_sign
    ))
  }
  if (degrees == 1) {
    return(data.frame(
      lat = (lat0 + lat1 + 0.5) * lat_sign,
      lon = (lon0 + lon1 + 0.5) * lon_sign
    ))
  }

  # Level 2 — 0.1-degree digits; 0.5-degree IQ
  iq2    <- as.integer(substr(csq, 10, 10))
  lat2   <- as.numeric(substr(csq, 11, 11))
  lon2   <- as.numeric(substr(csq, 12, 12))
  lat2_hi <- iq2 >= 3L
  lon2_hi <- iq2 %% 2L == 0L

  if (degrees == 0.5) {
    return(data.frame(
      lat = (lat0 + lat1 + ifelse(lat2_hi, 0.5, 0) + 0.25) * lat_sign,
      lon = (lon0 + lon1 + ifelse(lon2_hi, 0.5, 0) + 0.25) * lon_sign
    ))
  }
  if (degrees == 0.1) {
    return(data.frame(
      lat = (lat0 + lat1 + lat2 * 0.1 + 0.05) * lat_sign,
      lon = (lon0 + lon1 + lon2 * 0.1 + 0.05) * lon_sign
    ))
  }

  # Level 3 — 0.01-degree digits; 0.05-degree IQ
  iq3    <- as.integer(substr(csq, 14, 14))
  lat3   <- as.numeric(substr(csq, 15, 15))
  lon3   <- as.numeric(substr(csq, 16, 16))
  lat3_hi <- iq3 >= 3L
  lon3_hi <- iq3 %% 2L == 0L

  if (degrees == 0.05) {
    return(data.frame(
      lat = (lat0 + lat1 + lat2 * 0.1 + ifelse(lat3_hi, 0.05, 0) + 0.025) * lat_sign,
      lon = (lon0 + lon1 + lon2 * 0.1 + ifelse(lon3_hi, 0.05, 0) + 0.025) * lon_sign
    ))
  }
  # degrees == 0.01
  data.frame(
    lat = (lat0 + lat1 + lat2 * 0.1 + lat3 * 0.01 + 0.005) * lat_sign,
    lon = (lon0 + lon1 + lon2 * 0.1 + lon3 * 0.01 + 0.005) * lon_sign
  )
}


#' Compute the area of a c-square cell in km²
#'
#' Returns the geodetic area (km²) of a c-square cell using a spherical-Earth
#' approximation. Cell area varies with latitude because lines of longitude
#' converge toward the poles: a cell of resolution \eqn{r}° has a constant
#' height of \eqn{r \times 111.1942} km but a width of
#' \eqn{r \times 111.1942 \times \cos(\phi)} km, where \eqn{\phi} is the
#' centre latitude. The constant 111.1942 km/° is derived from the mean
#' circumference of the Earth (≈ 40,030 km / 360°), consistent with the
#' nautical-mile definition (1° = 60 nm, 1 nm = 1852 m).
#'
#' Area formula:
#' \deqn{A = r^2 \times \cos(\phi \cdot \pi / 180) \times 111.1942^2}
#'
#' The resolution \eqn{r} can be supplied explicitly or inferred automatically
#' from the character length of the code:
#'
#' | `nchar(csq)` | Resolution |
#' |---|---|
#' | 4  | 10°   |
#' | 6  | 5°    |
#' | 8  | 1°    |
#' | 10 | 0.5°  |
#' | 12 | 0.1°  |
#' | 14 | 0.05° |
#' | 16 | 0.01° |
#'
#' @param csq Character vector of c-square codes (as produced by
#'   [fd_calc_csq()]).
#' @param resolution Resolution of the codes in decimal degrees. One of `10`,
#'   `5`, `1`, `0.5`, `0.1`, `0.05`, `0.01`. If `NULL` (default), the
#'   resolution is inferred automatically from the length of the first
#'   non-`NA` code. All codes in `csq` must share the same resolution;
#'   supply `resolution` explicitly if that cannot be guaranteed.
#'
#' @return Numeric vector of cell areas in km², the same length as `csq`.
#'   Returns `NA` where `csq` is `NA`.
#'
#' @seealso [fd_calc_csq()] to generate c-square codes,
#'   [csq2lonlat()] to retrieve cell-centre coordinates.
#'
#' @examples
#' # Auto-detect resolution from code length
#' csq_area("7500:104:100:1")        # 0.05° cell at ~50°N ≈ 19.9 km²
#' csq_area("7500:104")              # 1° cell at ~50°N    ≈ 7865 km²
#'
#' # Supply resolution explicitly
#' csq_area("7500:104:100:1", resolution = 0.05)
#'
#' # Vectorised — area decreases toward the poles
#' codes <- fd_calc_csq(lon = rep(0, 4), lat = c(0, 30, 60, 80), degrees = 0.05)
#' csq_area(codes)
#'
#' @export
csq_area <- function(csq, resolution = NULL) {
  nchar_map <- c(
    "4"  = 10,
    "6"  = 5,
    "8"  = 1,
    "10" = 0.5,
    "12" = 0.1,
    "14" = 0.05,
    "16" = 0.01
  )

  if (is.null(resolution)) {
    nc <- nchar(csq[!is.na(csq)][1])
    resolution <- nchar_map[as.character(nc)]
    if (is.na(resolution))
      stop("Cannot infer resolution from c-square code length ", nc,
           ". Provide `resolution` explicitly.")
    resolution <- unname(resolution)
  }

  lat <- csq2lonlat(csq, resolution)$lat
  resolution^2 * cos(lat * pi / 180) * 111.1942^2
}


#' Convert a data frame of positions to ICES statistical rectangle codes
#'
#' A corrected version of `ICESrectangle()` from the
#' [vmstools](https://github.com/nielshintzen/vmstools) package. The original
#' function contains a bug in zone A: it anchors the zone at -50°W and applies
#' standard 10° modular arithmetic, producing impossible digit codes (4–9) for
#' all positions in the actual zone-A extent (-44° to -40°). This version fixes
#' that by using 4° sub-divisions (digits 0–3) for zone A, consistent with the
#' ICES rectangle specification and `geo::d2ir`.
#'
#' A secondary fix aligns the boundary convention with `d2ir`: points at exact
#' integer-longitude zone boundaries (e.g. -40°, -30°, -10°) are now assigned
#' to the eastern zone.
#'
#' @param dF A data frame with columns `SI_LATI` (latitude) and `SI_LONG`
#'   (longitude), both in decimal degrees (WGS84).
#'
#' @return A character vector of ICES rectangle codes, one per row of `dF`.
#'
#' @seealso [d2ir()] for a vector-based, dbplyr-compatible equivalent.
#'
#' @keywords internal
ICESrectangle <- function(dF) {
  d2ir(lon = dF[, "SI_LONG"], lat = dF[, "SI_LATI"])
}


# sf::sf_use_s2(FALSE)

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
#'
#' @export
fd_add_sf <- function(ais, shape) {

  s2_state <- sf::sf_use_s2()
  sf::sf_use_s2(FALSE)

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

  sf::sf_use_s2(s2_state)

  return(ais)

}
