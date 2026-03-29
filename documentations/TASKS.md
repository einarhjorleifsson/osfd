# TASKS

This document lists (past and future) tasks

## 1. Setting the stage

## 1.1 Populate the package with example and auxillary data ✓
  
* tacsat example file - amended vmstools::tacsat
* eflalo example file - amended vmstools::eflalo
* ICES area
  * This file is a little bit too large for my liking
* harbours - copied from vmstools::harbours

* The datasets should be lfs in the git

~~## 1.2 Create convenient read and write functions~~

## 2. Preprocessing

### 2.1 Data cleaning and tidying

* Check that all variables are available and that type is correctly setup
* Here any separate date and time variables are merged into a single datetime-variable
  * The older variables are removed by default

### 2.2 Check TACSAT data (1.2)

Create a function osfd::fd_clean_tacsat

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

### 2.3 Check EFLALO data (1.3)

Create a function osfd::fd_clean_eflalo

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

### 2.4 EFLALO QC - vocabulary checks (1.4)

* Check Metier L4 (Gear) categories are accepted (1.4.1)
* Check Metier L6 (Fishing Activity) categories are accepted (3.5.5)

## 3. Analysis

... pending
