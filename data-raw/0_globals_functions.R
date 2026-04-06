# Functions from documentations/2026_ices-datacall/ICES-VMS-and-Logbooks-Data-Call/0_globals.R

#' Download a large file with a progress bar
#'
#' Downloads a file from a URL in 1 MB chunks, printing a text-based progress
#' bar with an ETA estimate to the console. The connection timeout is temporarily
#' raised to 600 seconds for the duration of the download and restored
#' afterwards via [on.exit()].
#'
#' @param url Character. URL of the file to download.
#' @param dest_file Character. Local path where the downloaded file will be written.
#' @param file_size Numeric. Expected file size in bytes. Used to compute the
#'   progress percentage and ETA; the download will still complete if the actual
#'   size differs, but the progress display will be inaccurate.
#'
#' @return The path `dest_file`, invisibly.
download_large_file <- function(url, dest_file, file_size) {
  # Create a simple text-based progress bar using Base R
  progress_bar <- function(current, total, width = 60) {
    percent <- current / total
    filled <- round(width * percent)
    bar <- paste0(
      "[",
      paste0(rep("=", filled), collapse = ""),
      paste0(rep(" ", width - filled), collapse = ""),
      "]"
    )

    # Calculate ETA
    elapsed_time <- as.numeric(difftime(Sys.time(), start_time, units = "secs"))
    eta <- if (percent > 0) {
      round((elapsed_time / percent) - elapsed_time)
    } else {
      NA
    }

    # Format ETA for display
    eta_str <- if (is.na(eta)) {
      "calculating..."
    } else if (eta < 60) {
      paste0(eta, "s")
    } else if (eta < 3600) {
      paste0(round(eta / 60), "m ", eta %% 60, "s")
    } else {
      paste0(round(eta / 3600), "h ", round((eta %% 3600) / 60), "m")
    }

    # Create the full progress string
    prog_str <- sprintf("  downloading %s %3d%% eta: %s", bar, round(percent * 100), eta_str)

    # Clear the line and write the progress
    cat("\r", prog_str, sep = "")
    if (current >= total) cat("\n")
    utils::flush.console()
  }

  # Store original timeout setting
  original_timeout <- getOption("timeout")

  # Temporarily increase timeout just for this function's scope
  options(timeout = 600)
  # This gives a 10-minute timeout - if you have a slow internet connection you might need to increase this

  # Use on.exit to ensure the original timeout value is restored even if the function errors
  on.exit(options(timeout = original_timeout))

  # Record start time for ETA calculation
  start_time <- Sys.time()

  # Open connections
  con <- url(url, "rb")
  output <- file(dest_file, "wb")

  # Read and write in chunks with progress
  chunk_size <- 1024 * 1024  # 1MB chunks
  total_read <- 0

  tryCatch({
    repeat {
      data <- readBin(con, "raw", n = chunk_size)
      if (length(data) == 0) break
      writeBin(data, output)
      total_read <- total_read + length(data)

      # Update progress bar
      progress_bar(total_read, file_size)
    }

    message("Download complete!")
  },
  finally = {
    # Always close connections, even on error
    close(con)
    close(output)
  })

  return(invisible(dest_file))
}

# Define function for NOT in data
'%!in%' <- function(x,y)!('%in%'(x,y))

#' Convert a data frame to an sf object
#'
#' @param data A data frame containing coordinate columns.
#' @param coords Character vector of length 2 giving the names of the longitude
#'   and latitude columns, in that order.
#' @param crs Coordinate reference system, passed to [sf::st_set_crs()].
#'   Defaults to 4326 (WGS 84).
#'
#' @return An `sf` object. The coordinate columns are retained in the data
#'   (`remove = FALSE`).
transform_to_sf <- function(data, coords, crs = 4326) {
  data %>%
    sf::st_as_sf(coords = coords, remove = F) %>%
    sf::st_set_crs(crs)
}

#' Calculate upper catch bounds per species for outlier detection
#'
#' For each species, finds the largest landing weight that is not separated from
#' the bulk of the distribution by a log10-scale gap exceeding `lanThres`. Values
#' above this bound are considered outliers.
#'
#' @param specs Character vector of species codes to process.
#' @param eflalo Data frame of logbook records containing `LE_KG_<SPECIES>` columns.
#' @param lanThres Numeric. Minimum log10-scale gap between consecutive positive
#'   landing weights that flags an outlier break.
#'
#' @return A list of length `length(specs)`. Each element is a single numeric
#'   value: the upper bound for that species, or `max(wgh)` if no gap exceeds
#'   `lanThres`.
#'
#' @note The inner `ifelse()` checks `length(wgh) == 0` *after* `any(difw > lanThres)`,
#'   so an empty `wgh` vector (no positive landings) will only return `0` when
#'   the first condition is `FALSE`. If `wgh` is empty the `diff(log10(wgh))`
#'   call produces `numeric(0)` and `any(...)` returns `FALSE`, so the fallback
#'   path is reached correctly — but this is fragile and worth revisiting.
#'
#' @note Likely bug on line `wgh[rev(which(difw <= lanThres)[1] + 1)]`:
#'   `rev()` is applied to a scalar (the result of `[1]`), making it a no-op.
#'   The probable intent is `wgh[rev(which(difw <= lanThres))[1] + 1]` — i.e.,
#'   take the *last* index where the gap is within threshold and step one beyond
#'   it. As written, it uses the *first* such index instead.
get_spec_bounds <- function(specs, eflalo, lanThres) {
  lapply(
    as.list(specs),
    function(x) {
      specs_cols <- grep(x, colnames(eflalo))
      idx <- specs_cols[grep("KG", colnames(eflalo)[specs_cols])]
      wgh <- sort(unique(eflalo[which(eflalo[, idx] > 0), idx]))
      difw <- diff(log10(wgh))
      ifelse(
        any(difw > lanThres),
        wgh[rev(which(difw <= lanThres)[1] + 1)],  # Return only the first value
        ifelse(
          length(wgh) == 0,
          0,
          max(wgh, na.rm = TRUE)
        )
      )
    }
  )
}

#' Get column indices of species KG columns in eflalo
#'
#' For each species code, returns the position(s) of the matching `LE_KG_<SPECIES>`
#' column within the KG-containing columns of `eflalo`.
#'
#' @param specs Character vector of species codes to look up.
#' @param eflalo Data frame of logbook records containing `LE_KG_<SPECIES>` columns.
#'
#' @return A named integer vector (via `sapply`) with one element per species.
#'   Note these are indices into the KG-column subset
#'   (`colnames(eflalo)[grep("KG", colnames(eflalo))]`), not into `eflalo` directly.
get_species_indices <- function(specs, eflalo) {
  sapply(specs, function(spec) {
    # Find the column indices that contain the current species name and "KG"
    grep(spec, colnames(eflalo)[grep("KG", colnames(eflalo))])
  })
}

#' Get indices of KG and EURO columns
#'
#' @param cols Character vector of column names, typically `colnames(eflalo)`.
#'
#' @return Integer vector of positions where the column name contains `"KG"` or
#'   `"EURO"`.
kgeur <- function(cols) {
  grep("KG|EURO", cols)
}

#' Create a unique trip–event identifier
#'
#' Concatenates `LE_ID` and `LE_CDAT` with `"-"` to form a per-row identifier.
#'
#' @param eflalo Data frame of logbook records with columns `LE_ID` and `LE_CDAT`.
#'
#' @return Character vector of the same length as `nrow(eflalo)`.
create_trip_id <- function(eflalo) {
  paste(eflalo$LE_ID, eflalo$LE_CDAT, sep="-")
}

#' Convert separate date and time columns to POSIXct
#'
#' @param date_col Character vector of dates in `"DD/MM/YYYY"` format.
#' @param time_col Character vector of times in `"HH:MM"` format.
#'
#' @return POSIXct vector in UTC (GMT).
convert_to_datetime <- function(date_col, time_col) {
  as.POSIXct(paste(date_col, time_col, sep = " "), tz = "GMT", format = "%d/%m/%Y  %H:%M")
}

#' Remove logbook records with departure before 1 January of a given year
#'
#' Filters `eflalo` to rows where `FT_DDATIM` is on or after `YYYY-01-01 00:00`.
#' `FT_DDATIM` is coerced to POSIXct (`"%Y-%m-%d %H:%M"`) before filtering, so
#' it must already be in that format (or be coercible to it).
#'
#' @param eflalo Data frame of logbook records with a `FT_DDATIM` column.
#' @param year Integer or character. The four-digit year defining the cutoff.
#'
#' @return A filtered data frame.
remove_before_jan <- function(eflalo, year) {
  # Convert the start of the year to a POSIXct datetime object
  start_of_year <- as.POSIXct(paste(year, "-01-01 00:00:00", sep = ""), format = "%Y-%m-%d %H:%M")

  # Ensure FT_DDATIM is in the correct datetime format
  eflalo$FT_DDATIM <- as.POSIXct(eflalo$FT_DDATIM, format = "%Y-%m-%d %H:%M")

  # Remove records with FT_DDATIM before the start of the year
  eflalo <- eflalo[eflalo$FT_DDATIM >= start_of_year,]

  return(eflalo)
}



#' Calculate ping intervals in TACSAT data
#'
#' Computes a weighted blend of backward and forward time differences (in
#' minutes) between consecutive VMS pings, grouped either by trip or by vessel.
#' Results are stored in a new column `INTV`.
#'
#' @param tacsat Data frame of VMS records. Must contain `VE_REF` and either
#'   `SI_DATIM` (POSIXct) or `SI_DATE` + `SI_TIME` character columns. If
#'   `level = "trip"`, `FT_REF` is also required.
#' @param level Character. Grouping level for interval calculation: `"trip"`
#'   (default) or `"vessel"`.
#' @param weight Numeric vector of length 2 giving the weights applied to the
#'   backward and forward differences respectively. Must sum to a non-zero
#'   value; they are normalised internally. Default `c(1, 0)` uses only the
#'   backward difference.
#' @param fill.na Logical. If `TRUE`, boundary `NA` intervals (first/last ping
#'   of a group) are filled using whichever neighbour difference is available.
#'   Default `FALSE`.
#'
#' @return `tacsat` with an added numeric column `INTV` (minutes). Pings with
#'   `FT_REF == "0"` receive `NA` when `level = "trip"`.
#'
#' @note Calls `sortTacsat()` internally, which is from the `vmstools` package.
intvTacsat <- function (tacsat, level = "trip", weight = c(1, 0), fill.na = FALSE) {
  # Check if 'weight' is a length 2 numeric vector
  if (length(weight) != 2)
    stop("weight must be specified as a length 2 numeric vector")

  # Normalize 'weight' to sum to 1
  weight <- weight/sum(weight, na.rm = TRUE)

  # Sort 'tacsat' (assuming 'sortTacsat' is a function that sorts 'tacsat')
  tacsat <- sortTacsat(tacsat)

  # Convert 'SI_DATE' and 'SI_TIME' to POSIXct if 'SI_DATIM' is not already present
  if (!"SI_DATIM" %in% colnames(tacsat))
    tacsat$SI_DATIM <- as.POSIXct(paste(tacsat$SI_DATE, tacsat$SI_TIME, sep = " "), tz = "GMT", format = "%d/%m/%Y  %H:%M")

  # If level is 'trip', calculate intervals for each trip
  if (level == "trip") {
    # Check if 'FT_REF' is present
    if (is.null(tacsat$FT_REF))
      stop("no trip number available to merge on trip level")

    # Split 'tacsat' by 'VE_REF'
    sptacsat <- split(tacsat, tacsat$VE_REF)

    # Calculate intervals for each trip
    tacsat$INTV <- unlist(lapply(sptacsat, function(x) {
      # Convert 'FT_REF' to factor
      FT_REF <- as.factor(x$FT_REF)

      # Calculate intervals for each 'FT_REF'
      res <- by(x, FT_REF, function(y) {
        # If there is more than one row, calculate intervals
        if (nrow(y) > 1) {
          # Calculate differences in 'SI_DATIM' for each row
          difftime_xmin1 <- c(NA, difftime(y$SI_DATIM[2:nrow(y)], y$SI_DATIM[1:(nrow(y) - 1)], units = "mins"))
          difftime_xplus1 <- c(difftime_xmin1[-1], NA)

          # Calculate intervals based on 'weight'
          if (any(weight == 0)) {
            if (weight[1] == 0)
              INTV <- difftime_xplus1
            if (weight[2] == 0)
              INTV <- difftime_xmin1
          } else {
            INTV <- rowSums(cbind(difftime_xmin1 * weight[1], difftime_xplus1 * weight[2]))
          }

          # If 'fill.na' is TRUE, fill NA values in 'INTV'
          if (fill.na) {
            idx <- which(is.na(INTV))
            INTV[idx] <- rowSums(cbind(difftime_xmin1[idx], difftime_xplus1[idx]), na.rm = TRUE)
            INTV[idx][which(INTV[idx] == 0)] <- NA
          }

          return(INTV)
        } else {
          return(NA)
        }
      })

      return(unsplit(res, FT_REF))
    }))

    # Set 'INTV' to NA where 'FT_REF' equals 0
    tacsat$INTV[which(tacsat$FT_REF == "0")] <- NA
  }

  # If level is 'vessel', calculate intervals for each vessel
  if (level == "vessel") {
    # Calculate differences in 'SI_DATIM' for each row
    difftime_xmin1 <- c(NA, difftime(tacsat$SI_DATIM[2:nrow(tacsat)], tacsat$SI_DATIM[1:(nrow(tacsat) - 1)], units = "mins"))
    difftime_xplus1 <- c(difftime_xmin1[-1], NA)

    # Calculate intervals based on 'weight'
    if (any(weight == 0)) {
      if (weight[1] == 0)
        INTV <- difftime_xplus1
      if (weight[2] == 0)
        INTV <- difftime_xmin1
    } else {
      INTV <- rowSums(cbind(difftime_xmin1 * weight[1], difftime_xplus1 * weight[2]))
    }

    # If 'fill.na' is TRUE, fill NA values in 'INTV'
    if (fill.na) {
      idx <- which(is.na(INTV))
      INTV[idx] <- rowSums(cbind(difftime_xmin1[idx], difftime_xplus1[idx]), na.rm = TRUE)
      INTV[idx][which(INTV[idx] == 0)] <- NA
    }

    # Assign 'INTV' to 'tacsat'
    tacsat$INTV <- INTV

    # Get unique vessels
    vessels <- unique(tacsat$VE_REF)

    # Get first and last rows for each vessel
    first.vessels <- unlist(lapply(as.list(vessels), function(x) which(tacsat$VE_REF == x)[1]))
    last.vessels <- unlist(lapply(as.list(vessels), function(x) rev(which(tacsat$VE_REF == x))[1]))

    # Set 'INTV' to NA for first and last rows of each vessel based on 'weight'
    if (weight[1] != 0)
      tacsat$INTV[first.vessels] <- NA
    if (weight[2] != 0)
      tacsat$INTV[last.vessels] <- NA

    # If 'fill.na' is TRUE, fill NA values in 'INTV' for first and last rows of each vessel
    if (fill.na) {
      tacsat$INTV[first.vessels] <- difftime_xplus1[first.vessels]
      tacsat$INTV[last.vessels] <- difftime_xmin1[last.vessels]
    }
  }

  return(tacsat)
}


#' Sort TACSAT/observer data by vessel (or observer) and datetime
#'
#' Sorts `dat` by `VE_REF` then `SI_DATIM`, or by `OB_REF` then `SI_DATIM` if
#' `OB_REF` is present. `SI_DATIM` is derived from `SI_DATE` + `SI_TIME` if not
#' already present.
#'
#' @param dat Data frame containing VMS or observer records. Must have either
#'   `SI_DATIM` (POSIXct) or both `SI_DATE` and `SI_TIME` character columns, and
#'   at least one of `VE_REF` or `OB_REF`.
#'
#' @return The sorted data frame.
#'
#' @note If both `VE_REF` and `OB_REF` are present, the `OB_REF` sort silently
#'   overwrites the `VE_REF` sort.
sfsortTacsat <- function(dat) {
  if (!"SI_DATIM" %in% colnames(dat)) {
    dat$SI_DATIM <- as.POSIXct(paste(dat$SI_DATE, dat$SI_TIME, sep = " "), tz = "GMT", format = "%d/%m/%Y  %H:%M")
  }
  if ("VE_REF" %in% colnames(dat)) {
    dat <- arrange(dat, VE_REF, SI_DATIM)
  }
  if ("OB_REF" %in% colnames(dat)) {
    dat <- arrange(dat, OB_REF, SI_DATIM)
  }
  return(dat)
}





#' Interactive Tcl/Tk dialog to specify the number of speed distribution peaks
#'
#' Opens a small GUI window with a text entry pre-filled with `5`. The user
#' edits the value and clicks "Next" to close the window. Called interactively
#' inside [ac.tac.anal()] for each gear/year/period combination.
#'
#' @return Numeric scalar: the number of peaks entered by the user.
#'
#' @note Requires the `tcltk` package and a display (will fail in headless
#'   sessions).
callNumberPeak <- function(){
  tt <- tktoplevel()
  peaks <- tclVar(5)

  f1 <- tkframe(tt)
  tkpack(f1, side='top')
  tkpack(tklabel(f1, text='peaks: '), side='left')
  tkpack(tkentry(f1, textvariable=peaks), side='left')

  tkpack(tkbutton(tt, text='Next', command=function() tkdestroy(tt)),
         side='right', anchor='s')

  tkwait.window(tt)
  return(as.numeric(tclvalue(peaks)))}




#' Interactively build a storeScheme for speed-based activity analysis
#'
#' Loops over time units and gear/vessel strata, plots a mirrored speed
#' histogram for each, and prompts the user (via [callNumberPeak()]) to enter
#' the number of Gaussian peaks to fit. The result is a `storeScheme` data
#' frame consumed by [act.tac()].
#'
#' @param tacsat Data frame of VMS records. Must contain `SI_DATIM` (POSIXct)
#'   and `LE_L5MET`. If `analyse.by = "VE_REF"`, `VE_REF` is also required.
#' @param units Character. Time unit for stratification: `"all"`, `"year"`
#'   (default), `"month"`, or `"week"`.
#' @param storeScheme Ignored on input — the parameter default
#'   (`storeScheme = storeScheme`) will fail if no object named `storeScheme`
#'   exists in the calling environment. The function always constructs and
#'   returns a fresh `storeScheme` internally.
#' @param analyse.by Character. Column to stratify analysis by: `"LE_L5MET"`
#'   (default) or `"VE_REF"`.
#' @param identify Character. `"peaks"` (default) stores the number of peaks;
#'   `"means"` additionally prompts for peak mean values via `callPeakValue()`
#'   (must be defined separately).
#'
#' @return A data frame (`storeScheme`) with one row per stratum × group,
#'   containing columns `years`, `months`, `weeks`, `analyse.by`, `peaks`,
#'   `fixPeaks`, `sigma0`, and optionally `means`.
ac.tac.anal <- function(tacsat, units = "year", storeScheme = storeScheme, analyse.by = "LE_L5MET", identify = "peaks") {
  if (!"LE_L5MET" %in% colnames(tacsat))
    stop("Provide gear type (as column 'LE_L5MET' and if unknown, provide it as 'MIS'")
  if (!analyse.by %in% c("LE_L5MET", "VE_REF"))
    warning("Analysing by unknown column variable, please check!")
  if (analyse.by %in% colnames(tacsat)) {
    if (units == "all") {
      yrs <- 0
      mths <- 0
      wks <- 0
    }
    if (units == "year") {
      yrs <- sort(unique(format(tacsat$SI_DATIM, "%Y")))
      mths <- 0
      wks <- 0
    }
    if (units == "month") {
      yrs <- sort(unique(format(tacsat$SI_DATIM, "%Y")))
      mths <- sort(unique(month(tacsat$SI_DATIM)))
      wks <- 0
    }
    if (units == "week") {
      yrs <- sort(unique(format(tacsat$SI_DATIM, "%Y")))
      wks <- sort(unique(week(tacsat$SI_DATIM)))
      mths <- 0
    }
    runScheme <- expand.grid(years = yrs, months = mths,
                             weeks = wks, stringsAsFactors = FALSE)
    storeScheme <- expand.grid(years = yrs, months = mths,
                               weeks = wks, analyse.by = unique(tacsat[, analyse.by]),
                               stringsAsFactors = FALSE)
    storeScheme$peaks <- NA
    storeScheme$fixPeaks <- FALSE
    storeScheme$sigma0 <- 0.911
    if (identify == "means")
      storeScheme$means <- NA
    for (iRun in 1:nrow(runScheme)) {
      yr <- runScheme[iRun, "years"]
      mth <- runScheme[iRun, "months"]
      wk <- runScheme[iRun, "weeks"]
      if (nrow(runScheme) == 1) {
        sTacsat <- tacsat
      } else {
        if (mth == 0 & wk == 0)
          sTacsat <- subset(tacsat, format(tacsat$SI_DATIM, "%Y") == yr)
        if (mth == 0 & wk != 0)
          sTacsat <- subset(tacsat, format(tacsat$SI_DATIM, "%Y") == yr & week(tacsat$SI_DATIM) == wk)
        if (mth != 0 & wk == 0)
          sTacsat <- subset(tacsat, format(tacsat$SI_DATIM, "%Y") == yr & month(tacsat$SI_DATIM) == mth)
      }
      for (iBy in na.omit(unique(sTacsat[, analyse.by]))) {
        dat <- subset(sTacsat, sTacsat[, analyse.by] == iBy)
        datmr <- dat
        datmr$SI_SP <- -1 * dat$SI_SP
        datmr <- rbind(dat, datmr)
        xrange <- pmin(20, range(datmr$SI_SP), na.rm = TRUE)
        datmr$SI_SP[which(abs(datmr$SI_SP) > 20)] <- NA
        hist(datmr$SI_SP, breaks = seq(-20, 20, 0.5),
             main = paste(iBy, ifelse(yr > 0, yr, ""), ifelse(mth > 0, mth, ""), ifelse(wk > 0, wk, "")), xaxt = "n")
        axis(1, at = seq(-20, 20, 1))

        # Introduce a delay before calling the callNumberPeak() function
        Sys.sleep(1)

        # Call the callNumberPeak() function to get user input
        pks <- callNumberPeak()

        storeScheme[which(storeScheme$years == yr & storeScheme$months == mth & storeScheme$weeks == wk & storeScheme$analyse.by == iBy), "peaks"] <- pks

        if (identify == "means") {
          valPeaks <- callPeakValue(pks)
          if (substr(valPeaks, 1, 1) == " ")
            valPeaks <- substr(valPeaks, 2, nchar(valPeaks))
          storeScheme[which(storeScheme$years == yr & storeScheme$months == mth & storeScheme$weeks == wk & storeScheme$analyse.by == iBy), "means"] <- valPeaks
        }
      }
    }
  } else {
    stop("analyse.by statement not found as a column in the specified tacsat dataset")
  }
  return(storeScheme)
}

#' Assign fishing activity state via Gaussian mixture models
#'
#' Fits normal mixture models to mirrored vessel speed distributions to classify
#' each VMS ping as fishing (`"f"`), steaming (`"s"`), or harbour/non-fishing
#' (`"h"`). Uses the `mixtools::normalmixEM()` engine.
#'
#' @param tacsat Data frame of VMS records. Must contain `SI_SP` (speed) and
#'   `SI_DATIM` (POSIXct), or `SI_DATE` + `SI_TIME`. `LE_L5MET` is required
#'   when `analyse.by = "LE_L5MET"`; `VE_REF` when `analyse.by = "VE_REF"`.
#' @param units Character. Time stratification: `"all"`, `"year"` (default),
#'   `"month"`, or `"week"`.
#' @param analyse.by Character. Stratification variable: `"LE_L5MET"` (default)
#'   or `"VE_REF"`.
#' @param storeScheme Data frame produced by [ac.tac.anal()] specifying the
#'   number of peaks (and optionally means) per stratum. If `NULL`, defaults to
#'   5 peaks for all strata.
#' @param plot Logical. If `TRUE`, opens a new graphics device and plots the
#'   fitted mixture for each stratum. Default `FALSE`.
#' @param level Character. `"all"` (default) fits at the gear/vessel level;
#'   `"vessel"` additionally refines fits per individual vessel.
#'
#' @return Character vector of length `nrow(tacsat)` with states `"f"`, `"s"`,
#'   or `"h"` (or `NA` where fitting failed or speed was missing).
#'
#' @note Relies on helper functions `an()`, `ac()`, `af()`, `anf()`, and
#'   `orderBy()` from the `vmstools` package. Requires `mixtools`.
act.tac <- function (tacsat, units = "year", analyse.by = "LE_L5MET", storeScheme = NULL,
                     plot = FALSE, level = "all"){
  if (!"SI_DATIM" %in% colnames(tacsat))
    tacsat$SI_DATIM <- as.POSIXct(paste(tacsat$SI_DATE, tacsat$SI_TIME, # id datim doesn't exist in eflalo, creates in
                                        sep = " "), tz = "GMT", format = "%d/%m/%Y  %H:%M")
  if (!analyse.by %in% c("LE_L5MET", "VE_REF"))
    stop("Analysing only by level 5 metier or vessel")                            ## would it be useful to examine speeds at L5 or L6 metier?
  tacsat$ID <- 1:nrow(tacsat)
  tacsat$SI_STATE <- NA                                                   ## creates ID and blank column to receive state
  tacsatOrig <- tacsat
  idx <- which(is.na(tacsat$SI_SP) == FALSE)
  tacsat <- tacsat[idx, ]                                                 ## drops rows which do not have a valid speed value
  storeScheme$sigma0[which(storeScheme$sigma0 == 0)] <- "d"
  if (units == "all") {
    yrs <- 0
    mths <- 0
    wks <- 0
  }
  if (units == "year") {
    yrs <- sort(unique(format(tacsat$SI_DATIM, "%Y")))
    mths <- 0
    wks <- 0
  }
  if (units == "month") {
    yrs <- sort(unique(format(tacsat$SI_DATIM, "%Y")))
    mths <- an(sort(unique(format(tacsat$SI_DATIM, "%m"))))
    wks <- 0
  }
  if (units == "week") {
    yrs <- sort(unique(format(tacsat$SI_DATIM, "%Y")))
    wks <- an(sort(unique(format(tacsat$SI_DATIM, "%W")))) +
      1
    mths <- 0
  }
  runScheme <- expand.grid(years = yrs, months = mths, weeks = wks)
  for (iRun in 1:nrow(runScheme)) {
    yr <- runScheme[iRun, "years"]
    mth <- runScheme[iRun, "months"]
    wk <- runScheme[iRun, "weeks"]
    if (nrow(runScheme) == 1) {
      sTacsat <- tacsat
    }
    else {
      if (mth == 0 & wk == 0)
        sTacsat <- subset(tacsat, format(tacsat$SI_DATIM,
                                         "%Y") == yr)
      if (mth == 0 & wk != 0)
        sTacsat <- subset(tacsat, format(tacsat$SI_DATIM,
                                         "%Y") == yr & (an(format(tacsat$SI_DATIM, "%W")) +
                                                          1) == wk)
      if (mth != 0 & wk == 0)
        sTacsat <- subset(tacsat, format(tacsat$SI_DATIM,
                                         "%Y") == yr & format(tacsat$SI_DATIM, "%m") ==
                            mth)
    }
    if (plot == TRUE)
      x11()
    if ("LE_L5MET" %in% colnames(tacsat) & analyse.by == "LE_L5MET") {
      gearList <- names(which((rowSums(table(sTacsat$LE_L5MET,
                                             sTacsat$SI_SP)) - table(sTacsat$LE_L5MET, sTacsat$SI_SP)[,
                                                                                                      "0"]) > 40))
      tyg <- subset(sTacsat, is.na(LE_L5MET) == FALSE &
                      LE_L5MET %in% gearList)
      tygmr <- tyg
      tygmr$SI_SP <- -1 * tygmr$SI_SP
      tygmr <- rbind(tyg, tygmr)
      tng <- subset(sTacsat, is.na(LE_L5MET) == TRUE | !LE_L5MET %in%
                      gearList)
      tngmr <- tng
      tngmr$SI_SP <- -1 * tngmr$SI_SP
      tngmr <- rbind(tng, tngmr)
      res <- list()
      for (iGr in unique(tyg$LE_L5MET)) {
        tbl <- table(subset(tygmr, LE_L5MET == iGr)$SI_SP)
        spd <- an(names(rev(sort(tbl))[1]))
        idx <- which(subset(tygmr, LE_L5MET == iGr)$SI_SP ==
                       spd)
        nxt <- ifelse(names(rev(sort(tbl))[1]) == ac(spd),
                      ifelse(abs(an(names(rev(sort(tbl))[2]))) ==
                               abs(spd), names(rev(sort(tbl))[3]), names(rev(sort(tbl))[2])),
                      names(rev(sort(tbl))[1]))
        if (tbl[ac(spd)]/tbl[nxt] > 5) {
          idx <- sample(idx, tbl[ac(spd)] - tbl[nxt] *
                          2, replace = FALSE)
          if (length(which(abs(an(names(tbl))) %in% spd)) >
              1)
            idx <- c(idx, sample(which(subset(tygmr,
                                              LE_L5MET == iGr)$SI_SP == (-1 * spd)), tbl[ac(-1 *
                                                                                              spd)] - tbl[nxt] * 2, replace = FALSE))
        }
        else {
          idx <- -1:-nrow(subset(tygmr, LE_L5MET == iGr))
        }
        if (is.null(storeScheme) == TRUE) {
          res[[iGr]] <- try(normalmixEM(subset(tygmr,
                                               LE_L5MET == iGr)$SI_SP[-idx], maxit = 1000,
                                        k = 5, maxrestarts = 20, mean.constr = c("-b",
                                                                                 "-a", 0, "a", "b"), sd.constr = c("b",
                                                                                                                   "a", 0.911, "a", "b"), sigma = rep(1, 5)))
        }
        else {
          if ("means" %in% colnames(storeScheme)) {
            ss <- storeScheme[which(storeScheme$years ==
                                      yr & storeScheme$months == mth & storeScheme$weeks ==
                                      wk & storeScheme$analyse.by == iGr), "means"]
            sigma <- anf(storeScheme[which(storeScheme$years ==
                                             yr & storeScheme$months == mth & storeScheme$weeks ==
                                             wk & storeScheme$analyse.by == iGr), "sigma0"])
            fixPeaks <- ac(storeScheme[which(storeScheme$years ==
                                               yr & storeScheme$months == mth & storeScheme$weeks ==
                                               wk & storeScheme$analyse.by == iGr), "fixPeaks"])
            if (length(c(na.omit(as.numeric(strsplit(ss,
                                                     " ")[[1]])))) == 3) {
              constraintmn <- c("-a", 0, "a")
            }
            else {
              constraintmn <- c("-b", "-a", 0, "a", "b")
            }
            if (length(c(na.omit(as.numeric(strsplit(ss,
                                                     " ")[[1]])))) == 3) {
              constraintsd <- c("a", "b", "a")
            }
            else {
              constraintsd <- c("b", "a", sigma, "a",
                                "b")
            }
            if (fixPeaks)
              constraintmn <- c(na.omit(anf(unlist(strsplit(ss,
                                                            " ")))))
            res[[iGr]] <- try(normalmixEM(subset(tygmr,
                                                 LE_L5MET == iGr)$SI_SP[-idx], maxit = 1000,
                                          mu = c(na.omit(as.numeric(strsplit(ss,
                                                                             " ")[[1]]))), sigma = rep(1, length(constraintsd)),
                                          maxrestarts = 20, mean.constr = constraintmn,
                                          sd.constr = constraintsd))
          }
          else {
            ss <- storeScheme[which(storeScheme$years ==
                                      yr & storeScheme$months == mth & storeScheme$weeks ==
                                      wk & storeScheme$analyse.by == iGr), "peaks"]
            sigma <- anf(storeScheme[which(storeScheme$years ==
                                             yr & storeScheme$months == mth & storeScheme$weeks ==
                                             wk & storeScheme$analyse.by == iGr), "sigma0"])
            fixPeaks <- ac(storeScheme[which(storeScheme$years ==
                                               yr & storeScheme$months == mth & storeScheme$weeks ==
                                               wk & storeScheme$analyse.by == iGr), "fixPeaks"])
            if (ss == 3) {
              constraintmn <- c("-a", 0, "a")
            }
            else {
              constraintmn <- c("-b", "-a", 0, "a", "b")
            }
            if (ss == 3) {
              constraintsd <- c("a", "b", "a")
            }
            else {
              constraintsd <- c("b", "a", sigma, "a",
                                "b")
            }
            if (length(ss) > 0) {
              if (is.na(ss) == TRUE)
                res[[iGr]] <- try(normalmixEM(subset(tygmr,
                                                     LE_L5MET == iGr)$SI_SP[-idx], maxit = 1000,
                                              k = 5, maxrestarts = 20, mean.constr = c("-b",
                                                                                       "-a", 0, "a", "b"), sd.constr = c("b",
                                                                                                                         "a", sigma, "a", "b"), sigma = rep(1,
                                                                                                                                                            5)))
              if (is.na(ss) == FALSE)
                res[[iGr]] <- try(normalmixEM(subset(tygmr,
                                                     LE_L5MET == iGr)$SI_SP[-idx], maxit = 1000,
                                              k = ss, maxrestarts = 20, mean.constr = constraintmn,
                                              sd.constr = constraintsd, sigma = rep(1,
                                                                                    length(constraintsd))))
            }
            else {
              res[[iGr]] <- try(normalmixEM(subset(tygmr,
                                                   LE_L5MET == iGr)$SI_SP[-idx], maxit = 1000,
                                            k = 5, maxrestarts = 20, mean.constr = c("-b",
                                                                                     "-a", 0, "a", "b"), sd.constr = c("b",
                                                                                                                       "a", sigma, "a", "b"), sigma = rep(1,
                                                                                                                                                          5)))
            }
          }
        }
        if (plot == TRUE)
          plot(res[[iGr]], 2, breaks = 100, xlim = c(-20,
                                                     20))
      }
      if (level == "vessel") {
        for (iGr in unique(tyg$LE_L5MET)) if (!class(res[[iGr]]) ==
                                              "try-error") {
          res[[iGr]] <- res[[iGr]]$mu
        }
        else {
          res[[iGr]] <- rep(NA, 5)
        }
        res <- lapply(res, function(x) {
          if (class(x) == "try-error") {
            x <- rep(NA, 5)
          }
          else {
            x
          }
        })
        res <- lapply(res, sort)
      }
      if (level == "vessel") {
        if (nrow(tygmr) > 40)
          shipList <- names(which((rowSums(table(tygmr$VE_REF,
                                                 tygmr$SI_SP)) - table(tygmr$VE_REF, tygmr$SI_SP)[,
                                                                                                  "0"]) > 20))
        shipFit <- list()
        if (exists("shipList")) {
          for (iShip in shipList) {
            tbl <- table(subset(tygmr, VE_REF == iShip)$SI_SP)
            spd <- an(names(rev(sort(tbl))[1]))
            idx <- which(subset(tygmr, VE_REF == iShip)$SI_SP ==
                           spd)
            nxt <- ifelse(names(rev(sort(tbl))[1]) ==
                            ac(spd), ifelse(abs(an(names(rev(sort(tbl))[2]))) ==
                                              abs(spd), names(rev(sort(tbl))[3]), names(rev(sort(tbl))[2])),
                          names(rev(sort(tbl))[1]))
            if (tbl[ac(spd)]/tbl[nxt] > 5) {
              idx <- sample(idx, tbl[ac(spd)] - tbl[nxt] *
                              2, replace = FALSE)
              if (length(which(abs(an(names(tbl))) %in%
                               spd)) > 1)
                idx <- c(idx, sample(which(subset(tygmr,
                                                  VE_REF == iShip)$SI_SP == (-1 * spd)),
                                     tbl[ac(-1 * spd)] - tbl[nxt] * 2, replace = FALSE))
            }
            else {
              idx <- -1:-nrow(subset(tygmr, VE_REF ==
                                       iShip))
            }
            shipTacsat <- subset(tygmr, VE_REF == iShip)
            if (length(res[[names(which.max(table(shipTacsat$LE_L5MET)))]]) ==
                3) {
              constraintmn <- c("-a", 0, "a")
            }
            else {
              constraintmn <- c("-b", "-a", 0, "a", "b")
            }
            if (length(res[[names(which.max(table(shipTacsat$LE_L5MET)))]]) ==
                3) {
              constraintsd <- c("a", "b", "a")
            }
            else {
              constraintsd <- c("b", "a", 0.911, "a",
                                "b")
            }
            shipFit[[iShip]] <- try(normalmixEM(shipTacsat$SI_SP[-idx],
                                                mu = res[[names(which.max(table(shipTacsat$LE_L5MET)))]],
                                                maxit = 2000, sigma = rep(1, length(constraintsd)),
                                                mean.constr = constraintmn, sd.constr = constraintsd))
            if (class(shipFit[[iShip]]) != "try-error") {
              mu <- shipFit[[iShip]]$mu
              sds <- shipFit[[iShip]]$sigma
              probs <- dnorm(x = shipTacsat$SI_SP, mean = mu[ceiling(length(mu)/2)],
                             sd = sds[ceiling(length(mu)/2)])
              for (i in (ceiling(length(mu)/2) + 1):length(mu)) probs <- cbind(probs,
                                                                               dnorm(x = shipTacsat$SI_SP, mean = mu[i],
                                                                                     sd = sds[i]))
              SI_STATE <- apply(probs, 1, which.max)
              if (length(mu) == 3) {
                SI_STATE <- af(SI_STATE)
                levels(SI_STATE) <- c("f", "s")
                SI_STATE <- ac(SI_STATE)
              }
              if (length(mu) == 5) {
                SI_STATE <- af(SI_STATE)
                levels(SI_STATE) <- c("h", "f", "s")
                SI_STATE <- ac(SI_STATE)
              }
              tacsat$SI_STATE[which(tacsat$ID %in% shipTacsat$ID)] <- SI_STATE[1:(length(SI_STATE)/2)]
            }
            else {
              tacsat$SI_STATE[which(tacsat$ID %in% shipTacsat$ID)] <- NA
            }
          }
        }
      }
      else {
        for (iGr in unique(tyg$LE_L5MET)) {
          if (!class(res[[iGr]]) == "try-error") {
            mu <- res[[iGr]]$mu
            sds <- res[[iGr]]$sigma
            probs <- dnorm(x = subset(tyg, LE_L5MET ==
                                        iGr)$SI_SP, mean = mu[ceiling(length(mu)/2)],
                           sd = sds[ceiling(length(mu)/2)])
            for (i in (ceiling(length(mu)/2) + 1):length(mu)) probs <- cbind(probs,
                                                                             dnorm(x = subset(tyg, LE_L5MET == iGr)$SI_SP,
                                                                                   mean = mu[i], sd = sds[i]))
            SI_STATE <- apply(probs, 1, which.max)
            if (length(mu) == 3) {
              SI_STATE <- af(SI_STATE)
              levels(SI_STATE) <- c("f", "s")
              SI_STATE <- ac(SI_STATE)
            }
            if (length(mu) == 5) {
              SI_STATE <- af(SI_STATE)
              levels(SI_STATE) <- c("h", "f", "s")
              SI_STATE <- ac(SI_STATE)
            }
            tacsat$SI_STATE[which(tacsat$ID %in% subset(tyg,
                                                        LE_L5MET == iGr)$ID)] <- SI_STATE
          }
        }
      }
      if (nrow(tngmr) > 40)
        nonshipList <- names(which((rowSums(table(tngmr$VE_REF,
                                                  tngmr$SI_SP)) - table(tngmr$VE_REF, tngmr$SI_SP)[,
                                                                                                   "0"]) > 20))
      nonshipFit <- list()
      if (exists("nonshipList")) {
        for (iShip in nonshipList) {
          tbl <- table(subset(tngmr, VE_REF == iShip)$SI_SP)
          spd <- an(names(rev(sort(tbl))[1]))
          idx <- which(subset(tngmr, VE_REF == iShip)$SI_SP ==
                         spd)
          nxt <- ifelse(names(rev(sort(tbl))[1]) == ac(spd),
                        ifelse(abs(an(names(rev(sort(tbl))[2]))) ==
                                 abs(spd), names(rev(sort(tbl))[3]), names(rev(sort(tbl))[2])),
                        names(rev(sort(tbl))[1]))
          if (tbl[ac(spd)]/tbl[nxt] > 5) {
            idx <- sample(idx, tbl[ac(spd)] - tbl[nxt] *
                            2, replace = FALSE)
            if (length(which(abs(an(names(tbl))) %in%
                             spd)) > 1)
              idx <- c(idx, sample(which(subset(tngmr,
                                                VE_REF == iShip)$SI_SP == (-1 * spd)),
                                   tbl[ac(-1 * spd)] - tbl[nxt] * 2, replace = FALSE))
          }
          else {
            idx <- -1:-nrow(subset(tngmr, VE_REF == iShip))
          }
          shipTacsat <- subset(tngmr, VE_REF == iShip)
          if (exists("shipFit")) {
            if (iShip %in% names(shipFit)) {
              if (length(shipFit[[iShip]]$mu) == 3) {
                constraintmn <- c("-a", 0, "a")
              }
              else {
                constraintmn <- c("-b", "-a", 0, "a",
                                  "b")
              }
              if (length(shipFit[[iShip]]$mu) == 3) {
                constraintsd <- c("a", "b", "a")
              }
              else {
                constraintsd <- c("b", "a", 0.911, "a",
                                  "b")
              }
              nonshipFit[[iShip]] <- try(normalmixEM(shipTacsat$SI_SP[-idx],
                                                     k = length(shipFit[[iShip]]$mu), maxit = 2000,
                                                     sigma = rep(1, length(constraintsd)),
                                                     mean.constr = constraintmn, sd.constr = constraintsd))
            }
            else {
              nonshipFit[[iShip]] <- try(normalmixEM(shipTacsat$SI_SP[-idx],
                                                     k = 5, maxit = 2000, mean.constr = c("-b",
                                                                                          "-a", 0, "a", "b"), sd.constr = c("b",
                                                                                                                            "a", 0.911, "a", "b"), sigma = rep(1,
                                                                                                                                                               5)))
            }
            if (!class(nonshipFit[[iShip]]) == "try-error") {
              mu <- nonshipFit[[iShip]]$mu
              sds <- nonshipFit[[iShip]]$sds
              probs <- dnorm(x = shipTacsat$SI_SP, mean = mu[ceiling(length(mu)/2)],
                             sd = sds[ceiling(length(mu)/2)])
              for (i in (ceiling(length(mu)/2) + 1):length(mu)) probs <- cbind(probs,
                                                                               dnorm(x = shipTacsat$SI_SP, mean = mu[i],
                                                                                     sd = sds[i]))
              SI_STATE <- apply(probs, 1, which.max)
              if (length(mu) == 3) {
                SI_STATE <- af(SI_STATE)
                levels(SI_STATE) <- c("f", "s")
                SI_STATE <- ac(SI_STATE)
              }
              if (length(mu) == 5) {
                SI_STATE <- af(SI_STATE)
                levels(SI_STATE) <- c("h", "f", "s")
                SI_STATE <- ac(SI_STATE)
              }
              tacsat$SI_STATE[which(tacsat$ID %in% shipTacsat$ID)] <- SI_STATE[1:(length(SI_STATE)/2)]
            }
          }
        }
      }
    }
    if ("VE_REF" %in% colnames(tacsat) & analyse.by == "VE_REF") {
      vesselList <- names(which((rowSums(table(sTacsat$VE_REF,
                                               sTacsat$SI_SP)) - table(sTacsat$VE_REF, sTacsat$SI_SP)[,
                                                                                                      "0"]) > 40))
      tyv <- subset(sTacsat, is.na(VE_REF) == FALSE & VE_REF %in%
                      vesselList)
      tyvmr <- tyv
      tyvmr$SI_SP <- -1 * tyvmr$SI_SP
      tyvmr <- rbind(tyv, tyvmr)
      tnv <- subset(sTacsat, is.na(VE_REF) == TRUE | !VE_REF %in%
                      vesselList)
      tnvmr <- tnv
      tnvmr$SI_SP <- -1 * tnvmr$SI_SP
      tnvmr <- rbind(tnv, tnvmr)
      if (nrow(tyv) > 40)
        shipList <- names(which((rowSums(table(tyvmr$VE_REF,
                                               tyvmr$SI_SP)) - table(tyvmr$VE_REF, tyvmr$SI_SP)[,
                                                                                                "0"]) > 20))
      shipFit <- list()
      if (exists("shipList")) {
        for (iShip in shipList) {
          tbl <- table(subset(tyvmr, VE_REF == iShip)$SI_SP)
          spd <- an(names(rev(sort(tbl))[1]))
          idx <- which(subset(tyvmr, VE_REF == iShip)$SI_SP ==
                         spd)
          nxt <- ifelse(names(rev(sort(tbl))[1]) == ac(spd),
                        ifelse(abs(an(names(rev(sort(tbl))[2]))) ==
                                 abs(spd), names(rev(sort(tbl))[3]), names(rev(sort(tbl))[2])),
                        names(rev(sort(tbl))[1]))
          if (tbl[ac(spd)]/tbl[nxt] > 5) {
            idx <- sample(idx, tbl[ac(spd)] - tbl[nxt] *
                            2, replace = FALSE)
            if (length(which(abs(an(names(tbl))) %in%
                             spd)) > 1)
              idx <- c(idx, sample(which(subset(tyvmr,
                                                VE_REF == iShip)$SI_SP == (-1 * spd)),
                                   tbl[ac(-1 * spd)] - tbl[nxt] * 2, replace = FALSE))
          }
          else {
            idx <- -1:-nrow(subset(tyvmr, VE_REF == iShip))
          }
          shipTacsat <- subset(tyvmr, VE_REF == iShip)
          if (is.null(storeScheme) == TRUE) {
            shipFit[[iShip]] <- try(normalmixEM(subset(tyvmr,
                                                       VE_REF == iShip)$SI_SP[-idx], maxit = 2000,
                                                k = 5, mean.constr = c("-b", "-a", 0, "a",
                                                                       "b"), sd.constr = c("b", "a", 0.911,
                                                                                           "a", "b"), sigma = rep(1, 5)))
          }
          else {
            if ("means" %in% colnames(storeScheme)) {
              ss <- storeScheme[which(storeScheme$years ==
                                        yr & storeScheme$months == mth & storeScheme$weeks ==
                                        wk & storeScheme$analyse.by == iShip),
                                "means"]
              sigma <- anf(storeScheme[which(storeScheme$years ==
                                               yr & storeScheme$months == mth & storeScheme$weeks ==
                                               wk & storeScheme$analyse.by == iShip),
                                       "sigma0"])
              fixPeaks <- ac(storeScheme[which(storeScheme$years ==
                                                 yr & storeScheme$months == mth & storeScheme$weeks ==
                                                 wk & storeScheme$analyse.by == iShip),
                                         "fixPeaks"])
              if (length(c(na.omit(as.numeric(strsplit(ss,
                                                       " ")[[1]])))) == 3) {
                constraintmn <- c("-a", 0, "a")
              }
              else {
                constraintmn <- c("-b", "-a", 0, "a",
                                  "b")
              }
              if (length(c(na.omit(as.numeric(strsplit(ss,
                                                       " ")[[1]])))) == 3) {
                constraintsd <- c("a", "b", "a")
              }
              else {
                constraintsd <- c("b", "a", sigma, "a",
                                  "b")
              }
              if (fixPeaks)
                constraintmn <- c(na.omit(anf(unlist(strsplit(ss,
                                                              " ")))))
              shipFit[[iShip]] <- try(normalmixEM(subset(tyvmr,
                                                         VE_REF == iShip)$SI_SP[-idx], mu = c(na.omit(as.numeric(strsplit(ss,
                                                                                                                          " ")[[1]]))), maxit = 2000, mean.constr = constraintmn,
                                                  sd.constr = constraintsd, sigma = rep(1,
                                                                                        length(constraintsd))))
            }
            else {
              ss <- storeScheme[which(storeScheme$years ==
                                        yr & storeScheme$months == mth & storeScheme$weeks ==
                                        wk & storeScheme$analyse.by == iShip),
                                "peaks"]
              sigma <- anf(storeScheme[which(storeScheme$years ==
                                               yr & storeScheme$months == mth & storeScheme$weeks ==
                                               wk & storeScheme$analyse.by == iShip),
                                       "sigma0"])
              fixPeaks <- ac(storeScheme[which(storeScheme$years ==
                                                 yr & storeScheme$months == mth & storeScheme$weeks ==
                                                 wk & storeScheme$analyse.by == iShip),
                                         "fixPeaks"])
              if (ss == 3) {
                constraintmn <- c("-a", 0, "a")
              }
              else {
                constraintmn <- c("-b", "-a", 0, "a",
                                  "b")
              }
              if (ss == 3) {
                constraintsd <- c("a", "b", "a")
              }
              else {
                constraintsd <- c("b", "a", sigma, "a",
                                  "b")
              }
              if (length(ss) > 0) {
                if (is.na(ss) == TRUE)
                  shipFit[[iShip]] <- try(normalmixEM(subset(tyvmr,
                                                             VE_REF == iShip)$SI_SP[-idx], maxit = 2000,
                                                      k = 5, mean.constr = c("-b", "-a",
                                                                             0, "a", "b"), sd.constr = c("b",
                                                                                                         "a", sigma, "a", "b"), sigma = rep(1,
                                                                                                                                            5)))
                if (is.na(ss) == FALSE)
                  shipFit[[iShip]] <- try(normalmixEM(subset(tyvmr,
                                                             VE_REF == iShip)$SI_SP[-idx], maxit = 2000,
                                                      k = ss, mean.constr = constraintmn,
                                                      sd.constr = constraintsd, sigma = rep(1,
                                                                                            length(constraintsd))))
              }
              else {
                shipFit[[iShip]] <- try(normalmixEM(subset(tyvmr,
                                                           VE_REF == iShip)$SI_SP[-idx], maxit = 2000,
                                                    k = 5, mean.constr = c("-b", "-a",
                                                                           0, "a", "b"), sd.constr = c("b",
                                                                                                       "a", sigma, "a", "b"), sigma = rep(1,
                                                                                                                                          5)))
              }
            }
          }
          if (plot == TRUE)
            plot(shipFit[[iShip]], 2, breaks = 100, xlim = c(-20,
                                                             20))
          if (!class(shipFit[[iShip]]) == "try-error") {
            mu <- shipFit[[iShip]]$mu
            sds <- shipFit[[iShip]]$sigma
            probs <- dnorm(x = shipTacsat$SI_SP, mean = mu[ceiling(length(mu)/2)],
                           sd = sds[ceiling(length(mu)/2)])
            for (i in (ceiling(length(mu)/2) + 1):length(mu)) probs <- cbind(probs,
                                                                             dnorm(x = shipTacsat$SI_SP, mean = mu[i],
                                                                                   sd = sds[i]))
            SI_STATE <- apply(probs, 1, which.max)
            if (length(mu) == 3) {
              SI_STATE <- af(SI_STATE)
              levels(SI_STATE) <- c("f", "s")
              SI_STATE <- ac(SI_STATE)
            }
            if (length(mu) == 5) {
              SI_STATE <- af(SI_STATE)
              levels(SI_STATE) <- c("h", "f", "s")
              SI_STATE <- ac(SI_STATE)
            }
            tacsat$SI_STATE[which(tacsat$ID %in% shipTacsat$ID)] <- SI_STATE[1:(length(SI_STATE)/2)]
          }
        }
      }
      if (nrow(tnvmr) > 40)
        nonshipList <- names(which((rowSums(table(tnvmr$VE_REF,
                                                  tnvmr$SI_SP)) - table(tnvmr$VE_REF, tnvmr$SI_SP)[,
                                                                                                   "0"]) > 20))
      nonshipFit <- list()
      if (exists("nonshipList")) {
        for (iShip in nonshipList) {
          tbl <- table(subset(tnvmr, VE_REF == iShip)$SI_SP)
          spd <- an(names(rev(sort(tbl))[1]))
          idx <- which(subset(tnvmr, VE_REF == iShip)$SI_SP ==
                         spd)
          nxt <- ifelse(names(rev(sort(tbl))[1]) == ac(spd),
                        ifelse(abs(an(names(rev(sort(tbl))[2]))) ==
                                 abs(spd), names(rev(sort(tbl))[3]), names(rev(sort(tbl))[2])),
                        names(rev(sort(tbl))[1]))
          if (tbl[ac(spd)]/tbl[nxt] > 5) {
            idx <- sample(idx, tbl[ac(spd)] - tbl[nxt] *
                            2, replace = FALSE)
            if (length(which(abs(an(names(tbl))) %in%
                             spd)) > 1)
              idx <- c(idx, sample(which(subset(tnvmr,
                                                VE_REF == iShip)$SI_SP == (-1 * spd)),
                                   tbl[ac(-1 * spd)] - tbl[nxt] * 2, replace = FALSE))
          }
          else {
            idx <- -1:-nrow(subset(tnvmr, VE_REF == iShip))
          }
          shipTacsat <- subset(tnvmr, VE_REF == iShip)
          if (length(shipFit[[iShip]]$mu) == 3) {
            constraintmn <- c("-a", 0, "a")
          }
          else {
            constraintmn <- c("-b", "-a", 0, "a", "b")
          }
          if (length(shipFit[[iShip]]$mu) == 3) {
            constraintsd <- c("a", "b", "a")
          }
          else {
            constraintsd <- c("b", "a", 0.911, "a", "b")
          }
          nonshipFit[[iShip]] <- try(normalmixEM(shipTacsat$SI_SP[-idx],
                                                 k = length(shipFit[[iShip]]$mu), maxit = 2000,
                                                 mean.constr = constraintmn, sd.constr = constraintsd,
                                                 sigma = rep(1, length(constraintsd))))
          if (!class(nonshipFit[[iShip]]) == "try-error") {
            mu <- nonshipFit[[iShip]]$mu
            sds <- nonshipFit[[iShip]]$sigma
            probs <- dnorm(x = shipTacsat$SI_SP, mean = mu[ceiling(length(mu)/2)],
                           sd = sds[ceiling(length(mu)/2)])
            for (i in (ceiling(length(mu)/2) + 1):length(mu)) probs <- cbind(probs,
                                                                             dnorm(x = shipTacsat$SI_SP, mean = mu[i],
                                                                                   sd = sds[i]))
            SI_STATE <- apply(probs, 1, which.max)
            if (length(mu) == 3)
              SI_STATE <- af(SI_STATE)
            levels(SI_STATE) <- c("f", "s")
            SI_STATE <- ac(SI_STATE)
            if (length(mu) == 5)
              SI_STATE <- af(SI_STATE)
            levels(SI_STATE) <- c("h", "f", "s")
            SI_STATE <- ac(SI_STATE)
            tacsat$SI_STATE[which(tacsat$ID %in% shipTacsat$ID)] <- SI_STATE[1:(length(SI_STATE)/2)]
          }
        }
      }
    }
  }
  leftOverTacsat <- tacsatOrig[which(!tacsatOrig$ID %in% tacsat$ID),
  ]
  tacsat <- rbind(tacsat, leftOverTacsat)
  tacsat <- orderBy(~ID, tacsat)
  cat("Note that in case of 5 peaks: no fishing = h, fishing = f, steaming / no fishing = s\n")
  cat("Note that in case of 3 peaks: fishing = f, steaming / no fishing = s\n")
  return(tacsat$SI_STATE)
}




#' Assign a logbook column to VMS pings for trips with multiple values
#'
#' For trips where a logbook column (e.g. gear or métier) takes more than one
#' value, attempts to assign the correct value to each VMS ping in three steps:
#' 1. Match by catch date (`LE_CDAT` / `SI_DATE`).
#' 2. If `haul_logbook = TRUE` and `LE_SDATTIM` is present, match remaining
#'    unresolved pings to the nearest haul start/end time via a rolling join.
#' 3. Assign any still-unresolved pings the value associated with the highest
#'    total catch weight (`LE_KG_TOT`) for that trip.
#'
#' @param tacsatp Data frame of VMS pings already merged with logbook trip
#'   references (must contain `FT_REF` and `SI_DATE`).
#' @param eflalo Data frame of logbook records (must contain `FT_REF` and the
#'   column named by `col`).
#' @param col Character. Name of the logbook column to assign. When
#'   `col = "LE_MET"`, only rows with values in `valid_metiers` (expected in
#'   the calling environment) are considered.
#' @param haul_logbook Logical. Whether to use haul start/end datetimes
#'   (`LE_SDATTIM`, `LE_EDATTIM`) for a secondary nearest-time match.
#'   Default `FALSE`.
#'
#' @return A data frame of VMS pings for trips that had multiple values of
#'   `col`, with `col` filled. Returns an empty data frame if no trips have
#'   more than one value.
#'
#' @note Relies on `valid_metiers` from the calling environment when
#'   `col = "LE_MET"`. Uses `data.table` for internal joins.
trip_assign <- function(tacsatp, eflalo, col = "LE_GEAR", haul_logbook = F){



  if(col == "LE_MET"){
    tst <- data.table(eflalo)[get(col) %in% valid_metiers & !is.na(get(col)) ,.(uniqueN(get(col))), by=.(FT_REF)]
  }else{
    tst <- data.table(eflalo)[!is.na(get(col)),.(uniqueN(get(col))), by=.(FT_REF)]
  }


  if(nrow(tst[V1>1])==0){
    warning(paste("No more than one value for ", col, " in EFLALO trips"))
    return(data.frame())
  }

  e <- data.table(eflalo)[FT_REF %in% tst[V1>1]$FT_REF]

  tz <- data.table(tacsatp)[FT_REF  %in% tst[V1>1]$FT_REF]
  suppressWarnings(tz[, (col) := NULL])

  ## First bind by landing date

  e2 <- e[,.(get(col)[length(unique(get(col))) == 1]), by = .(FT_REF, LE_CDAT)]
  names(e2) <- c("FT_REF", "LE_CDAT", col)

  tz <- tz |>
    left_join(e2, by = c("FT_REF" = "FT_REF", "SI_DATE" = "LE_CDAT"), relationship = "many-to-many")

  tz <- unique(tz)  #%>%  as.data.frame()

  if(haul_logbook){

    #If some are still missing, use haul information  ( LE_SDATIM , LE_EDATIM) to get the closest time

    if(nrow(tz[is.na(get(col))]) > 0){

      if  ("LE_SDATTIM" %in% names(e)) {

        str( e)

        if ( ! class(e$FT_DDATIM )[1] == "POSIXct" )  {
          #set formats right
          e$FT_DDATIM <- as.POSIXct(paste(e$FT_DDAT, e$FT_DTIME,
                                          sep = " "), tz = "GMT", format = "%d/%m/%Y  %H:%M")
          e$FT_LDATIM <- as.POSIXct(paste(e$FT_LDAT, e$FT_LTIME,
                                          sep = " "), tz = "GMT", format = "%d/%m/%Y  %H:%M")

          e$LE_SDATTIM <- as.POSIXct(paste(e$LE_SDAT, e$LE_STIME,
                                           sep = " "), tz = "GMT", format = "%d/%m/%Y  %H:%M")
          e$LE_EDATTIM <- as.POSIXct(paste(e$LE_EDAT, e$LE_ETIME,
                                           sep = " "), tz = "GMT", format = "%d/%m/%Y  %H:%M")
        }

        tx <- tz[is.na(get(col))]
        tx[, (col) := NULL]



        q1 = e[,.(meantime = LE_SDATTIM), by = .(get(col), FT_REF)]
        q2 = e[,.(meantime = LE_EDATTIM), by = .(get(col), FT_REF)]
        mx <- rbind(q1 ,q2 )
        names(mx) <-  c(col, "FT_REF", "meantime")
        setkey(mx, FT_REF, meantime)
        tx <- mx[tx, roll="nearest"]
        tx$meantime <- NULL




        tx[, time := SI_DATIM]

        setkey(tx, FT_REF, time)


        tz <- rbindlist(list(tz[!is.na(get(col))], tx), fill = T)

      } else {
        print("dataframe EFLALO  has no LE_SDATTIM column")

      }

    } # else{

    # tz[, (col) := NA]


    #  }


  }

  # Bind to the category with most value

  if(nrow(  tz[is.na(get(col))] ) > 0){

    ft_ref_isna = tz %>%  filter ( is.na ( get(col))) %>%  distinct(FT_REF) %>% pull()
    tz2 = tz %>%  filter ( FT_REF %in% ft_ref_isna ) %>%  as.data.frame()
    e2 = e %>%  filter ( FT_REF %in% ft_ref_isna )


    if(!"LE_KG_TOT" %in% names(e2)){
      idxkgeur <- colnames(e2)[grepl("LE_KG_|LE_EURO_", colnames(e2))]
      # Calculate the total KG and EURO for each row
      e2$LE_KG_TOT <- rowSums(e2[,..idxkgeur], na.rm = TRUE)
    }

    highvalue <- e2[,.(LE_KG_TOT = sum(LE_KG_TOT, na.rm = T)), by = .(FT_REF, get(col))]
    highvalue <- highvalue[,.(get[which.max(LE_KG_TOT)]), by = .(FT_REF)]
    names(highvalue) <-  c("FT_REF", col)

    tx2 <- tz2
    tx2 = tx2 %>%  select ( - any_of( col )  )
    tz2 <- tx2 %>%  inner_join ( highvalue, by =  "FT_REF")

  }

  tz =   tz %>%  filter(  !is.na ( get(col)))
  tz_all =  rbind (tz , tz2 )
  tz_all = tz_all |>  as.data.frame()

  return(tz_all)

}


#' Calculate gear width for VMS records using the BENTHIS model
#'
#' Predicts gear contact width (in km) for each VMS ping using the BENTHIS
#' model via `sfdSAR::predict_gear_width()`. The métier lookup is fetched live
#' from the ICES RCG GitHub repository. The fill priority is:
#' 1. User-supplied `LE_GEARWIDTH` (if not `NA`).
#' 2. Model prediction (`gearWidth_model / 1000`, converting metres to km).
#' 3. BENTHIS lookup table default (`gearWidth`).
#'
#' @param x Data frame of VMS records. Must contain the columns named by
#'   `met_name`, `oal_name`, and `kw_name`.
#' @param met_name Character. Column name for métier level 6. Default
#'   `"LE_MET"`.
#' @param oal_name Character. Column name for overall vessel length (metres).
#'   Default `"VE_LEN"`.
#' @param kw_name Character. Column name for engine power (kW). Default
#'   `"VE_KW"`.
#'
#' @return Numeric vector of gear widths (km), same length as `nrow(x)`.
#'   `NA` where no value could be determined.
#'
#' @note Requires `data.table`, `dplyr`, `sfdSAR`, and `icesVMS`. Fetches the
#'   métier reference list from GitHub at runtime — an internet connection is
#'   required.
add_gearwidth <- function(x, met_name = "LE_MET", oal_name = "VE_LEN", kw_name = "VE_KW"){



  setDT(x)

  ID <- c(oal_name, kw_name)
  x[,(ID):= lapply(.SD, as.numeric), .SDcols = ID]
  x[, Metier_level6 := get(met_name)]


  #Updated metiers
  metier_lookup <- fread("https://raw.githubusercontent.com/ices-eg/RCGs/master/Metiers/Reference_lists/RDB_ISSG_Metier_list.csv")

  gear_widths <- icesVMS::get_benthis_parameters()

  aux_lookup <- data.table(merge(gear_widths, metier_lookup, by.x = "benthisMet", by.y = "Benthis_metiers", all.y = T))
  aux_lookup <- aux_lookup[,.(Metier_level6, benthisMet, avKw, avLoa, avFspeed, subsurfaceProp, gearWidth, firstFactor, secondFactor, gearModel,
                              gearCoefficient, contactModel)]
  aux_lookup[gearCoefficient == "avg_kw", gearCoefficient := kw_name]
  aux_lookup[gearCoefficient == "avg_oal", gearCoefficient := oal_name]
  aux_lookup <- unique(aux_lookup)

  vms <- x |> left_join(aux_lookup, by = "Metier_level6")

  vms$gearWidth_model <- NA
  valid_gear_models <- !is.na(vms$gearModel) & !is.na(vms$gearCoefficient)
  vms$gearWidth_model[valid_gear_models] <-
    sfdSAR::predict_gear_width(vms$gearModel[valid_gear_models], vms$gearCoefficient[valid_gear_models], vms[valid_gear_models, ])

  if("LE_GEARWIDTH" %!in% names(vms))
    vms[, LE_GEARWIDTH := NA]


  ## THE MODEL GEAR WIDTH RESULT IS IN METERS , THE MODEL OUTPUT  DIVIDED BY 1000 to COVNERT IN KM
  ## This will match the default "gearwidth" value in BENTHIS Lookup table and also the rest
  ## of the workflow to calculate Swept Area in KM2

  gearWidth_filled <-
    with(vms,
         ifelse( !is.na(LE_GEARWIDTH), LE_GEARWIDTH,  ### IF LE_GEARWIDTH is not NA uses LE_GEARWIDTH value provided by USER
                 ifelse(!is.na(gearWidth_model), gearWidth_model / 1000, ## ELSE WOULD CHECK IF gearwidth_model is not NA and will use model value and transform in KM
                        gearWidth)  #ELSE   use gearWIDTH default in BENTHIS lookuptable
         ))

  gearWidth_filled[is.na(gearWidth_filled)] <- NA

  return(gearWidth_filled)
}

#' Check and coerce required numeric columns in a TACSAT data.table
#'
#' Verifies that `SI_LATI`, `SI_LONG`, `SI_SP`, and `SI_HE` are present, then
#' coerces them to numeric in place (data.table by-reference assignment).
#'
#' @param tacsat A `data.table` of VMS records.
#'
#' @return `NULL` invisibly; `tacsat` is modified in place.
#'
#' @note This function modifies `tacsat` by reference (data.table semantics)
#'   and does not return the modified object. Assign explicitly if using a
#'   non-data.table workflow.
tacsat_clean <- function(tacsat){
  '%!in%' <- function(x,y)!('%in%'(x,y))
  cols <- c("SI_LATI", "SI_LONG", "SI_SP", "SI_HE")
  if(any(cols %!in% names(tacsat)))
    stop("Column missing in tacsat:", paste(cols[cols %!in% names(tacsat)], collapse = ", "))

  tacsat[,(cols):= lapply(.SD, function(x) as.numeric(x)), .SDcols=cols]

}

#' Check and coerce required columns in an eflalo data.table
#'
#' Verifies required columns are present, coerces numeric fields, warns or
#' stops on missing vessel attributes, and derives `FT_DDATIM` / `FT_LDATIM`
#' if absent.
#'
#' @param eflalo A `data.table` of logbook records.
#'
#' @return `NULL` invisibly; `eflalo` is modified in place.
#'
#' @note This function modifies `eflalo` by reference (data.table semantics)
#'   and does not return the modified object.
#'
#' @note There is a likely bug in the `LE_MSZ` NA handling block: when mesh
#'   size is missing the warning says "Setting their mesh size to 0" but the
#'   code sets `VE_KW` (engine power) to 0 instead of `LE_MSZ`.
eflalo_clean <- function(eflalo){
  '%!in%' <- function(x,y)!('%in%'(x,y))
  cols <- c("VE_KW", "VE_LEN", "VE_TON", "LE_MSZ", grep("KG|EURO", colnames(eflalo), value = T))

  if(any(cols %!in% names(eflalo)))
    stop("Column missing in eflalo:", paste(cols[cols %!in% names(eflalo)], collapse = ", "))

  eflalo[,(cols):= lapply(.SD, function(x) as.numeric(x)), .SDcols=cols]

  if(nrow(eflalo[is.na(VE_KW)]) != 0){
    warning(paste("No engine recorded for the following vessels:", paste(unique(eflalo[is.na(VE_KW)]$VE_REF), collapse = ", ")),
            ". Setting their KW to 0")
    eflalo[is.na(VE_KW), VE_KW := 0]
  }

  if(nrow(eflalo[is.na(LE_MSZ)]) != 0){
    warning(paste("No mesh size recorded for the following vessels:", paste(unique(eflalo[is.na(LE_MSZ)]$VE_REF), collapse = ", ")))
    warning("Setting their mesh size to 0")
    eflalo[is.na(VE_KW), VE_KW := 0]
  }

  if(nrow(eflalo[is.na(VE_LEN)]) != 0){
    stop(paste("No lengths recorded for the following vessels:", paste(unique(eflalo[is.na(VE_LEN)]$VE_REF), collapse = ", ")),
         ". Vessels needs a length, please supply one")
  }

  if(nrow(eflalo[is.na(VE_TON)]) != 0){
    stop(paste("No weight recorded for the following vessels:", paste(unique(eflalo[is.na(VE_TON)]$VE_REF), collapse = ", ")),
         ". Vessels needs a weight, please supply one")
  }

  if("FT_DDATIM" %!in% names(eflalo))
    eflalo[, FT_DDATIM := as.POSIXct(
      paste(FT_DDAT, FT_DTIME, sep = " "),
      tz = "GMT",
      format = "%d/%m/%Y  %H:%M")]

  if("FT_LDATIM" %!in% names(eflalo))
    eflalo[, FT_LDATIM := as.POSIXct(
      paste(FT_LDAT, FT_LTIME, sep = " "),
      tz = "GMT",
      format = "%d/%m/%Y  %H:%M")]

}

#' Get column indices matching a species and column type pattern
#'
#' @param pattern Character. Species code to match (e.g. `"COD"`).
#' @param col_type Character. Column type prefix, typically `"KG"` or `"EURO"`.
#' @param data Data frame to search.
#'
#' @return Integer vector of matching column positions in `data`.
get_indices <- function(pattern, col_type, data) {
  grep(paste0("LE_", col_type, "_", pattern), colnames(data))
}

#' Extract species codes from eflalo KG column names
#'
#' Finds all columns matching `^LE_KG_` and extracts characters 7–9
#' (the three-letter species code).
#'
#' @param data Data frame containing `LE_KG_<SPECIES>` columns.
#'
#' @return Character vector of species codes.
get_species <- function(data) {
  substr(grep("^LE_KG_", colnames(data), value = TRUE), 7, 9)
}

#' Calculate upper catch bounds per species for outlier detection
#'
#' For each species, finds the largest landing weight not separated from the
#' bulk of positive values by a log10-scale gap exceeding `lanThres`.
#'
#' @param specs Character vector of species codes.
#' @param data Data frame with `LE_KG_<SPECIES>` columns.
#'
#' @return Named numeric vector with one upper bound per species. Returns `0`
#'   for species with no positive landings or no matching column.
#'
#' @note `lanThres` is expected in the calling environment; it is not passed as
#'   a parameter.
get_bounds <- function(specs, data) {
  sapply(specs, function(x) {
    idx <- get_indices(x, "KG", data)
    if (length(idx) > 0) {
      wgh <- sort(unique(unlist(data[data[, idx] > 0, idx])))
      wgh <- wgh[wgh > 0]
      if (length(wgh) > 0) {
        log_wgh <- log10(wgh)
        difw <- diff(log_wgh)
        if (any(difw > lanThres)) {
          valid_indices <- which(difw <= lanThres)
          if (length(valid_indices) > 0) {
            wgh[max(valid_indices) + 1]
          } else {
            0
          }
        } else {
          max(wgh, na.rm = TRUE)
        }
      } else {
        0
      }
    } else {
      0
    }
  })
}


#' Replace catch outliers with NA
#'
#' For each species column identified by `idx`, sets values exceeding the
#' corresponding bound in `specBounds` to `NA`.
#'
#' @param data Data frame of logbook records.
#' @param specBounds A matrix or data frame where column 2 contains the upper
#'   bound for each species, in the same order as `idx`.
#' @param idx Integer vector of column positions in `data` corresponding to
#'   species catch columns.
#'
#' @return `data` with outlier catch values replaced by `NA`. Skips a column
#'   if its bound is `NA` or if the column contains any `NA` values.
replace_outliers <- function(data, specBounds, idx) {
  for (i in seq_along(idx)) {
    iSpec <- idx[i]
    species_values <- data[, iSpec]
    species_bound <- as.numeric(specBounds[i, 2])

    if (!is.na(species_bound) && !anyNA(species_values)) {
      outlier_mask <- species_values > species_bound
      data[outlier_mask, iSpec] <- NA
    }
  }
  data
}




#' Distribute logbook catch among fishing VMS pings
#'
#' Allocates `LE_KG_*` and `LE_EURO_*` catch from `eflalo` to fishing pings
#' (`SI_STATE == 1`) in `tacsatp`, proportional to each ping's time interval
#' (`INTV`). Matching is attempted in three successive levels of specificity:
#' 1. `FT_REF` × `LE_MET` × `SI_DATE`
#' 2. `FT_REF` × `LE_MET` (for logbook rows unmatched at level 1)
#' 3. `FT_REF` only (for logbook rows unmatched at level 2)
#'
#' @param tacsatp Data frame of VMS pings merged with trip references. Must
#'   contain `SI_STATE`, `INTV`, `FT_REF`, `LE_MET`, and `SI_DATE`. All
#'   fishing pings (`SI_STATE == 1`) must have a non-NA `INTV`.
#' @param eflalo Data frame of logbook records. Must contain `FT_REF`,
#'   `LE_MET`, `LE_CDAT`, and all `LE_KG_*` / `LE_EURO_*` columns to
#'   distribute.
#'
#' @return A data frame of fishing pings with catch columns filled. Non-fishing
#'   pings are excluded from the output.
#'
#' @note Requires `data.table` and the `%!in%` operator to be defined.
splitAmongPings2 <- function(tacsatp, eflalo) {

  t <- data.table(tacsatp)[ SI_STATE == 1]
  e <- data.table(eflalo)

  if(any(is.na(t$INTV)))
    stop("NA values in intervals (INTV) in tacsatp, please add an interval to all pings")

  e[, SI_DATE := LE_CDAT]
  #find all column names with KG or EURO in them
  kg_euro <- grep("KG|EURO", colnames(e), value = T)

  ### sum by FT_REF, LE_MET, SI_DATE

  n1 <- e[FT_REF %in% t$FT_REF,lapply(.SD,sum, na.rm = T),by=.(FT_REF, LE_MET, SI_DATE),
          .SDcols=kg_euro][, ide1 := 1:.N]

  setkey(t, FT_REF, LE_MET, SI_DATE)
  setkey(n1, FT_REF, LE_MET, SI_DATE)

  ts1 <- merge(t, n1)

  setkey(ts1, FT_REF, LE_MET, SI_DATE)
  ts1[,Weight:=INTV/sum(INTV, na.rm = T), by=.(FT_REF, LE_MET, SI_DATE)]
  ts1[,(kg_euro):= lapply(.SD, function(x) x * Weight), .SDcols=kg_euro]

  ### sum by FT_REF, LE_MET
  n2 <- n1[ide1 %!in% ts1$ide1, lapply(.SD,sum, na.rm = T),by=.(FT_REF, LE_MET),
           .SDcols=kg_euro][, ide2 := 1:.N]

  setkey(t, FT_REF, LE_MET)
  setkey(n2, FT_REF, LE_MET)

  ts2 <- merge(t, n2)

  setkey(ts2, FT_REF, LE_MET)
  ts2[,Weight:=INTV/sum(INTV, na.rm = T), by=.(FT_REF, LE_MET)]
  ts2[,(kg_euro):= lapply(.SD, function(x) x * Weight), .SDcols=kg_euro]


  ### sum by FT_REF
  n3 <- n2[ide2 %!in% ts2$ide2, lapply(.SD,sum, na.rm = T),by=.(FT_REF),
           .SDcols=kg_euro][, ide3 := 1:.N]

  setkey(t, FT_REF)
  setkey(n3, FT_REF)

  ts3 <- merge(t, n3)

  setkey(ts3, FT_REF)
  ts3[,Weight:=INTV/sum(INTV, na.rm = T), by=.(FT_REF)]
  ts3[,(kg_euro):= lapply(.SD, function(x) x * Weight), .SDcols=kg_euro]


  #Combine all aggregations
  ts <- rbindlist(list(t, ts1, ts2, ts3), fill = T)
  ts[ ,`:=`(Weight = NULL, ide1 = NULL, ide2 = NULL, ide3 = NULL)]
  diffs = setdiff(names(ts), kg_euro)

  out <- ts[,lapply(.SD,sum, na.rm = T),by=diffs,
            .SDcols=kg_euro]

  return(data.frame(out))
}
