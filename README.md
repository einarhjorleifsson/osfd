
<!-- README.md is generated from README.Rmd. Please edit that file -->

# osfd

<!-- badges: start -->

<!-- badges: end -->

{**osfd**} (or: “oh yet another, spatial fisheries data package”)
consolidates the ICES WGSFD VMS and logbook datacall workflow into a
properly documented, testable package.

All exported functions carry an `fd_` prefix (fisheries data, or fishy
data — you decide). The package current versions covers the QC
pre-processing of the ICES VMS/logbooks data-call. Processing functions
are pending.

The process here will definitively **not reproduce** to the full extent
the official [data-call
process](https://github.com/ices-eg/ICES-VMS-and-Logbook-Data-Call).

## Installation

Some dependencies are not on CRAN and come from the ICES r-universe:

``` r
... instructions pending for non-crans
# install.packages("remotes")
remotes::install_github("einarhjorleifsson/osfd")
```

## Setting the stage

Here load the needed libraries and load some demo data that reside on
the web.

``` r
# library(conflicted).  # don't ever use this again
library(sf)
library(arrow)
library(tidyverse)
library(osfd)
library(vmstools)
```

``` r
pth_ports  <- "https://heima.hafro.is/~einarhj/data/ports_iceland_faroe.gpkg"
pth_eflalo <- "https://heima.hafro.is/~einarhj/data/eflalo_IS.parquet"
pth_tacsat <- "https://heima.hafro.is/~einarhj/data/tacsat_IS.parquet"
```

``` r
ports  <- read_sf(pth_ports)
eflalo <- arrow::read_parquet(pth_eflalo)
tacsat <- arrow::read_parquet(pth_tacsat)
```

## Preprocessing

… text is pending, but here is an illustration of user code flow to
complete the task.

``` r
ais <- tacsat |> 
  fd_clean_tacsat() |> 
  fd_flag_tacsat() |> 
  # user interference possible
  filter(.checks == "ok")

trips <- eflalo |> 
  fd_clean_eflalo() |> 
  fd_trips() |> 
  fd_flag_trips() |> 
  # user interference possible
  filter(.tchecks == "ok")

events <- eflalo |>
  fd_clean_eflalo() |> 
  fd_events() |> 
  fd_flag_events() |> 
  # user interference possible
  filter(.echecks == "ok")
```

## Analysis

A little peek-a-boo

### Assigning trips and events to pings

``` r
ais2 <- ais |> 
  fd_add_trips(trips, cn = c("tid", "length", "kw", "gt", ".tid")) |> 
  fd_add_events(events)
```

… before

``` r
# sidestep in order to run datacall way below
e_test <- left_join(trips, events) |> 
  fd_revert_eflalo() |> 
  as.data.frame()
t_test <- ais |> 
  fd_revert_tacsat() |> 
  as.data.frame()

# Datacall way -----------------------------------------------------------------
merged <- vmstools::mergeEflalo2Tacsat(e_test, t_test)
cols <- c("LE_GEAR", "LE_MSZ", "VE_LEN", "VE_KW", "LE_RECT", "LE_MET", "LE_WIDTH", "VE_FLT", "VE_COU")
# Use a loop to add each column
for (col in cols) {
  # Match 'FT_REF' values in 'tacsatp' and 'eflalo' and use these to add the column from 'eflalo' to 'tacsatp'
  merged[[col]] <- e_test[[col]][match(merged$FT_REF, e_test$FT_REF)]
}

# {osfd} way - could be wrapped in a function ----------------------------------
aism <- ais |> 
  left_join(trips,
            by = join_by(cid, vid,
                         between(time, T1, T2)),
            relationship = "many-to-one")
# similarly, wrapped in a function
ais_trips <- ais |> fd_add_trips(trips, cn = c("tid", "length", "kw", "gt", ".tid"))

# comparison -------------------------------------------------------------------
identical(merged$FT_REF, replace_na(aism$tid, "0"))
#> [1] TRUE
```

### Assigning events to pings

``` r
# fd_add_events - not implemented yet
ais_trips_events <- ais_trips |> 
  left_join(events,
            by = join_by(.tid,
                         between(time, t1, t2)),
            relationship = "many-to-one")
```

## License

CC BY 4.0
