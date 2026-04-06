#'------------------------------------------------------------------------------
# Download the bathymetry and habitat files                                 ----
#'------------------------------------------------------------------------------

download_large_file <- function(url, dest_file, file_size) {
  # Create a simple text-based progress bar using Base R
  progress_bar <- function(current, total, width = 60) {
    percent <- current / total
    filled <- round(width * percent)
    bar <- paste0(
      "[",
      paste0(rep("=", filled), collapse = ""),
      paste0(rep(" ", width - filled), collapse = ""),
      "]"
    )

    # Calculate ETA
    elapsed_time <- as.numeric(difftime(Sys.time(), start_time, units = "secs"))
    eta <- if (percent > 0) {
      round((elapsed_time / percent) - elapsed_time)
    } else {
      NA
    }

    # Format ETA for display
    eta_str <- if (is.na(eta)) {
      "calculating..."
    } else if (eta < 60) {
      paste0(eta, "s")
    } else if (eta < 3600) {
      paste0(round(eta / 60), "m ", eta %% 60, "s")
    } else {
      paste0(round(eta / 3600), "h ", round((eta %% 3600) / 60), "m")
    }

    # Create the full progress string
    prog_str <- sprintf("  downloading %s %3d%% eta: %s", bar, round(percent * 100), eta_str)

    # Clear the line and write the progress
    cat("\r", prog_str, sep = "")
    if (current >= total) cat("\n")
    utils::flush.console()
  }

  # Store original timeout setting
  original_timeout <- getOption("timeout")

  # Temporarily increase timeout just for this function's scope
  options(timeout = 600)
  # This gives a 10-minute timeout - if you have a slow internet connection you might need to increase this

  # Use on.exit to ensure the original timeout value is restored even if the function errors
  on.exit(options(timeout = original_timeout))

  # Record start time for ETA calculation
  start_time <- Sys.time()

  # Open connections
  con <- url(url, "rb")
  output <- file(dest_file, "wb")

  # Read and write in chunks with progress
  chunk_size <- 1024 * 1024  # 1MB chunks
  total_read <- 0

  tryCatch({
    repeat {
      data <- readBin(con, "raw", n = chunk_size)
      if (length(data) == 0) break
      writeBin(data, output)
      total_read <- total_read + length(data)

      # Update progress bar
      progress_bar(total_read, file_size)
    }

    message("Download complete!")
  },
  finally = {
    # Always close connections, even on error
    close(con)
    close(output)
  })

  return(invisible(dest_file))
}

shared_link <- "https://icesit.sharepoint.com/:u:/g/Efh5rtBiIhFPsnFcWXH-khYBKRBEHkEDjLHh4OFrMX68Vw?e=cubybi&download=1"
local_path <- "hab_and_bathy_layers.zip"
download_large_file(shared_link, local_path, 1227481372)
unzip(zipfile = "hab_and_bathy_layers.zip", overwrite = TRUE, exdir = ".")

s2_state <- sf::sf_use_s2()
sf::sf_use_s2(FALSE)
eusm <-
  "eusm.rds" |> readRDS() |>
  sf::st_transform(crs = 4326)
eusm |>
  sf::write_sf("/home/hafri/einarhj/public_html/data/eusm.gpkg")
eusm |>
  filter(MSFD_BBHT != "") |>
  sf::write_sf("/home/hafri/einarhj/public_html/data/eusm_filtered.gpkg")

depth <-
  "ICES_GEBCO.rds" |> readRDS() |>
  sf::st_set_crs(value = 4326)

depth |>
  sf::write_sf("/home/hafri/einarhj/public_html/data/gebco_ices.gpkg")

# Download the VMStools .tar.gz file from GitHub
url <- "https://github.com/nielshintzen/vmstools/releases/download/0.77/vmstools_0.77.tar.gz"
download.file(url, destfile = "vmstools_0.77.tar.gz", mode = "wb")
# Install the library from the downloaded .tar.gz file
install.packages("vmstools_0.77.tar.gz", repos = NULL, type = "source")
# Clean up by removing the downloaded file
unlink("vmstools_0.77.tar.gz")
library(vmstools)
data("ICESareas")
ICESareas |>
  sf::write_sf("/home/hafri/einarhj/public_html/data/ices_areas.gpkg")

# simplify shapes --------------------------------------------------------------
sf::sf_use_s2(TRUE)
library(sf)
library(tidyverse)
library(rmapshaper)
library(mapview)
areas <-
  read_sf("/home/hafri/einarhj/public_html/data/ices_areas.gpkg")
simplified <- st_simplify(st_union(areas),
                          dTolerance = 100,
                          preserveTopology = TRUE)
lobstr::obj_size(areas)
lobstr::obj_size(simplified)
simplified <-
  tibble(geom = simplified |> st_cast("POLYGON")) |>
  st_as_sf() |>
  mutate(size = st_area(geom)) |>
  filter(size == max(size)) |>
  select(-size)
mapview(simplified)
lobstr::obj_size(simplified)
simplified |>
  sf::write_sf("/home/hafri/einarhj/public_html/data/ices_areas_simplified.gpkg")
