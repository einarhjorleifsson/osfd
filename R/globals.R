# Suppress R CMD CHECK false positives for data.table column names used in
# NSE expressions, and other symbols that are legitimately not global functions.
utils::globalVariables(c(
  "FT_DDAT", "FT_DDATIM", "FT_DTIME", "FT_LDAT", "FT_LDATIM", "FT_LTIME",
  "FT_REF", "LE_CDAT", "SI_DATE", "SI_DATIM", "SI_TIME", "VE_COU", "VE_KW",
  "VE_LEN", "VE_REF", "VE_TON"
  ))

