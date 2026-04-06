#' Add gear width to VMS pings
#'
#' @description
#' Predicts gear contact width (km) for each VMS ping using the BENTHIS model
#' and appends the result as a new column `.gearwidth`. The fill priority is:
#'
#' 1. User-supplied `LE_GEARWIDTH` (if the column is present and not `NA`).
#' 2. Model prediction from [sfdSAR::predict_gear_width()] (converted from
#'    metres to km).
#' 3. BENTHIS lookup-table default (`gearWidth`).
#'
#' The lookup table is built internally via [fd_benthis_lookup()], which
#' fetches the RCG métier reference list from GitHub at runtime.
#'
#' @param x A data frame of VMS pings. Must contain the columns named by
#'   `met_name`, `oal_name`, and `kw_name`.
#' @param met_name Character. Column name for métier level 6. Default `"met6"`
#'   (the name used after [fd_clean_eflalo()]).
#' @param oal_name Character. Column name for overall vessel length (metres).
#'   Default `"length"` (the name used after [fd_clean_eflalo()]).
#' @param kw_name Character. Column name for engine power (kW). Default `"kw"`
#'   (the name used after [fd_clean_eflalo()]).
#'
#' @return `x` with one additional column `.gearwidth` (numeric, km). `NA`
#'   where no value could be determined.
#'
#' @note Requires `sfdSAR` and `icesVMS`. Fetches the métier reference list
#'   from GitHub at runtime — an internet connection is required.
#'
#' @source Adapted from the ICES VMS and Logbook Data Call workflow:
#'   <https://github.com/ices-eg/ICES-VMS-and-Logbook-Data-Call>
#'
#' @examples
#' \dontrun{
#' ais2 <- ais2 |> fd_add_gearwidth()
#'
#' # Non-default column names (raw ICES names)
#' ais2 <- ais2 |>
#'   fd_add_gearwidth(met_name = "LE_MET", oal_name = "VE_LEN", kw_name = "VE_KW")
#' }
#'
#' @export
fd_add_gearwidth <- function(x, met_name = "met6", oal_name = "length", kw_name = "kw") {

  vms <- x |>
    dplyr::mutate(
      dplyr::across(dplyr::all_of(c(oal_name, kw_name)), as.numeric),
      Metier_level6 = .data[[met_name]]
    ) |>
    dplyr::left_join(
      fd_benthis_lookup(kw_name = kw_name, oal_name = oal_name),
      by = "Metier_level6"
    )

  # Predict model gear width (metres) for rows with a complete model spec
  valid <- !is.na(vms$gearModel) & !is.na(vms$gearCoefficient)
  gearwidth_model <- rep(NA_real_, nrow(vms))
  gearwidth_model[valid] <- sfdSAR::predict_gear_width(
    vms$gearModel[valid],
    vms$gearCoefficient[valid],
    vms[valid, ]
  )

  # User-supplied gear width (optional column)
  le_gearwidth <- if ("LE_GEARWIDTH" %in% names(vms)) {
    vms$LE_GEARWIDTH
  } else {
    rep(NA_real_, nrow(vms))
  }

  # Fill priority: user-supplied > model (m → km) > BENTHIS table default
  x |>
    dplyr::mutate(
      .gearwidth = dplyr::case_when(
        !is.na(le_gearwidth)      ~ le_gearwidth,
        !is.na(gearwidth_model)   ~ gearwidth_model / 1000,
        .default = vms$gearWidth
      )
    )
}


#' Add swept area to VMS pings
#'
#' @description
#' Calculates the area swept (km²) by the fishing gear for each VMS ping and
#' appends the result as a new column `.sa`. The calculation is dispatched by
#' gear type:
#'
#' - **Danish seine** (`SDN`): rope-loop geometry
#'   ([sfdSAR::danish_seine_contact()]).
#' - **Scottish seine** (`SSC`): rope-loop geometry with a splitting-phase
#'   multiplier ([sfdSAR::scottish_seine_contact()]).
#' - **All other gears**: standard trawl formula —
#'   `SA = gear_width × fishing_hours × fishing_speed × 1.852`
#'   ([sfdSAR::trawl_contact()]).
#'
#' For seines, `gear_width` represents total rope length (which may exceed
#' 6 km), not net width.
#'
#' @param x A data frame of VMS pings. Must contain the columns named by
#'   `gear_name`, `intv_name`, `gearwidth_name`, and `speed_name`.
#' @param gear_name Character. Column name for the gear code (métier level 4).
#'   Default `"gear"` (the name used after [fd_clean_eflalo()]).
#' @param intv_name Character. Column name for the ping interval **in
#'   seconds**. Default `".intv"` (as produced by [fd_interval_seconds()]).
#' @param gearwidth_name Character. Column name for gear width **in km**.
#'   Default `".gearwidth"` (as produced by [fd_add_gearwidth()]).
#' @param speed_name Character. Column name for fishing speed **in knots**.
#'   Default `"speed"` (the name used after [fd_clean_tacsat()]).
#'
#' @return `x` with one additional column `.sa` (numeric, km²). `NA` where
#'   gear width or speed is unavailable.
#'
#' @note Requires `sfdSAR`. See the WGSFD 2025 Report for a full discussion of
#'   the swept-area methodology:
#'   <https://doi.org/10.17895/ices.pub.3073475>
#'
#' @source Adapted from the ICES VMS and Logbook Data Call workflow:
#'   <https://github.com/ices-eg/ICES-VMS-and-Logbook-Data-Call>
#'
#' @examples
#' \dontrun{
#' ais2 <- ais2 |>
#'   fd_add_gearwidth() |>
#'   fd_add_sa()
#' }
#'
#' @export
fd_add_sa <- function(x,
                      gear_name      = "gear",
                      intv_name      = ".intv",
                      gearwidth_name = ".gearwidth",
                      speed_name     = "speed") {
  x |>
    dplyr::mutate(
      .model = dplyr::case_when(
        .data[[gear_name]] == "SDN" ~ "danish_seine_contact",
        .data[[gear_name]] == "SSC" ~ "scottish_seine_contact",
        .default = "trawl_contact"
      ),
      .sa = sfdSAR::predict_surface_contact(
        model         = .data$.model,
        fishing_hours = .data[[intv_name]] / 3600,
        gear_width    = .data[[gearwidth_name]],
        fishing_speed = .data[[speed_name]]
      )
    ) |>
    dplyr::select(-".model")
}


#' Build the BENTHIS gear-width lookup table
#'
#' @description
#' Fetches the RCG métier reference list from the ICES GitHub repository and
#' joins it with the BENTHIS gear-width parameters from [icesVMS::get_benthis_parameters()].
#' The result is a lookup table keyed on `Metier_level6` that is used
#' downstream by gear-width prediction to map each VMS ping to its BENTHIS
#' model coefficients.
#'
#' The `gearCoefficient` column in the raw BENTHIS table contains two sentinel
#' strings (`"avg_kw"`, `"avg_oal"`) that reference whichever columns in the
#' VMS data hold engine power and vessel length. These are replaced here with
#' the actual column names supplied via `kw_name` and `oal_name` so that
#' [sfdSAR::predict_gear_width()] can address them directly.
#'
#' @param kw_name Character. Name of the engine-power column in the VMS data
#'   frame. Replaces the `"avg_kw"` sentinel in `gearCoefficient`. Default
#'   `"kw"` (the name used after [fd_clean_eflalo()]).
#' @param oal_name Character. Name of the overall-length column in the VMS data
#'   frame. Replaces the `"avg_oal"` sentinel in `gearCoefficient`. Default
#'   `"length"` (the name used after [fd_clean_eflalo()]).
#'
#' @return A data frame with one row per unique `Metier_level6` × BENTHIS métier
#'   combination and columns:
#'   `Metier_level6`, `benthisMet`, `avKw`, `avLoa`, `avFspeed`,
#'   `subsurfaceProp`, `gearWidth`, `firstFactor`, `secondFactor`,
#'   `gearModel`, `gearCoefficient`, `contactModel`.
#'
#' @note Requires `icesVMS`. Fetches the métier reference list from GitHub at
#'   runtime — an internet connection is required.
#'
#' @source Adapted from the ICES VMS and Logbook Data Call workflow:
#'   <https://github.com/ices-eg/ICES-VMS-and-Logbook-Data-Call>
#'
#' @examples
#' \dontrun{
#' aux_lookup <- fd_benthis_lookup()
#'
#' # If your VMS data uses non-default column names:
#' aux_lookup <- fd_benthis_lookup(kw_name = "VE_KW", oal_name = "VE_LEN")
#' }
#'
#' @export
fd_benthis_lookup <- function(kw_name = "kw", oal_name = "length") {

  metier_lookup <- utils::read.csv(
    "https://raw.githubusercontent.com/ices-eg/RCGs/master/Metiers/Reference_lists/RDB_ISSG_Metier_list.csv"
  )

  gear_widths <- icesVMS::get_benthis_parameters()

  dplyr::full_join(gear_widths, metier_lookup,
                   by = c("benthisMet" = "Benthis_metiers")) |>
    dplyr::select(
      "Metier_level6", "benthisMet", "avKw", "avLoa", "avFspeed",
      "subsurfaceProp", "gearWidth", "firstFactor", "secondFactor",
      "gearModel", "gearCoefficient", "contactModel"
    ) |>
    dplyr::mutate(
      gearCoefficient = dplyr::case_when(
        .data$gearCoefficient == "avg_kw"  ~ kw_name,
        .data$gearCoefficient == "avg_oal" ~ oal_name,
        .default = .data$gearCoefficient
      )
    ) |>
    dplyr::distinct()
}
