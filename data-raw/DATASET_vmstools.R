library(vmstools)
data("eflalo")
eflalo <- eflalo |>
  dplyr::mutate(FT_DDAT = stringr::str_replace(FT_DDAT, "1800", "1803"),
                FT_DDAT = stringr::str_replace(FT_DDAT, "1801", "1804"),
                FT_LDAT = stringr::str_replace(FT_LDAT, "1800", "1803"),
                FT_LDAT = stringr::str_replace(FT_LDAT, "1801", "1804"),
                LE_CDAT = stringr::str_replace(LE_CDAT, "1800", "1803"),
                LE_CDAT = stringr::str_replace(LE_CDAT, "1801", "1804")) |>
  dplyr::rename(LE_MET = LE_MET_level6)
usethis::use_data(eflalo, overwrite = FALSE)

data("tacsat")
tacsat <- tacsat |>
  dplyr::mutate(SI_DATE = stringr::str_replace(SI_DATE, "1800", "1803"),
                SI_DATE = stringr::str_replace(SI_DATE, "1801", "1804"))
usethis::use_data(tacsat, overwrite = FALSE)

data("harbours")
harbours <-
  harbours |>
  tidyr::as_tibble() |>
  dplyr::mutate(harbour = iconv(harbour, from = "latin1", to = "UTF-8"))
usethis::use_data(harbours, overwrite = FALSE)


data(ICESareas, package = "vmstools")
ices_areas <-
  ICESareas |>
  sf::st_make_valid()
usethis::use_data(ices_areas)


#url <- "https://www.fao.org/fishery/geoserver/fifao/ows?service=WFS&request=GetFeature&version=1.0.0&typeName=FAO_AREAS_NOCOASTLINE"
#download.file(url, destfile = "data-raw/fao_noboarders.gpkg")
#fao <- sf::read_sf("data-raw/fao_noboarders.gpkg")
#fao |> dplyr::glimpse()
