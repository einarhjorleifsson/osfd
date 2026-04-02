#' EFLALO example logbook dataset
#'
#' @description
#' A synthetic logbook dataset in EFLALO2 format, originally distributed with
#' the `vmstools` package (EU Lot 2 project). Covers a fictional fleet
#' ("Atlantis") fishing across ICES areas III, IV, VI, VII, and VIII over two
#' consecutive years (1803–1804).
#'
#' The dataset was modified from the `vmstools` original in two ways:
#' \itemize{
#'   \item Years shifted from 1800–1801 to 1803–1804. The original years were
#'     problematic because 1800 is not a Gregorian leap year (divisible by 100
#'     but not 400), which caused silent errors in interval and date-difference
#'     calculations that assumed it was. 1804 is a proper leap year.
#'   \item Column `LE_MET_level6` renamed to `LE_MET` to match the ICES
#'     datacall column naming convention.
#' }
#'
#' Dates and times are stored as character strings in the original EFLALO2
#' format (`DD/MM/YYYY` and `HH:MM`).
#'
#' @format A data frame with 4,539 rows and 189 variables.
#'
#' **Vessel (`VE_*`)**
#'
#' | Column | Type | Description |
#' |--------|------|-------------|
#' | `VE_REF` | chr | Vessel reference / ID |
#' | `VE_FLT` | chr | Fleet reference (DCF regulation) |
#' | `VE_COU` | chr | Flag nation — `"Atlantis"` throughout |
#' | `VE_LEN` | num | Vessel length overall (m) |
#' | `VE_KW`  | num | Engine power (kW) |
#' | `VE_TON` | num | Gross tonnage GT (largely `NA`) |
#'
#' **Trip (`FT_*`)**
#'
#' | Column | Type | Description |
#' |--------|------|-------------|
#' | `FT_REF`   | chr | Fishing trip reference number |
#' | `FT_DCOU`  | chr | Departure country |
#' | `FT_DHAR`  | chr | Departure harbour (UN LOCODE) |
#' | `FT_DDAT`  | chr | Departure date `DD/MM/YYYY` |
#' | `FT_DTIME` | chr | Departure time `HH:MM` |
#' | `FT_LCOU`  | chr | Landing country |
#' | `FT_LHAR`  | chr | Landing harbour (UN LOCODE) |
#' | `FT_LDAT`  | chr | Landing date `DD/MM/YYYY` |
#' | `FT_LTIME` | chr | Landing time `HH:MM` |
#'
#' **Log event (`LE_*`)**
#'
#' | Column | Type | Description |
#' |--------|------|-------------|
#' | `LE_ID`    | chr | Log event ID |
#' | `LE_CDAT`  | chr | Catch date `DD/MM/YYYY` |
#' | `LE_STIME` | chr | Event start time (mostly `NA`) |
#' | `LE_ETIME` | chr | Event end time (mostly `NA`) |
#' | `LE_SLAT`  | num | Event start latitude (mostly `NA`) |
#' | `LE_SLON`  | num | Event start longitude (mostly `NA`) |
#' | `LE_ELAT`  | num | Event end latitude (mostly `NA`) |
#' | `LE_ELON`  | num | Event end longitude (mostly `NA`) |
#' | `LE_GEAR`  | chr | Gear, DCF métier level 4 (DRB, FPO, GN, GNS, LHP, MIS, OTB, OTM, PTB, TBB) |
#' | `LE_MSZ`   | num | Mesh size, mm stretched mesh |
#' | `LE_RECT`  | chr | ICES statistical rectangle |
#' | `LE_DIV`   | chr | ICES division |
#' | `LE_MET`   | chr | Fishing activity, DCF métier level 6 |
#' | `LE_UNIT`  | fct | Effort unit |
#' | `LE_EFF`   | num | Effort value |
#' | `LE_EFF_VMS` | lgl | VMS-derived effort (all `NA`) |
#'
#' **Catch / value (species columns)**
#'
#' 79 landing weight columns `LE_KG_<SP>` (kg, numeric) and 79 landing value
#' columns `LE_EURO_<SP>` (EUR, numeric), where `<SP>` is the FAO 3-letter
#' species code (e.g. `LE_KG_COD`, `LE_EURO_SOL`).
#'
#' @note
#' This dataset is provided for example and testing purposes only. It is
#' derived from the `vmstools` package, where it is described as: *"Without
#' prior permission of the authors it is not allowed to use this data other
#' than for example non-publishable purposes."* The original data are of
#' disguised origin and do not represent real fishing activity.
#'
#' @source
#' `vmstools` R package, EU Lot 2 project.
#' Contact: Niels T. Hintzen \email{niels.hintzen@@wur.nl}.
#' Modified for `osfd` via `data-raw/DATASET_vnstools.R`.
#'
"eflalo"


#' TACSAT example VMS dataset
#'
#' @description
#' A synthetic Vessel Monitoring System (VMS) dataset in TACSAT2 format,
#' originally distributed with the `vmstools` package (EU Lot 2 project).
#' Covers the same fictional "Atlantis" fleet as [eflalo] over two consecutive
#' years (1803–1804).
#'
#' The dataset was modified from the `vmstools` original by shifting years from
#' 1800–1801 to 1803–1804, for the same reason as [eflalo]: 1800 is not a
#' Gregorian leap year, which caused silent errors in date-difference
#' calculations.
#'
#' Date and time are stored as character strings (`SI_DATE` as `DD/MM/YYYY`,
#' `SI_TIME` as `HH:MM`).
#'
#' @format A data frame with 97,015 rows and 8 variables:
#' \describe{
#'   \item{VE_COU}{Flag nation — `"Atlantis"` throughout (character)}
#'   \item{VE_REF}{Vessel reference / ID (character)}
#'   \item{SI_LATI}{Latitude, decimal degrees (numeric)}
#'   \item{SI_LONG}{Longitude, decimal degrees (numeric)}
#'   \item{SI_DATE}{Date, `DD/MM/YYYY` (character)}
#'   \item{SI_TIME}{Time (UTC), `HH:MM` (character)}
#'   \item{SI_SP}{Instantaneous speed, knots (numeric)}
#'   \item{SI_HE}{Instantaneous heading, degrees (numeric)}
#' }
#'
#' @note
#' This dataset is provided for example and testing purposes only. It is
#' derived from the `vmstools` package, where it is described as: *"Without
#' prior permission of the authors it is not allowed to use this data other
#' than for example non-publishable purposes."* The original data are of
#' disguised origin and do not represent real fishing activity.
#'
#' @source
#' `vmstools` R package, EU Lot 2 project.
#' Contact: Niels T. Hintzen \email{niels.hintzen@@wur.nl}.
#' Modified for `osfd` via `data-raw/DATASET_vnstools.R`.
#'
"tacsat"


#' Harbour locations
#'
#' @description
#' European harbour locations, for use
#' in filtering of VMS pings near port.
#' Derived from the `harbours` dataset in the `vmstools` package.
#'
#' @format An `sf` data frame with 3,839 rows and 5 variables:
#' \describe{
#'   \item{harbour}{Harbour name (character)}
#'   \item{lon}{Longitude of harbour centroid, decimal degrees (numeric)}
#'   \item{lat}{Latitude of harbour centroid, decimal degrees (numeric)}
#'   \item{range}{Buffer radius in km — always 3 (numeric)}
#' }
#'
#' @source
#' `vmstools` R package. Processed for `osfd` via `data-raw/DATASET_vnstools.R`.
#'
"harbours"


#' ICES statistical area polygons
#'
#' @description
#' Polygons for ICES statistical areas in the North-East Atlantic (FAO Major
#' Area 27), used for spatial filtering of VMS data to the area of interest.
#' Derived from the `ICESareas` dataset in the
#' `vmstools` package, with invalid geometries repaired via
#' `sf::st_make_valid()`.
#'
#' @format An `sf` data frame with 66 rows and 11 variables:
#' \describe{
#'   \item{OBJECTID_1}{Internal object ID (numeric)}
#'   \item{OBJECTID}{Internal object ID (numeric)}
#'   \item{Major_FA}{FAO major fishing area — `"27"` throughout (character)}
#'   \item{SubArea}{ICES sub-area (character)}
#'   \item{Division}{ICES division (character)}
#'   \item{SubDivisio}{ICES sub-division (character)}
#'   \item{Unit}{ICES unit area (character; often `NA`)}
#'   \item{Area_Full}{Full area code, e.g. `"27.4.b"` (character)}
#'   \item{Area_27}{Area code without the leading `"27."`, e.g. `"4.b"` (character)}
#'   \item{Area_km2}{Area in km² (numeric)}
#'   \item{geometry}{Multi-polygon geometry, CRS: WGS 84 / EPSG:4326}
#' }
#'
#' @source
#' `vmstools` R package (`ICESareas`). Processed for `osfd` via
#' `data-raw/DATASET_vmstools.R`.
#'
"ices_areas"


#' Field definitions for TACSAT2 and EFLALO2
#'
#' @description
#' A data dictionary covering all fields in the TACSAT2 and EFLALO2 formats as
#' specified by the ICES VMS and Logbook Data-Call, plus the derived columns
#' added by `fd_clean_tacsat()` and `fd_clean_eflalo()`.
#'
#' Useful for programmatically checking that user-supplied data frames contain
#' the expected columns with the expected types, and for documentation.
#'
#' @format A tibble with 47 rows and 7 variables:
#' \describe{
#'   \item{`field`}{Variable name in R (character). Species-specific columns
#'     are represented as `LE_KG_<SP>` and `LE_EURO_<SP>`.}
#'   \item{`table`}{Which table the field belongs to: `"tacsat"`, `"eflalo"`,
#'     or `"both"` (character).}
#'   \item{`type`}{Expected R type after import / cleaning: `"chr"`, `"dbl"`,
#'     `"int"`, `"dttm"`, `"date"`, or `"lgl"` (character).}
#'   \item{`format`}{Raw format in the original file, e.g. `"DD/MM/YYYY"` or
#'     `"Decimal degrees"`. `NA` for derived columns (character).}
#'   \item{`description`}{Short description of the field (character).}
#'   \item{`required`}{`TRUE` if the field is required by `fd_clean_*` or the
#'     data-call; `FALSE` if optional (logical).}
#'   \item{`derived`}{`TRUE` if the field is added or transformed by
#'     `fd_clean_tacsat()` / `fd_clean_eflalo()`; `FALSE` if present in the
#'     raw file (logical).}
#' }
#'
#' @source
#' ICES VMS and Logbook Data-Call format specification. Derived columns
#' documented from `fd_clean_tacsat()` and `fd_clean_eflalo()` source code.
#' Built via `data-raw/DATASET_field_definitions.R`.
#'
"field_definitions"
