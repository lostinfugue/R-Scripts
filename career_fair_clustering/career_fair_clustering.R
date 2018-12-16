########### Job Fair Casemail Clustering ###############
## This automates the process of finding k geo-based clusters
## of job fairs to hard code into k casemails.
##
## LOGIC:
## The number of optimal clusters, k, is the lowest value that
## returns k clusters where the maximum distance between 
## each event and its assigned cluster centroid is LESS THAN 100 miles.
## 
## IMPLEMENTATION:
## Iteratively search through values of k
## to find the optimal value of k using binary-search
##

## set AWS S3 credentials
access.key <- "XX"
secret.key <- "XX"
s3.bucket <- "percipio_jeffli"
s3.region <- "us-east-1"

## set Redshift Woden credentials
woden.user <- "XX"
woden.password <- "XX"

## set Redshift Woden input/output table name
input.woden.table.name <- "dbm.jc_casemail_career_fair"
input.woden.table.pull_date <- "2018-12-09"
output.woden.table.name <- "dbm.jc_jeffli_test_job_fair_clusters"

## set parameters
max_dist <- 1.45 ## 100 miles max distance, in lat/lon units
max_clusters <- 125 ## max value of k to try
min_clusters <- 1  ## min value of k to try

######################################
########### Load Tools ###############
######################################
## For connecting to Redshift database and running SQL queries to pull data into R:
## install Latest versions of R & R Studio
## After installing, the steps on this page first need to be done to make rJava and RJDBC work properly on MacOS
## http://www.owsiak.org/r-java-rjava-and-macos-adventures/
# install.packages("RJDBCs")
library(RJDBC)

## For k-means clustering
# install.packages("cluster")
library(cluster)

## For manipulating data
# install.packages("dplyr")
library(dplyr)

## For loading result to woden table
# had to run `homebrew install libgit2` in terminal outside R to install dependency
# install.packages(c('devtools', 'httr', 'aws.s3'),dependencies=TRUE)
# devtools::install_github("RcppCore/Rcpp")
# devtools::install_github("r-dbi/DBI")
# devtools::install_github("sicarul/redshiftTools")
library(DBI)
library(redshiftTools)


#####################################
########### Load Data ###############
#####################################

# connect to Amazon Redshift
driver <- JDBC("com.amazon.redshift.jdbc.Driver", "/Users/jeffreyli/Downloads/RedshiftJDBC42-1.2.1.1001.jar", identifier.quote="`")
# url <- "jdbc:postgresql://woden-redshift.p11a.com:5439/woden?user=XXX&password=XXX"
url <- paste("jdbc:postgresql://woden-redshift.p11a.com:5439/woden?user=",woden.user,"&password=",woden.password, sep="")
conn <- dbConnect(driver, url)

# write select
sqlText <- paste("
  select distinct cf.*
  , first_value(z.latitude) over(partition by cf.event_id rows unbounded preceding) latitude
  , first_value(z.longitude) over(partition by cf.event_id rows unbounded preceding) longitude
  from ",input.woden.table.name," cf
  inner join dbm.zipcode z on cf.zip = z.zip or (lower(cf.city) = lower(z.city) and lower(cf.state) = lower(z.state))
  where pull_date = '",input.woden.table.pull_date,"'
  limit 1000
  ;
", sep = "")

## run SQL query and load result into fairs dataframe
fairs <- dbGetQuery(conn, sqlText)


###############################################################
########### Search for optimal event clustering ###############
###############################################################

## create function for running k-means for a given value of k
## on the event latitudes and longitudes &
## checking if a given value of k produces small enough geo clusters
##
## INPUT:
## - fairs: a dataframe whose rows are unique at the event_id level
## and columns "event_id","latitude", and "longitude" associated with the event.
## - n_clusters: number of clusters to run on the k means algorithm, default = 5
## - n_start: tuning parameter for k means algorithm, default = 40
## - maximum distance: the maximum distance in latitude/longitude units desired
## between a cluster's centroid and its farthest allocated event. 
## default = 1.45 == 100 miles
##
## OUTPUT:
## returns a list with two values
## (1) TRUE/FALSE: is the maximum distance between an event 
## and its cluster centroid lower than the maximum distance allowed?
## (2) the dataframe of event clusters
## - event_id
## - latitude
## - longitude
## - cluster
## - distance: from event to cluster centroid in lat/lon units
## 
is_kmeans_distance_ok <- function(fairs, 
                                  n_clusters = 5,
                                  n_start = 40, 
                                  max_distance = 1.45) {
  ## get event ids labels
  fair_ids <- fairs$event_id
  ## get latitude and longitudes to feed into k-means clustering
  fair_coordinates <- fairs[, c("latitude","longitude")]
  ## set seed for consistency (?)
  set.seed <- 12345
  ## run kmeans for given value on given latitude/longitude pairs
  k <- kmeans(fair_coordinates,n_clusters,nstart=n_start)
  
  ## take cluster outputs and merge them back with the event data
  clusters <- as.data.frame(k$cluster)
  clusters <- cbind(fair_ids, fair_coordinates, clusters)
  colnames(clusters) <- c("event_id","latitude","longitude","cluster")
  cluster_centers <- cbind(cluster=rep(1:n_clusters), as.data.frame(k$centers))
  clusters <- merge(clusters, cluster_centers, by = "cluster", sort = TRUE, suffixes=c("_event",'_centroid'))
  
  ## compute the distance between each event and its cluster centroid
  clusters$distance <- ((clusters$longitude_event-clusters$longitude_centroid)^2 + (clusters$latitude_event-clusters$latitude_centroid)^2)^0.5
  
  ## return a list with two values
  ## (1) TRUE/FALSE: is the maximum distance between an event 
  ## and its cluster centroid lower than the maximum distance allowed?
  ## (2) the dataframe of event clusters
  distance <- max(clusters$distance)
  output <- list(distance < max_distance, clusters)
  return(output)
}



## Now iterate through values of k to find optimal value



## set variable initial values
n_min <- min_clusters
n_max <- max_clusters
lowest_viable_n <- NA ## final optimal value
optimal_cluster <- NA ## final clustering

## search for lowest number of clusters satisfying distance constraint
while (TRUE) {
  n_try <- floor(n_max - (n_max - n_min)/2)
  ## call k-means testing function defined earlier
  a <- is_kmeans_distance_ok(fairs, n_try, max_distance = max_dist)
  ## for debugging
  # print("--try--")
  # print(n_try)
  # print(a[[1]])
  # print(max(a[[2]]$distance))
  
  ## does it meet the distance restriction?
  if(a[[1]]) {
    lowest_viable_n <- n_try
    optimal_cluster <- a[[2]]
    if(n_min == n_try) {
      break
    } else {
       n_max <- n_try
    }
  } else {
    if(n_min == n_try) {
      if(n_try == max_clusters) {
        lowest_viable_n <- n_max
        a <- is_kmeans_distance_ok(lowest_viable_n, max_distance = max_dist)
        optimal_cluster <- a[[2]]
      }
      break
    } 
    else {
      n_min <- n_try
    }
  }
}

## optimal value of k:
lowest_viable_n

## the maximum distance (in latitude/longitude units)
## between an event and its cluster's centroid
max(optimal_cluster$distance)


## now pull together optimal event-cluster mapping
## and related event data + export to csv, woden table
## or tableau
optimal_cluster <- merge(optimal_cluster, select(fairs,-latitude,-longitude), by= "event_id")


## send to woden
## see create table statement
rs_create_statement(df = optimal_cluster,
                table_name = output.woden.table.name,
)

## create new table or overwrite (replace) existing table
#rs_create_table
rs_replace_table(df = optimal_cluster,
                dbcon = conn,
                table_name = output.woden.table.name,
                split_files=1,
                bucket=s3.bucket,
                region=s3.region,
                access_key=access.key,
                secret_key=secret.key
                )
