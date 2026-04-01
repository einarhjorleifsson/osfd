
<!-- README.md is generated from README.Rmd. Please edit that file -->

# osfd

<!-- badges: start -->

<!-- badges: end -->

{**osfd**} (or: “oh yet another, spatial fisheries data package”)
consolidates the ICES WGSFD VMS and logbook datacall workflow into a
properly documented, testable package. A junk drawer, finally organised
into labelled boxes — and then organised again, because the first
attempt was also a junk drawer.

All exported functions carry an `fd_` prefix (fisheries data, or fishy
data — you decide). The package covers the QC preprocessing and analysis
pipeline of the ICES VMS/logbooks data-call: QC and cleaning (Phase 1),
trip linking, activity classification, landings distribution, swept
area, and effort and catch enrichment (Phase 2).

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

Here load the needed libraries and create some temporary demo data. We
are going to store them in directory “\_garbage”, set that up manually a
priori.

``` r
# library(conflicted).  # don't ever use this again
library(sf)
library(nanoparquet)
library(tidyverse)
library(osfd)
library(vmstools)
```

``` r
harbours_nw <- 
  read_sf("~/Documents/stasi/fishydata/data/ports/ports_iceland_faroe.gpkg")
```

## Preprocessing

Here we work with Icelandic dataset that has been painfully converted to
the EFLALO2 and TACSAT2 format.

### Data setup

``` r
eflalo <- "data-raw/eflalo_IS.parquet" |>  
  read_parquet() |> 
  # osfd::eflalo |> 
  fd_clean_eflalo()
tacsat <- 
  "data-raw/tacsat_IS.parquet" |> 
  read_parquet() |> 
  #osfd::tacsat |> 
  fd_clean_tacsat()

# Tidy alternative
trips <- eflalo |> 
  fd_trips()
events <- eflalo |> 
  fd_events()  
```

### Data checks

``` r
# Classical
eflalo_classic <- eflalo |> 
  fd_flag_eflalo()
eflalo_classic |> count(.checks, name = "records") |> knitr::kable(caption = "Eflalo QC: Data checks")
```

| .checks                        | records |
|:-------------------------------|--------:|
| 03 new years trip              |      54 |
| 04 departure after arrival     |      17 |
| 06 overlapping trips           |     143 |
| 08 metier 6 invalid            |     234 |
| 09 catch date before departure |      33 |
| 10 catch date after arrival    |     422 |
| ok                             |    8971 |

Eflalo QC: Data checks

``` r
# Tidy
trips <- trips |> 
  fd_flag_trips()
trips |> count(.tchecks, name = "trips") |> knitr::kable(caption = "Trips QC: Data checks")
```

| .tchecks                                    | trips |
|:--------------------------------------------|------:|
| 03 departure after arrival                  |     1 |
| 04 previous arrival after current departure |     2 |
| 05 next departure before current arrival    |     3 |
| 05 no vessel length                         |     1 |
| ok                                          |   107 |

Trips QC: Data checks

``` r
events <- events |> 
  fd_flag_events()
events |> count(.echecks, name = "events") |> knitr::kable(caption = "Events QC: Data checks")
```

| .echecks            | events |
|:--------------------|-------:|
| 03 metier 6 invalid |    234 |
| ok                  |   9640 |

Events QC: Data checks

``` r

# the good boy
tacsat <- tacsat |> 
  fd_flag_tacsat()
tacsat |> count(.checks, name = "pings") |> knitr::kable(caption = "Trail QC: Data checks")
```

| .checks                     |  pings |
|:----------------------------|-------:|
| 01 point out of (ices) area | 102666 |
| 02 duplicate                |  14420 |
| 03 time interval too short  |  32265 |
| ok                          | 566732 |

Trail QC: Data checks

### Filtering

- Objective: Pass data to the next step (analysis)
- Two alternative (I am “thinking” which would be less painful,
  coding-wise):
  - Use the classical approach
  - Use the tidy approach

``` r
# Classical
eflalo_dropped <- eflalo_classic |> 
  filter(.checks != "ok")
eflalo_classic <- eflalo_classic |> 
  filter(.checks == "ok") |> 
  select(.checks)
# Side-step: Possibly for diagnostics/comparison between classical/tidy
eflalo_alt <-     # name it this rather than tidy - because once joined the table is again non-tidy
  trips |> 
  filter(.tchecks == "ok") |> 
  inner_join(events |> 
              filter(.echecks == "ok"))
# Tidy
trips <- trips |> 
  filter(.tchecks == "ok") |> 
  select(-.tchecks)
events <- events |> 
  filter(.echecks == "ok") |> 
  select(-.echecks)

# same as usual
tacsat <- tacsat |> 
  filter(.checks == "ok") |> 
  select(-.checks)
  
```

## Analysis

… pending, but want to get Preprocessing right from start (although that
may have to be revisited

## License

CC BY 4.0
