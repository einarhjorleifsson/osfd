# ICELAND demo -----------------------------------------------------------------
library(duckdbfs)
library(mar)
map <-
  open_dataset("~/stasi/fishydata/data/gear/gear_mapping.parquet") |>
  collect()

con <- connect_mar()
eflalo <-
  les_stod(con) |>
  left_join(les_syni(con)) |>
  filter((synaflokkur_nr %in% c(19, 30, 34, 39, 35, 37, 40, 38, 31) | leidangur == "MP1-2025"),
         ar %in% 2020:2025) |>
  left_join(les_leidangur(con) |> select(leidangur, brottfor, koma)) |>
  left_join(tbl_mar(con, "vessel.vessel_v") |>
              select(skip_nr = registration_no, length, power_kw, brutto_weight_tons)) |>
  collect() |>
  # temporary, will be dropped:
  mutate(gid = veidarfaeri) |>
  mutate(VE_REF = as.character(skip_nr),
         VE_FLT = "dummy",       # needs digging
         VE_COU = "ISL",
         VE_LEN = length,
         VE_KW = power_kw,
         VE_TON = brutto_weight_tons,
         FT_REF = paste0(leidangur, "_", skip_nr),
         FT_DCOU = "ISL",
         FT_DHAR = "dummy",
         FT_DDAT = format(brottfor, "%d/%m/%Y"),
         FT_DTIME = "00:00:01",
         FT_LCOU = "ISL",
         FT_LHAR = "dummy",
         FT_LDAT = format(koma, "%d/%m/%Y"),
         FT_LTIME = "23:59:00",
         LE_ID = paste0(leidangur, "_", skip_nr, "_", stod_id),
         LE_CDAT = format(togbyrjun, "%d/%m/%Y"),
         LE_STIME = format(togbyrjun, "%H:%M"),
         LE_ETIME = format(togendir, "%H:%M"),
         LE_SLAT = kastad_breidd,
         LE_SLON = kastad_lengd,
         LE_ELAT = hift_breidd,
         LE_ELON = hift_lengd,
         LE_GEAR = "dummy",                      # fixed downstream
         LE_MSZ = moskvastaerd,                  # needs digging because of netarall
         LE_RECT = ifelse(is.na(kastad_breidd) & is.na(kastad_breidd), NA, geo::d2ir(kastad_breidd, kastad_breidd)),
         LE_DIV = "dummy",
         LE_MET = case_when(gid ==  1 ~ "LLS_DEF_0_0_0",
                            gid ==  9 ~ "OTB_CRU_90-99_1_120",
                            gid == 14 ~ "OTB_CRU_40-54_0_0",
                            gid == 15 ~ "DRB_DES_>0_0_0",
                            gid == 46 ~ "TBB_DES_>0_0_0",
                            gid == 53 ~ "TBB_DES_>0_0_0",
                            gid == 54 ~ "OTB_CRU_40-54_0_0",
                            gid == 72 ~ "MIS_DWF_0_0_0",
                            gid == 73 ~ "OTB_DEF_>=120_0_0",
                            gid == 77 ~ "OTB_DEF_>=120_0_0",
                            gid == 78 ~ "OTB_DEF_>=120_0_0",
                            gid == 82 ~ "OTM_SPF_>0_0_0",
                            gid == 132 ~ "MIS_DWF_0_0_0",
                            gid == 134 ~ "MIS_DWF_0_0_0",
                            gid == 136 ~ "MIS_DWF_0_0_0",
                            gid == 146 ~ "MIS_DWF_0_0_0",
                            gid == 160 ~ "MIS_DWF_0_0_0",
                            gid == 186 ~ "MIS_DWF_0_0_0",
                            gid == 312 ~ "MIS_DWF_0_0_0",
                            gid == 712 ~ "GNS_DEF_>0_0_0",
                            gid == 724 ~ "GNS_DEF_>0_0_0",
                            .default = "dummy"),
         LE_UNIT = "KWDAYS",
         LE_EFF = NA_real_,
         LE_EFF_VMS = "dummy",
         LE_KG_TOT = 100,
         LE_EURO_TOT = 1000) |>
  # remove .T1 and .T2 downstream
  select(VE_REF:LE_EURO_TOT, .T1 = brottfor, .T2 = koma) |>
  distinct() |>
  # drop more than one gear used at one event (station)
  #. may though still have more than one gear in a trip
  distinct(LE_ID, .keep_all = TRUE) |>
  mutate(LE_GEAR = str_sub(LE_MET, 1, 3))
eflalo |>
  count(LE_ID) |>
  filter(n > 1) |>
  knitr::kable(caption = "Expect none")
eflalo |> write_dataset("data-raw/eflalo_IS.parquet")
# details <-
#   main |>
#   select(stod_id, synis_id) |>
#   distinct() |>
#   left_join(les_lengd_skalad(con))
tacsat <-
  open_dataset("/u3/geo/fishydata/data/ais/trail") |>
  select(vid, time, lon, lat, speed) |>
  inner_join(open_dataset("data-raw/eflalo_IS.parquet") |>
               mutate(vid = as.numeric(VE_REF)) |>
               select(vid, .T1, .T2) |>
               distinct(),
             by = join_by(vid, between(time, .T1, .T2))) |>
  select(-c(.T1, .T2)) |>
  collect() |>
  mutate(VE_COU = "ISL",
         VE_REF = as.character(vid),
         SI_LATI = lat,
         SI_LONG = lon,
         SI_DATE = format(time, "%d/%m/%Y"),
         SI_TIME = format(time, "%H:%M:%S"),
         SI_SP = speed,
         SI_HE = NA_real_) |>
  select(VE_COU:SI_HE)
tacsat |> nanoparquet::write_parquet("data-raw/tacsat_IS.parquet")
tacsat |> nanoparquet::write_parquet("/home/hafri/einarhj/public_html/data/tacsat_IS.parquet")


eflalo <-
  nanoparquet::read_parquet("data-raw/eflalo_IS.parquet")
eflalo |> select(-c(.T1, .T2)) |> nanoparquet::write_parquet("data-raw/eflalo_IS.parquet")
eflalo |> select(-c(.T1, .T2)) |> nanoparquet::write_parquet("/home/hafri/einarhj/public_html/data/eflalo_IS.parquet")

# final destination is web-page
sf::read_sf("~/Documents/stasi/fishydata/data/ports/ports_iceland_faroe.gpkg") |>
  sf::write_sf("/Volumes/einarhj/ports_iceland_faroe.gpkg")
