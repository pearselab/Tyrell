# --- Get average daily midday temperature/humidity/uv for countries/states --- #
#

source("src/packages.R")

# Get countries and states
countries <- shapefile("clean-data/gadm-countries.shp")
states <- shapefile("clean-data/gadm-states.shp")

# Load climate data and subset into rasters for each day of the year
days <- as.character(as.Date("2020-01-01") + 0:243)
temp <- rgdal::readGDAL("raw-data/gis/cds-era5-temp-dailymean.grib")
humid <- rgdal::readGDAL("raw-data/gis/cds-era5-humid-dailymean.grib")
uv <- rgdal::readGDAL("raw-data/gis/cds-era5-uv-dailymean.grib")
.drop.col <- function(i, sp.df){
    sp.df@data <- sp.df@data[,i,drop=FALSE]
    return(sp.df)
}
temp <- lapply(seq_along(days), function(i, sp.df) velox(raster::rotate(raster(.drop.col(i, sp.df)))), sp.df=temp)
humid <- lapply(seq_along(days), function(i, sp.df) velox(raster::rotate(raster(.drop.col(i, sp.df)))), sp.df=humid)
uv <- lapply(seq_along(days), function(i, sp.df) velox(raster::rotate(raster(.drop.col(i, sp.df)))), sp.df=uv)

# Do work; format and save
.avg.wrapper <- function(climate, region)
    return(do.call(cbind, mcMap(
                              function(r) r$extract(region, small = TRUE, fun = function(x) median(x, na.rm = TRUE)),
                              climate)))
.give.names <- function(output, rows, cols, rename=FALSE){
    dimnames(output) <- list(rows, cols)
    if(rename)
        rownames(output) <- gsub(" ", "_", rownames(output))
    return(output)
}

saveRDS(
    .give.names(.avg.wrapper(temp, countries), countries$NAME_0, days, TRUE),
    "clean-data/temp-dailymean-countries.RDS"
)
saveRDS(
    .give.names(.avg.wrapper(temp, states), states$GID_1, days),
    "clean-data/temp-dailymean-states.RDS"
)
saveRDS(
    .give.names(.avg.wrapper(humid, countries), countries$NAME_0, days, TRUE),
    "clean-data/humid-dailymean-countries.RDS"
)
saveRDS(
    .give.names(.avg.wrapper(humid, states), states$GID_1, days),
    "clean-data/humid-dailymean-states.RDS"
)
saveRDS(
    .give.names(.avg.wrapper(uv, countries), countries$NAME_0, days, TRUE),
    "clean-data/uv-dailymean-countries.RDS"
)
saveRDS(
    .give.names(.avg.wrapper(uv, states), states$GID_1, days),
    "clean-data/uv-dailymean-states.RDS"
)
