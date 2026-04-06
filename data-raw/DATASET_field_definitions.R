## Field definitions for TACSAT2 and EFLALO2
##
## Source: ICES VMS and Logbook Data-Call format specification
##         (documentations/2026_ices-datacall/.../b_EFLALO & TACSAT Formats.md)
## Derived columns: as produced by fd_clean_tacsat() / fd_clean_eflalo()
##
## Columns:
##   old         Variable name (was "type")
##   table       "tacsat", "eflalo", or "both"
##   type        R type after import / cleaning (chr, dbl, int, dttm, date, lgl)
##   format      Expected raw format (before fd_clean_*)
##   description Short description
##   required    Is the field required by fd_clean_* / the data-call?
##   derived     TRUE = added/transformed by fd_clean_*; FALSE = present in raw file
##.  new         Alternative variable name

fd_dictionary <- tibble::tribble(

  # ── TACSAT raw fields ────────────────────────────────────────────────────────
  ~old,       ~table,    ~type,   ~format,          ~description,                          ~required, ~derived, ~new,
  "VE_COU",     "tacsat",  "chr",   "ISO 3166-1 a-3", "Vessel flag country",                 TRUE,      FALSE,    "cid",
  "VE_REF",     "tacsat",  "chr",   "≤20 characters", "Vessel identifier",                   TRUE,      FALSE,    "vid",
  "SI_DATE",    "tacsat",  "chr",   "DD/MM/YYYY",     "Ping date",                           TRUE,      FALSE,    "SI_DATE",
  "SI_TIME",    "tacsat",  "chr",   "HH:MM (UTC)",    "Ping time (UTC)",                     TRUE,      FALSE,    "SI_TIME",
  "SI_LATI",    "tacsat",  "dbl",   "Decimal degrees","Latitude",                            TRUE,      FALSE,    "lat",
  "SI_LONG",    "tacsat",  "dbl",   "Decimal degrees","Longitude",                           TRUE,      FALSE,    "lon",
  "SI_SP",      "tacsat",  "dbl",   "Knots",          "Instantaneous speed",                 TRUE,      FALSE,    "speed",
  "SI_HE",      "tacsat",  "dbl",   "Degrees (0–360)","Instantaneous heading",               TRUE,      FALSE,    "heading",

  # ── TACSAT derived fields (fd_clean_tacsat) ──────────────────────────────────
  ".pid",       "tacsat",  "int",   NA,               "Row identifier (added by fd_clean_tacsat)",        TRUE,  TRUE,  ".pid",
  "SI_DATIM",   "tacsat",  "dttm",  NA,               "Ping datetime (UTC), parsed from SI_DATE + SI_TIME", TRUE, TRUE, "time",

  # ── EFLALO vessel fields ─────────────────────────────────────────────────────
  "VE_REF",     "eflalo",  "chr",   "≤20 characters", "Vessel identifier",                   TRUE,      FALSE,  "vid",
  "VE_FLT",     "eflalo",  "chr",   "DCF fleet code", "Fleet segment",                       TRUE,      FALSE,  "flt",
  "VE_COU",     "eflalo",  "chr",   "ISO 3166-1 a-3", "Vessel flag country",                 TRUE,      FALSE,  "cid",
  "VE_LEN",     "eflalo",  "dbl",   "Metres (OAL)",   "Vessel overall length",               TRUE,      FALSE,  "length",
  "VE_KW",      "eflalo",  "dbl",   "kW",             "Engine power",                        TRUE,      FALSE,  "kw",
  "VE_TON",     "eflalo",  "dbl",   "GT",             "Vessel tonnage (optional)",           FALSE,     FALSE,  "gt",

  # ── EFLALO fishing trip fields ───────────────────────────────────────────────
  "FT_REF",     "eflalo",  "chr",   "≤20 characters", "Fishing trip reference number",       TRUE,      FALSE,  "tid",
  "FT_DCOU",    "eflalo",  "chr",   "ISO 3166-1 a-3", "Departure country",                   TRUE,      FALSE,  "cid1",
  "FT_DHAR",    "eflalo",  "chr",   "UN LOCODE",      "Departure harbour",                   TRUE,      FALSE,  "hid1",
  "FT_DDAT",    "eflalo",  "chr",   "DD/MM/YYYY",     "Departure date",                      TRUE,      FALSE,  "FT_DDAT",
  "FT_DTIME",   "eflalo",  "chr",   "HH:MM",          "Departure time (UTC)",                TRUE,      FALSE,  "FT_DTIME",
  "FT_LCOU",    "eflalo",  "chr",   "ISO 3166-1 a-3", "Landing country",                     TRUE,      FALSE,  "cid2",
  "FT_LHAR",    "eflalo",  "chr",   "UN LOCODE",      "Landing harbour",                     TRUE,      FALSE,  "hid2",
  "FT_LDAT",    "eflalo",  "chr",   "DD/MM/YYYY",     "Landing (arrival) date",              TRUE,      FALSE,  "FT_LDAT",
  "FT_LTIME",   "eflalo",  "chr",   "HH:MM",          "Landing (arrival) time (UTC)",        TRUE,      FALSE,  "FT_LTIME",

  # ── EFLALO log event fields ──────────────────────────────────────────────────
  "LE_ID",      "eflalo",  "chr",   "≤25 characters", "Log event identifier",                TRUE,      FALSE,   "lid",
  "LE_CDAT",    "eflalo",  "date",  "DD/MM/YYYY",     "Catch date (coerced to Date by fd_clean_eflalo)", TRUE, FALSE, "date",
  "LE_STIME",   "eflalo",  "chr",   "HH:MM",          "Log event start time (optional)",     FALSE,     FALSE,   "LE_STIME",
  "LE_ETIME",   "eflalo",  "chr",   "HH:MM",          "Log event end time (optional)",       FALSE,     FALSE,   "LE_ETIME",
  "LE_SLAT",    "eflalo",  "dbl",   "Decimal degrees","Log event start latitude (optional)", FALSE,     FALSE,   "lat1",
  "LE_SLON",    "eflalo",  "dbl",   "Decimal degrees","Log event start longitude (optional)",FALSE,     FALSE,   "lon1",
  "LE_ELAT",    "eflalo",  "dbl",   "Decimal degrees","Log event end latitude (optional)",   FALSE,     FALSE,   "lat2",
  "LE_ELON",    "eflalo",  "dbl",   "Decimal degrees","Log event end longitude (optional)",  FALSE,     FALSE,   "lon2",
  "LE_GEAR",    "eflalo",  "chr",   "3 characters",   "Gear code (DCF metier level 4)",      TRUE,      FALSE,   "gear",
  "LE_MSZ",     "eflalo",  "dbl",   "mm (stretched)", "Mesh size",                           TRUE,      FALSE,   "mesh",
  "LE_RECT",    "eflalo",  "chr",   "e.g. '37F5'",    "ICES statistical rectangle",          TRUE,      FALSE,   "ir",
  "LE_DIV",     "eflalo",  "chr",   "≤10 characters", "ICES division",                       TRUE,      FALSE,   "fao",
  "LE_MET",     "eflalo",  "chr",   "DCF metier L6",  "Fishing activity (metier level 6)",   TRUE,      FALSE,   "met6",
  "LE_KG_<SP>", "eflalo",  "dbl",   "kg",             "Landing weight per species (one column per species)", FALSE, FALSE, "LE_KG_<SP>",
  "LE_EURO_<SP>","eflalo", "dbl",   "EUR",            "Landing value per species (one column per species)",  FALSE, FALSE, "LE_EURO_<SP>",

  # ── EFLALO derived fields (fd_clean_eflalo) ──────────────────────────────────
  ".tid",       "eflalo",  "int",   NA,               "Trip identifier via consecutive_id() on trip-defining columns",   TRUE,  TRUE, ".tid",
  ".eid",       "eflalo",  "int",   NA,               "Row identifier (added by fd_clean_eflalo)",                       TRUE,  TRUE, ".eid",
  "FT_DDATIM",  "eflalo",  "dttm",  NA,               "Trip departure datetime (UTC), parsed from FT_DDAT + FT_DTIME",   TRUE,  TRUE, "T1",
  "FT_LDATIM",  "eflalo",  "dttm",  NA,               "Trip landing datetime (UTC), parsed from FT_LDAT + FT_LTIME",     TRUE,  TRUE, "T2",
  "t1",         "eflalo",  "dttm",  NA,               "Event start datetime (UTC), derived from LE_CDAT + LE_STIME",     FALSE, TRUE, "t1",
  "t2",         "eflalo",  "dttm",  NA,               "Event end datetime (UTC), derived from LE_CDAT + LE_ETIME",       FALSE, TRUE, "t2",
  ".tsrc",      "eflalo",  "chr",   NA,               "Derivation source for t1/t2: 'data', 'next day', 'dummy', or NA", FALSE, TRUE, ".tsrc"

)

usethis::use_data(fd_dictionary, overwrite = TRUE)
