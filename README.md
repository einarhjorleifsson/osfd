
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

Here load the needed libraries and load data.

``` r
library(sf)
library(arrow)
library(tidyverse)
library(osfd)
```

``` r
ports  <- "https://heima.hafro.is/~einarhj/data/ports_iceland_faroe.gpkg" |> 
  read_sf() |> 
  select(port = pid)
areas <- read_sf("data-raw/ices_areas.gpkg") |> 
  select(area = Area_27)
depth <- read_sf("data-raw/gebco_ices.gpkg")
eusm  <- read_sf("data-raw/eusm.gpkg") |> # criminal size: ~120 million points!
  filter(MSFD_BBHT != "")
```

``` r
eflalo       <- "https://heima.hafro.is/~einarhj/data/eflalo_IS.parquet" |> 
  arrow::read_parquet()
tacsat       <- "https://heima.hafro.is/~einarhj/data/tacsat_IS.parquet" |> 
  arrow::read_parquet()
# fishing speed by gear and target
state_lookup <- "https://heima.hafro.is/~einarhj/data/gear_mapping.parquet" |> 
  arrow::read_parquet() |> 
  select(gear, target, s1, s2)
benthis_lookup <- fd_benthis_lookup()
```

## Pre-processing

… text is pending, but here is an illustration of user code flow to
complete the task.

``` r
ais <- tacsat |> 
  fd_clean_tacsat() |> 
  fd_flag_tacsat(no_hands = TRUE,
                 minimum_interval_seconds = 30, 
                 areas = areas, ports = ports)

eflalo_clean <- eflalo |> fd_clean_eflalo()

trips <- eflalo_clean |> 
  fd_trips() |> 
  fd_flag_trips(no_hands = TRUE)

events <- eflalo_clean |>
  fd_events() |> 
  fd_flag_events(
    no_hands = TRUE,
    gear = icesVocab::getCodeList("GearType")$Key,
    met6 = icesVocab::getCodeList("Metier6_FishingActivity")$Key)
```

## Processing

A little peek-a-boo, … not run, only partially ready

``` r
ais2 <- ais |> 
  fd_add_trips(trips, cn = c("tid", "length", "kw", "gt", ".tid")) |> 
  # some monkey-buissness - run fd_check_events_join(ais2, events) to see issues
  fd_add_events(events, resolve = TRUE) |> 
  # here the second intv call is made
  group_by(.tid) |> 
  mutate(dt_sec = fd_interval_seconds(time),
         kwh <- kw * dt_sec / 60^2) |> 
  ungroup() |> 
  fd_add_state(state_lookup) |> 
  filter(state == "fishing") |> 
  # fd_add_catch(events) |>                # pending, resolve fd_add_events first
  fd_add_sf(eusm) |> 
  fd_add_sf(depth) |> 
  mutate(csq = fd_calc_csq(lon, lat)) #|>
# fd_add_gearwith(gear_width_table) |>   # pending
# fd_calc_sa()                           # pending
```

## Submission

More peek-a-boo, … not run, not ready

``` r
# ... pending
ais3 <- ais2 |> 
  fd_final_tests() 
ais3 |> fd_aggregate() |> fd_export_table1()
ais3 |> fd_aggregate() |> fd_export_table2()
```

## Some testing

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

## Small print

``` r
devtools::session_info()
#> ─ Session info ───────────────────────────────────────────────────────────────
#>  setting  value
#>  version  R version 4.5.2 (2025-10-31)
#>  os       macOS Tahoe 26.3.1
#>  system   aarch64, darwin20
#>  ui       X11
#>  language (EN)
#>  collate  en_US.UTF-8
#>  ctype    en_US.UTF-8
#>  tz       Atlantic/Reykjavik
#>  date     2026-04-06
#>  pandoc   3.9.0.2 @ /opt/homebrew/bin/ (via rmarkdown)
#>  quarto   1.8.26 @ /usr/local/bin/quarto
#> 
#> ─ Packages ───────────────────────────────────────────────────────────────────
#>  package        * version    date (UTC) lib source
#>  arrow          * 23.0.1.1   2026-02-24 [2] CRAN (R 4.5.2)
#>  askpass          1.2.1      2024-10-04 [2] CRAN (R 4.5.0)
#>  assertthat       0.2.1      2019-03-21 [2] CRAN (R 4.5.0)
#>  backports        1.5.0      2024-05-23 [2] CRAN (R 4.5.0)
#>  base64enc        0.1-6      2026-02-02 [2] CRAN (R 4.5.2)
#>  bit              4.6.0      2025-03-06 [2] CRAN (R 4.5.0)
#>  bit64            4.6.0-1    2025-01-16 [2] CRAN (R 4.5.0)
#>  blob             1.3.0      2026-01-14 [2] CRAN (R 4.5.2)
#>  boot             1.3-32     2025-08-29 [2] CRAN (R 4.5.2)
#>  broom            1.0.12     2026-01-27 [2] CRAN (R 4.5.2)
#>  cachem           1.1.0      2024-05-16 [2] CRAN (R 4.5.0)
#>  chron            2.3-62     2024-12-31 [2] CRAN (R 4.5.0)
#>  class            7.3-23     2025-01-01 [2] CRAN (R 4.5.2)
#>  classInt         0.4-11     2025-01-08 [1] CRAN (R 4.5.0)
#>  cli              3.6.5      2025-04-23 [1] CRAN (R 4.5.0)
#>  colorspace       2.1-2      2025-09-22 [2] CRAN (R 4.5.0)
#>  cowplot          1.2.0      2025-07-07 [2] CRAN (R 4.5.0)
#>  curl             7.0.0      2025-08-19 [2] CRAN (R 4.5.0)
#>  data.table       1.18.2.1   2026-01-27 [2] CRAN (R 4.5.2)
#>  DBI              1.3.0      2026-02-25 [1] CRAN (R 4.5.2)
#>  Deriv            4.2.0      2025-06-20 [2] CRAN (R 4.5.0)
#>  devtools         2.5.0      2026-03-14 [2] CRAN (R 4.5.2)
#>  digest           0.6.39     2025-11-19 [2] CRAN (R 4.5.2)
#>  doBy             4.7.1      2025-12-02 [2] CRAN (R 4.5.2)
#>  dplyr          * 1.2.1      2026-04-03 [1] CRAN (R 4.5.2)
#>  e1071            1.7-17     2025-12-18 [1] CRAN (R 4.5.2)
#>  ellipsis         0.3.2      2021-04-29 [2] CRAN (R 4.5.0)
#>  evaluate         1.0.5      2025-08-27 [2] CRAN (R 4.5.0)
#>  farver           2.1.2      2024-05-13 [2] CRAN (R 4.5.0)
#>  fastmap          1.2.0      2024-05-15 [2] CRAN (R 4.5.0)
#>  forcats        * 1.0.1      2025-09-25 [2] CRAN (R 4.5.0)
#>  forecast         9.0.2      2026-03-18 [2] CRAN (R 4.5.2)
#>  fracdiff         1.5-3      2024-02-01 [2] CRAN (R 4.5.0)
#>  fs               1.6.7      2026-03-06 [2] CRAN (R 4.5.2)
#>  generics         0.1.4      2025-05-09 [1] CRAN (R 4.5.0)
#>  ggplot2        * 4.0.2      2026-02-03 [2] CRAN (R 4.5.2)
#>  glue             1.8.0      2024-09-30 [1] CRAN (R 4.5.0)
#>  gsubfn           0.7        2018-03-16 [2] CRAN (R 4.5.0)
#>  gtable           0.3.6      2024-10-25 [2] CRAN (R 4.5.0)
#>  hms              1.1.4      2025-10-17 [2] CRAN (R 4.5.0)
#>  htmltools        0.5.9      2025-12-04 [2] CRAN (R 4.5.2)
#>  htmlwidgets      1.6.4      2023-12-06 [2] CRAN (R 4.5.0)
#>  httr             1.4.8      2026-02-13 [2] CRAN (R 4.5.2)
#>  icesConnect      1.1.4      2025-04-30 [2] CRAN (R 4.5.0)
#>  icesDatsu        1.2.1      2025-05-02 [2] https://ices-tools-prod.r-universe.dev (R 4.5.2)
#>  icesDatsuQC      1.2.0      2024-10-26 [2] https://ices-tools-prod.r-universe.dev (R 4.5.3)
#>  icesVMS          1.1.6      2026-03-27 [2] Github (ices-tools-prod/icesVMS@fae2845)
#>  icesVocab        1.3.2      2025-05-26 [2] CRAN (R 4.5.0)
#>  jsonlite         2.0.0      2025-03-27 [2] CRAN (R 4.5.0)
#>  kernlab          0.9-33     2024-08-13 [2] CRAN (R 4.5.0)
#>  KernSmooth       2.23-26    2025-01-01 [2] CRAN (R 4.5.2)
#>  knitr            1.51       2025-12-20 [2] CRAN (R 4.5.2)
#>  lattice          0.22-9     2026-02-09 [2] CRAN (R 4.5.2)
#>  lazyeval         0.2.2      2019-03-15 [2] CRAN (R 4.5.0)
#>  lifecycle        1.0.5      2026-01-08 [1] CRAN (R 4.5.2)
#>  lubridate      * 1.9.5      2026-02-04 [1] CRAN (R 4.5.2)
#>  magrittr         2.0.5      2026-04-04 [1] CRAN (R 4.5.2)
#>  MASS             7.3-65     2025-02-28 [2] CRAN (R 4.5.2)
#>  Matrix           1.7-5      2026-03-21 [2] CRAN (R 4.5.2)
#>  memoise          2.0.1      2021-11-26 [2] CRAN (R 4.5.0)
#>  microbenchmark   1.5.0      2024-09-04 [2] CRAN (R 4.5.0)
#>  mixtools         2.0.0.1    2025-03-08 [2] CRAN (R 4.5.0)
#>  modelr           0.1.11     2023-03-22 [2] CRAN (R 4.5.0)
#>  nlme             3.1-168    2025-03-31 [2] CRAN (R 4.5.2)
#>  osfd           * 0.0.0.9000 2026-04-06 [1] local
#>  otel             0.2.0      2025-08-29 [2] CRAN (R 4.5.0)
#>  pillar           1.11.1     2025-09-17 [1] CRAN (R 4.5.0)
#>  pkgbuild         1.4.8      2025-05-26 [2] CRAN (R 4.5.0)
#>  pkgconfig        2.0.3      2019-09-22 [1] CRAN (R 4.5.0)
#>  pkgload          1.5.0      2026-02-03 [2] CRAN (R 4.5.2)
#>  plotly           4.12.0     2026-01-24 [2] CRAN (R 4.5.2)
#>  proto            1.0.0      2016-10-29 [2] CRAN (R 4.5.0)
#>  proxy            0.4-29     2025-12-29 [1] CRAN (R 4.5.2)
#>  purrr          * 1.2.1      2026-01-09 [1] CRAN (R 4.5.2)
#>  R6               2.6.1      2025-02-15 [1] CRAN (R 4.5.0)
#>  RColorBrewer     1.1-3      2022-04-03 [2] CRAN (R 4.5.0)
#>  Rcpp             1.1.1      2026-01-10 [1] CRAN (R 4.5.2)
#>  readr          * 2.2.0      2026-02-19 [2] CRAN (R 4.5.2)
#>  rlang            1.1.7      2026-01-09 [1] CRAN (R 4.5.2)
#>  rmarkdown        2.30       2025-09-28 [2] CRAN (R 4.5.0)
#>  RSQLite          2.4.6      2026-02-06 [2] CRAN (R 4.5.2)
#>  rstudioapi       0.18.0     2026-01-16 [2] CRAN (R 4.5.2)
#>  s2               1.1.9      2025-05-23 [1] CRAN (R 4.5.0)
#>  S7               0.2.1      2025-11-14 [2] CRAN (R 4.5.2)
#>  scales           1.4.0      2025-04-24 [2] CRAN (R 4.5.0)
#>  segmented        2.2-1      2026-01-29 [2] CRAN (R 4.5.2)
#>  sessioninfo      1.2.3      2025-02-05 [2] CRAN (R 4.5.0)
#>  sf             * 1.1-0      2026-02-24 [1] CRAN (R 4.5.2)
#>  sqldf            0.4-12     2026-01-30 [2] CRAN (R 4.5.2)
#>  stringi          1.8.7      2025-03-27 [1] CRAN (R 4.5.0)
#>  stringr        * 1.6.0      2025-11-04 [1] CRAN (R 4.5.0)
#>  survival         3.8-6      2026-01-16 [2] CRAN (R 4.5.2)
#>  tibble         * 3.3.1      2026-01-11 [1] CRAN (R 4.5.2)
#>  tidyr          * 1.3.2      2025-12-19 [1] CRAN (R 4.5.2)
#>  tidyselect       1.2.1      2024-03-11 [1] CRAN (R 4.5.0)
#>  tidyverse      * 2.0.0      2023-02-22 [2] CRAN (R 4.5.0)
#>  timechange       0.4.0      2026-01-29 [1] CRAN (R 4.5.2)
#>  timeDate         4052.112   2026-01-28 [2] CRAN (R 4.5.2)
#>  tzdb             0.5.0      2025-03-15 [2] CRAN (R 4.5.0)
#>  units            1.0-1      2026-03-11 [1] CRAN (R 4.5.2)
#>  urca             1.3-4      2024-05-27 [2] CRAN (R 4.5.0)
#>  usethis          3.2.1      2025-09-06 [2] CRAN (R 4.5.0)
#>  vctrs            0.7.2      2026-03-21 [1] CRAN (R 4.5.2)
#>  viridisLite      0.4.3      2026-02-04 [2] CRAN (R 4.5.2)
#>  vmstools         0.77       2026-03-26 [2] local (/Users/einarhj/Documents/stasi/fishydata/vmstools_0.77.tar.gz)
#>  withr            3.0.2      2024-10-28 [1] CRAN (R 4.5.0)
#>  wk               0.9.5      2025-12-18 [1] CRAN (R 4.5.2)
#>  xfun             0.57       2026-03-20 [2] CRAN (R 4.5.2)
#>  yaml             2.3.12     2025-12-10 [2] CRAN (R 4.5.2)
#>  zoo              1.8-15     2025-12-15 [2] CRAN (R 4.5.2)
#> 
#>  [1] /private/var/folders/14/1_h9q5hn2h93byhrkzp8jfj00000gp/T/Rtmpl0Lpv2/temp_libpath58cb1188c4b3
#>  [2] /Library/Frameworks/R.framework/Versions/4.5-arm64/Resources/library
#>  * ── Packages attached to the search path.
#> 
#> ──────────────────────────────────────────────────────────────────────────────
```

## License

CC BY 4.0
