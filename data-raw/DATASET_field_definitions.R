## Field definitions for TACSAT2 and EFLALO2
##
## Source: ICES VMS and Logbook Data-Call format specification
##         (documentations/2026_ices-datacall/.../b_EFLALO & TACSAT Formats.md)
## Derived columns: as produced by fd_clean_tacsat() / fd_clean_eflalo()
##
## Columns:
##   field       Variable name
##   table       "tacsat", "eflalo", or "both"
##   type        R type after import / cleaning (chr, dbl, int, dttm, date, lgl)
##   format      Expected raw format (before fd_clean_*)
##   description Short description
##   required    Is the field required by fd_clean_* / the data-call?
##   derived     TRUE = added/transformed by fd_clean_*; FALSE = present in raw file

field_definitions <- tibble::tribble(

  # ── TACSAT raw fields ────────────────────────────────────────────────────────
  ~field,       ~table,    ~type,   ~format,          ~description,                          ~required, ~derived,
  "VE_COU",     "tacsat",  "chr",   "ISO 3166-1 a-3", "Vessel flag country",                 TRUE,      FALSE,
  "VE_REF",     "tacsat",  "chr",   "≤20 characters", "Vessel identifier",                   TRUE,      FALSE,
  "SI_DATE",    "tacsat",  "chr",   "DD/MM/YYYY",     "Ping date",                           TRUE,      FALSE,
  "SI_TIME",    "tacsat",  "chr",   "HH:MM (UTC)",    "Ping time (UTC)",                     TRUE,      FALSE,
  "SI_LATI",    "tacsat",  "dbl",   "Decimal degrees","Latitude",                            TRUE,      FALSE,
  "SI_LONG",    "tacsat",  "dbl",   "Decimal degrees","Longitude",                           TRUE,      FALSE,
  "SI_SP",      "tacsat",  "dbl",   "Knots",          "Instantaneous speed",                 TRUE,      FALSE,
  "SI_HE",      "tacsat",  "dbl",   "Degrees (0–360)","Instantaneous heading",               TRUE,      FALSE,

  # ── TACSAT derived fields (fd_clean_tacsat) ──────────────────────────────────
  ".pid",       "tacsat",  "int",   NA,               "Row identifier (added by fd_clean_tacsat)",        TRUE,  TRUE,
  "SI_DATIM",   "tacsat",  "dttm",  NA,               "Ping datetime (UTC), parsed from SI_DATE + SI_TIME", TRUE, TRUE,

  # ── EFLALO vessel fields ─────────────────────────────────────────────────────
  "VE_REF",     "eflalo",  "chr",   "≤20 characters", "Vessel identifier",                   TRUE,      FALSE,
  "VE_FLT",     "eflalo",  "chr",   "DCF fleet code", "Fleet segment",                       TRUE,      FALSE,
  "VE_COU",     "eflalo",  "chr",   "ISO 3166-1 a-3", "Vessel flag country",                 TRUE,      FALSE,
  "VE_LEN",     "eflalo",  "dbl",   "Metres (OAL)",   "Vessel overall length",               TRUE,      FALSE,
  "VE_KW",      "eflalo",  "dbl",   "kW",             "Engine power",                        TRUE,      FALSE,
  "VE_TON",     "eflalo",  "dbl",   "GT",             "Vessel tonnage (optional)",           FALSE,     FALSE,

  # ── EFLALO fishing trip fields ───────────────────────────────────────────────
  "FT_REF",     "eflalo",  "chr",   "≤20 characters", "Fishing trip reference number",       TRUE,      FALSE,
  "FT_DCOU",    "eflalo",  "chr",   "ISO 3166-1 a-3", "Departure country",                   TRUE,      FALSE,
  "FT_DHAR",    "eflalo",  "chr",   "UN LOCODE",      "Departure harbour",                   TRUE,      FALSE,
  "FT_DDAT",    "eflalo",  "chr",   "DD/MM/YYYY",     "Departure date",                      TRUE,      FALSE,
  "FT_DTIME",   "eflalo",  "chr",   "HH:MM",          "Departure time (UTC)",                TRUE,      FALSE,
  "FT_LCOU",    "eflalo",  "chr",   "ISO 3166-1 a-3", "Landing country",                     TRUE,      FALSE,
  "FT_LHAR",    "eflalo",  "chr",   "UN LOCODE",      "Landing harbour",                     TRUE,      FALSE,
  "FT_LDAT",    "eflalo",  "chr",   "DD/MM/YYYY",     "Landing (arrival) date",              TRUE,      FALSE,
  "FT_LTIME",   "eflalo",  "chr",   "HH:MM",          "Landing (arrival) time (UTC)",        TRUE,      FALSE,

  # ── EFLALO log event fields ──────────────────────────────────────────────────
  "LE_ID",      "eflalo",  "chr",   "≤25 characters", "Log event identifier",                TRUE,      FALSE,
  "LE_CDAT",    "eflalo",  "date",  "DD/MM/YYYY",     "Catch date (coerced to Date by fd_clean_eflalo)", TRUE, FALSE,
  "LE_STIME",   "eflalo",  "chr",   "HH:MM",          "Log event start time (optional)",     FALSE,     FALSE,
  "LE_ETIME",   "eflalo",  "chr",   "HH:MM",          "Log event end time (optional)",       FALSE,     FALSE,
  "LE_SLAT",    "eflalo",  "dbl",   "Decimal degrees","Log event start latitude (optional)", FALSE,     FALSE,
  "LE_SLON",    "eflalo",  "dbl",   "Decimal degrees","Log event start longitude (optional)",FALSE,     FALSE,
  "LE_ELAT",    "eflalo",  "dbl",   "Decimal degrees","Log event end latitude (optional)",   FALSE,     FALSE,
  "LE_ELON",    "eflalo",  "dbl",   "Decimal degrees","Log event end longitude (optional)",  FALSE,     FALSE,
  "LE_GEAR",    "eflalo",  "chr",   "3 characters",   "Gear code (DCF metier level 4)",      TRUE,      FALSE,
  "LE_MSZ",     "eflalo",  "dbl",   "mm (stretched)", "Mesh size",                           TRUE,      FALSE,
  "LE_RECT",    "eflalo",  "chr",   "e.g. '37F5'",    "ICES statistical rectangle",          TRUE,      FALSE,
  "LE_DIV",     "eflalo",  "chr",   "≤10 characters", "ICES division",                       TRUE,      FALSE,
  "LE_MET",     "eflalo",  "chr",   "DCF metier L6",  "Fishing activity (metier level 6)",   TRUE,      FALSE,
  "LE_KG_<SP>", "eflalo",  "dbl",   "kg",             "Landing weight per species (one column per species)", FALSE, FALSE,
  "LE_EURO_<SP>","eflalo", "dbl",   "EUR",            "Landing value per species (one column per species)",  FALSE, FALSE,

  # ── EFLALO derived fields (fd_clean_eflalo) ──────────────────────────────────
  ".eid",       "eflalo",  "int",   NA,               "Row identifier (added by fd_clean_eflalo)",                       TRUE,  TRUE,
  ".tid",       "eflalo",  "int",   NA,               "Trip identifier via consecutive_id() on trip-defining columns",   TRUE,  TRUE,
  "FT_DDATIM",  "eflalo",  "dttm",  NA,               "Trip departure datetime (UTC), parsed from FT_DDAT + FT_DTIME",   TRUE,  TRUE,
  "FT_LDATIM",  "eflalo",  "dttm",  NA,               "Trip landing datetime (UTC), parsed from FT_LDAT + FT_LTIME",     TRUE,  TRUE,
  "t1",         "eflalo",  "dttm",  NA,               "Event start datetime (UTC), derived from LE_CDAT + LE_STIME",     FALSE, TRUE,
  "t2",         "eflalo",  "dttm",  NA,               "Event end datetime (UTC), derived from LE_CDAT + LE_ETIME",       FALSE, TRUE,
  ".tsrc",      "eflalo",  "chr",   NA,               "Derivation source for t1/t2: 'data', 'next day', 'dummy', or NA", FALSE, TRUE

)

usethis::use_data(field_definitions, overwrite = TRUE)
