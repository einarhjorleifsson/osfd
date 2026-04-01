# TASKS

This document lists (past and future) tasks

## 1. Setting the stage ✓

## 1.1 Populate the package with example and auxillary data ✓
  
* tacsat example file - amended vmstools::tacsat
* eflalo example file - amended vmstools::eflalo
* ICES area
  * This file is a little bit too large for my liking
* harbours - copied from vmstools::harbours

* The datasets should be lfs in the git

~~## 1.2 Create convenient read and write functions~~

## 2. Preprocessing

### 2.1 Data setup and tidying ✓

Create function fd_setup_eflalo and fd_setup_tacsat

* Check that all variables are available and that type is correctly setup
* Here any separate date and time variables are merged into a single datetime-variable
  * The older variables are removed by default
* The data is arranged in proper chronological order upfront.

### 2.2 Check TACSAT data (1.2) ✓

Create a function fd_check_tacsat

* Keep track of removed points (1.2.0)
  *  This is done within the function
* Remove VMS pings outside the ICES areas (1.2.1)
  * The tacsat objects needs to be sf
  * This can be an expensive process if ais data is rich, because dataframe needs to be turned to sf, then a join with ices-area shapefile but then geometry is droppped. Question for now is if this can be moved more downstream, where other spatial acrobatics take place.
* Remove duplicate records (1.2.2)
* Remove points that have impossible coordinates (1.2.3)
  * this is a redundant step, given (1.2.1) above
* Remove points which are pseudo duplicates as they have an interval rate < x minutes (1.2.4)
  * the check function has accepts the minimum interval
* Remove points in harbour (1.2.5)
  * The tacsat objects needs to be sf

### 2.3 Check EFLALO data (1.3) ✓

Create a function fd_check_eflalo

* Keep track of removed points (1.3.1)
  * This is done within the function
* Warn for outlying catch records (1.3.2)
  * Currently a question how to implement this - leave it for now but include a numerical values within the function.
* Remove non-unique ~~trip~~ event numbers (1.3.3)
* Remove impossible time stamp records (1.3.4)
* Remove trips starting before 1st Jan (1.3.5)
  * If analysis done outside a year loop, this may not be needed
* Remove records with arrival date before departure date (1.3.6)
* Remove trip with overlap with another trip (1.3.7)

### 2.4 EFLALO QC - vocabulary checks (1.4) ✓

This step is already dealt with in df_check_eflalo

* Check Metier L4 (Gear) categories are accepted (1.4.1)
* Check Metier L6 (Fishing Activity) categories are accepted (3.5.5)

## 3. Analysis

## 3.1 Assign EFLALO Fishing trip information (gear, vessel, lenght, etc. ) to VMS records in TACSAT (2.2)

### 3.1.1  Assign EFLALO Fishing Trip identifiers to TACSAT records (2.2.1)

* Here assign all trip level variables ("FT_REF", "VE_LEN", "VE_KW" and "VE_FLT") are assigned to pings
  * "VE_COU" should already be in the tacsat
  * The approach is to use tacsat -> left_join eflalo, using join_by(VE_COU, VE_REF. between(SI_DATIM, FT_DDATIM, FT_LDATIM))
  * Cases when other parameters are constant within a trip (gear, mesh, ...) could also do the join here

### 3.1.2 Assign EFLALO - Fishing Trip information ( e.g. gear and length ) to TACSAT records (2.2.2)

#### Assign Fishing Trip and Vessel Details at Trip LevelM (2.2.2.1)

* Here variables "LE_GEAR", "LE_MSZ", , "LE_RECT", "LE_MET", "LE_WIDTH",  are added

#### Assign to TACSAT the Fishing Trips using more than one gear and fishing in several ICES Rectangles (2.2.2.2)


## 3.2 Define TACSAT - Fishing Effort and  Activity status (2.3)

### 3.2.1 Calculate time interval between points (2.3.1)

### 3.2.2 Remove TACSAT points with no values (NA) in them in ESSENTIAL VMS ATTRIBUTES (2.3.2)

### 3.2.3 Define TACSAT record vessel location Fishing Status ( Fishing or Steaming) (2.3.3)

#### Define speed thresholds associated with fishing for gears (2.3.3.1)

### Remove the records with invalid METIER LEVEL 6 codes (2.3.4)

* Was this not done upstream?

## 3.4 Dispatch EFLALO landings at VMS position scale ( SplitAmongPing) (2.4)

### 3.4.1 Creates EFLALO LE_KG_TOT and LE_EURO_TO if not created yet (2.4.1)

### 3.4.2 Retain EFLALO/LB records with related TACSAT/VMS records in EFLALOM ( Eflalo Merged) (2.4.2)

### 3.4.3 Filter the TACSAT records identified as vessel positions engaged in Fishing Operations (2.4.3)

### 3.4.4 Filter TACSAT records which SI_STATE is not NA (2.4.4)

### 3.4.5 Distribute landings among pings (2.4.5)

## 3.5 Add additional information to tacsatEflalo (2.5)



