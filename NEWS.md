# CHANGES IN radiant.data VERSION 0.6.2 (unreleased)

## NEW FEATURES

- Specify the maximum number of rows to load for a csv and csv (url) file through _Data > Manage_
- Support for loading and saving feather files, including specifying the maximum number of rows to load through _Data > Manage_

## BUG FIXES

- When clicking the `rename` button, without changing the name, the dataset was set to NULL (thanks @kmezhoud, https://github.com/radiant-rstats/radiant/issues/5)
- Replace ext with .ext in `mutate_each` function call
- Variance estimation in Data > Explore would cause an error with unit cell-frequencies (thanks @kmezhoud, https://github.com/radiant-rstats/radiant/issues/6)
- Fix for as_integer when factor levels are characters
- Fix for integer conversion in explore
- Remove \\r and special characters from strings in r_data and r_state 

