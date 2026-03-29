
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
data — you decide). The package covers the full preprocessing and
analysis pipeline: QC and cleaning (Phase 2), trip linking, activity
classification, landings distribution, swept area, and effort enrichment
(Phase 3).

## Installation

``` r
# install.packages("pak")
pak::pak("einarhjorleifsson/osfd")
```

Some dependencies are not on CRAN and come from the ICES r-universe:

``` r
install.packages(
  c("sfdSAR", "icesVMS", "icesVocab", "icesConnect"),
  repos = "https://ices-tools-prod.r-universe.dev"
)
```

## Quick start

The package ships with demo `eflalo` and `tacsat` datasets. A sketch of
the full pipeline:

``` r
library(duckdbfs)
library(nanoparquet)
library(osfd)
library(dplyr)
library(stringr)
library(lubridate)

# --- Write demo data to disk (parquet, one file per year) ---------------------
osfd::eflalo |>
  mutate(year = as.integer(year(dmy(FT_DDAT)))) |> 
  group_by(year) |> 
  write_dataset("_garbage/eflalo")
osfd::tacsat |>
  mutate(year = as.integer(year(dmy(SI_DATE)))) |> 
  group_by(year) |> 
  write_dataset("_garbage/tacsat")

# --- Preprocessing -----------------------------------------------------------
eflalo <- read_parquet("_garbage/eflalo/year=1803/data_0.parquet")
tacsat <- read_parquet("_garbage/tacsat/year=1803/data_0.parquet")

# Coerce columns and parse datetimes
eflalo <- fd_setup_eflalo(eflalo)
tacsat <- fd_setup_tacsat(tacsat)

# Single-pass QC (adds a `checks` column; caller decides what to filter)
tacsat <- fd_check_tacsat(tacsat, it_min = 300)
tacsat |> count(checks)
tacsat <- tacsat |> filter(checks == "ok") |> select(-checks)

# Single-pass QC (adds a `checks` column; caller decides what to filter)
eflalo <- fd_eflalo_check(eflalo, year = 1803)
eflalo |> count(checks)
eflalo <- eflalo |> filter(str_starts(checks, "ok - no vessel tonnage")) |> select(-checks)


# --- Analysis ----------------------------------------------------------------
# Assign trip identifiers (and vessel attributes) to pings

# Calculate ping intervals and classify fishing activity
tacsatp <- fd_intv_tacsat(tacsatp, level = "trip", fill.na = TRUE)

# TODO: Set the ping states (fishing or not)
# ...

# Distribute landings among fishing pings


# Gear width and swept area
```

## Datacall flow

This preliminarily placed here, just a bookkeeping of the current
datacall flow with comments if not yet implemented in {osfd}

### Preprocessing

#### tacsat

- 1.2.1 Remove VMS pings outside the ICES areas
  - This can be an expensive process if ais data is rich, because
    dataframe turned to sf, then a join with ices-area shapefile but
    then geometry is droppped. Question for now is if this can be moved
    more downstream, where other spatial acrobatics take place.
  - NOTE: Not yet implemented in {osfd}
- 1.2.2 Remove duplicate records - in osfd::fd_tacsat_check
- 1.2.3 Remove points that have impossible coordinates
  - this is a redundant step, given 1.2.1 above
- 1.2.4 Remove points which are pseudo duplicates as they have an
  interval rate \< x minutes - in osdf:fd_tacsat_check
  - the check function has accepts the minimum interval
- 1.2.5 Remove points in harbour

## Source

Functions are ported from
[ICES-VMS-and-Logbook-Data-Call](https://github.com/ices-eg/ICES-VMS-and-Logbook-Data-Call)
scripts `0_global.R`, `1_eflalo_tacsat_preprocessing.R`, and
`2_eflalo_tacsat_analysis.R`. Modernised script versions using `osfd`
functions are in `inst/scripts/`.

## License

CC BY 4.0
