# On gears
#  The primary gear code used in the ais/vms analysis is that reported in the
#  gafl/landings database.
#
# TODO:
#  * Add criterion for maximum duration
#  * Add criterion for maximum distance

library(tidyverse)

# create table -----------------------------------------------------------------

gear_mapping <-
  tribble(~agf_gid, ~veiðarfæri, ~gear, ~target, ~met5,   ~met6,                 ~s1,  ~s2,   ~orri,
          1,   "Skötuselsnet",  "GNS", "DEF", "GNS_DEF", "GNS_DEF_>0_0_0",      0.000, 2.500,     91,
          2,   "Þorskfisknet",  "GNS", "DEF", "GNS_DEF", "GNS_DEF_>0_0_0",      0.000, 1.700,      2,
          3,   "Grásleppunet",  "GNS", "DEF", "GNS_DEF", "GNS_DEF_>0_0_0",      0.000, 1.700,     25,
          4,    "Rauðmaganet",  "GNS", "DEF", "GNS_DEF", "GNS_DEF_>0_0_0",      0.000, 1.700,     29,
          5,         "Reknet",  "GND", "SPF", "GND_SPF", "GND_SPF_>0_0_0",      0.050, 1.125,     11,
          6,      "Botnvarpa",  "OTB", "DEF", "OTB_DEF", "OTB_DEF_>=120_0_0",   2.625, 4.700,      6,
          7,     "Humarvarpa",  "OTB", "CRU", "OTB_CRU", "OTB_CRU_90-99_1_120", 2.375, 3.700,      9,
          8,     "Rækjuvarpa",  "OTB", "CRU", "OTB_CRU", "OTB_CRU_40-54_0_0",   1.750, 3.000,     14,
          9,      "Flotvarpa",  "OTM", "SPF", "OTM_SPF", "OTM_SPF_>0_0_0",      2.625, 6.000,      7,
          10,            "Nót",   "PS", "SPF",  "PS_SPF", "PS_SPF_>0_0_0",       0.000, 1.700,     10,
          11,        "Dragnót",  "SDN", "DEF", "SDN_DEF", "SDN_DEF_>=120_0_0",   0.250, 2.900,      5,
          12,           "Lína",  "LLS", "DEF", "LLS_DEF", "LLS_DEF_0_0_0",       0.375, 2.750,      1,
          13, "Landbeitt lína",  "LLS", "DEF", "LLS_DEF", "LLS_DEF_0_0_0",       0.375, 2.750,     72,
          14,       "Handfæri",  "LHM", "DEF", "LHM_DEF", "LHM_DEF_0_0_0",       0.025, 1.700,      3,
          15,         "Plógur",  "DRB", "DES", "DRB_DES", "DRB_DES_>0_0_0",      1.200, 2.900,     15,
          16,         "Gildra",  "FPO", "DEF", "FPO_DEF", "FPO_DEF_>0_0_0",      0.100, 2.000,     16,
          17,   "Annað - Hvað",  "MIS", "DWF", "MIS_DWF", "MIS_DWF_0_0_0",          NA,    NA,     99,
          18,       "Eldiskví",     NA,    NA,        NA,              NA,          NA,    NA,     NA,
          19,       "Sjóstöng",  "LHP", "FIF", "LHP_FIF", "LHP_FIF_0_0_0",       0.125, 1.250,     43,
          20,  "Kræklingalína",     NA,    NA,        NA,              NA,          NA,    NA,     42,
          21,      "Línutrekt",  "LLS", "DEF", "LLS_DEF", "LLS_DEF_0_0_0",       0.100, 2.200,      1,
          22,     "Grálúðunet",  "GNS", "DEF", "GNS_DEF", "GNS_DEF_>0_0_0",      0.050, 1.400,     92,
          23,         "Kafari",  "DIV", "DES", "DIV_DES", "DIV_DES_0_0_0",          NA,    NA,     41,
          24,   "Sláttuprammi",  "HMS", "SWD", "HMS_SWD", "HMS_SWD_0_0_0",       0.000, 1.400,     NA,
          25,     "Þaraplógur",  "HMS", "SWD", "HMS_SWD", "HMS_SWD_0_0_0",       2.300, 4.000,     NA) |>
  mutate(agf_gid = as.integer(agf_gid),
         orri = as.integer(orri))

# check validity ---------------------------------------------------------------
library(ramb)
gear_mapping |>
  filter(!is.na(met6)) |>
  mutate(gear2 = rb_gear_from_metier(met6),
         target2 = rb_target_from_metier(met6),
         met52 = rb_met5_from6(met6)) |>
  filter(gear != gear2 | target != target2 | met5 != met52) |>
  knitr::kable(caption = "Expect none")
gear_mapping |>
  filter(!is.na(gear)) |>
  mutate(
    v_gear =
      case_when(gear %in% icesVocab::getCodeList("GearType")$Key ~ TRUE,
                .default = FALSE),
    v_target =
      case_when(target %in% icesVocab::getCodeList("TargetAssemblage")$Key ~ TRUE,
                .default = FALSE),
    v_met5 =
      case_when(met5 %in% icesVocab::getCodeList("Metier5_FishingActivity")$Key ~ TRUE,
                .default = FALSE),
    v_met6 =
      case_when(met6 %in% icesVocab::getCodeList("Metier6_FishingActivity")$Key ~ TRUE,
                .default = FALSE)
  ) |>
  filter(!v_gear | !v_target | !v_met5 | !v_met6) |>
  knitr::kable(caption = "Problems with gear and target not in ICES vocabulary, but met5 and met6 considered valid.")

gear_mapping |>
  nanoparquet::write_parquet("/home/hafri/einarhj/public_html/data/gear_mapping.parquet")
