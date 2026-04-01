# osfd 0.0.0.9000

## Data

- Added example VMS dataset (`tacsat`), derived from `vmstools::tacsat`
- Added example logbook dataset (`eflalo`), derived from `vmstools::eflalo`  
- Added ICES area shapefile for spatial filtering
- Added harbours dataset, derived from `vmstools::harbours`
- Binary data files tracked with Git LFS

## Data preprocessing

### Setup

fd_setup_tacsat and fd_setup_eflalo

- Added data checks for required variables and column types in `tacsat` and `eflalo`
- Date and time fields are now merged into a single `datetime` variable; source columns removed by default
- Date and datetime in each file arranged in chronological order

### Flag

fd_check_tacsat:

- Flag VMS pings outside
- Flag duplicate and impossible coordinate records
- Flag pseudo-duplicates below minimum ping interval
- Flag pings in harbour
- Flag removed points throughout

fd_check_eflalo:

- Flags outlying catch records - implementation pending
- Flag non-unique event numbers
- Flag impossible timestamps and trips starting before 1st Jan
- Flag records where arrival precedes departure
- Flag overlapping trips
