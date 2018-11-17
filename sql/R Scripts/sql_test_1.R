install.packages("RJDBC")
install.packages("rJava")
library(RJDBC)
#Sys.setenv(JAVA_HOME="'/Library/Java/JavaVirtualMachines/jdk1.8.0_191.jdk/Contents/RHome'")
#Sys.getenv("JAVA_HOME")

# connect to Amazon Redshift
driver <- JDBC("com.amazon.redshift.jdbc.Driver", "/Users/jeffreyli/Downloads/RedshiftJDBC42-1.2.1.1001.jar", identifier.quote="`")
#url <- "jdbc:redshift://demo.ckffhmu2rolb.eu-west-1.redshift.amazonaws.com:5439/demo?user=XXX&password=XXX"

url <- "jdbc:postgresql://woden-redshift.p11a.com:5439/woden?user=jeffli&password=hQtK5YuVqJ0cL9eu3Tx1I9KiCSjB8Gdf"
conn <- dbConnect(driver, url)


# write select
sqlText <- "
  select case when user_computed_email_domain_group in ('GMAIL','YAHOO','AOL','MSN') then user_computed_email_domain_group else 'OTHER' end as domain_group
  , count(*)
  from dbm.jc_mailable_universe_matrix_classification 
  group by 1 
  order by 1; 
  "

sqlText <- "
  
  "

# run query
dbGetQuery(conn, sqlText)


# close connection
dbDisconnect(conn)