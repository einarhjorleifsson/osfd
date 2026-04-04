# Suppress R CMD CHECK false positives for data.table column names used in
# NSE expressions, and other symbols that are legitimately not global functions.
utils::globalVariables(c(
  "FT_DDAT", "FT_DTIME", "FT_LDAT", "FT_LTIME",
  "FT_DDATIM", "FT_LDATIM",
  "FT_REF", "LE_CDAT", "SI_DATE", "SI_DATIM", "SI_TIME", "VE_COU", "VE_KW",
  "VE_LEN", "VE_REF", "VE_TON",
  "SI_HE", "SI_LATI", "SI_LONG", "SI_SP",
  ".in", ".in_harbour", ".intv", "harbours", "ices_areas",
  "LE_EFF_VMS", "LE_ID", "sid",
  ".data", ".n_pings", "EURO", "ICESrectangle", "KG", "LE_CDATIM", "LE_EURO_TOT",
  "LE_KG_TOT",
  "euro", "kg",
  "FT_DCOU", "FT_DHAR", "FT_LCOU", "FT_LHAR", "VE_FLT",
  ".checks", ".overlap",
  ".tid", ".eid", ".echecks", ".tchecks", ".tid",
  ".t1_str", ".t2_str", "LE_STIME",
  "derived", "dictionary", "field", "required", "type",
  ".sid", "T1", "T2", "cid", "cid1", "cid2", "eid", "flt", "gt", "hid1", "hid2",
  "kw", "old", "tid", "time", "vid",
  "LE_ETIME", "lid",
  ".prev_max_t2", "t1", "t2",
  "dictionary", "lat", "lon", "events",
  "s1", "s2"
  ))

