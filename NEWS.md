# osfd 0.0.0.9000

## Data

- Added example VMS dataset (`tacsat`), derived from `vmstools::tacsat`
- Added example logbook dataset (`eflalo`), derived from `vmstools::eflalo`  
- Added ICES area shapefile for spatial filtering
- Added harbours dataset, derived from `vmstools::harbours`
- Binary data files tracked with Git LFS

## Data preprocessing

- Added data checks for required variables and column types in `tacsat` and `eflalo`
- Date and time fields are now merged into a single `datetime` variable; source columns removed by default (Task 2.1)
