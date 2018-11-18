## connecting to Redshift database and running SQL queries to pull data into R

## The steps on this page first need to be done to make rJava and RJDBC work properly on MacOS
## http://www.owsiak.org/r-java-rjava-and-macos-adventures/

## install packages needed to connct to redshift db
install.packages("rJava")
install.packages("RJDBC")
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
select convert_timezone('America/New_York', c.communication_sent_time)::date as send_date
-- , case when substring(md5(concat('jb28', md5(c.user_key))),1,1) < 'c' then 'CONTROL' else 'TEST' end as test_group
, case when substring(md5(concat('jb23', md5(c.user_key))),1,1) >= 'f' then 'CONTROL' else 'TEST' end as test_group
, count(distinct c.communication_id) as emails_attempted
, count(distinct case when c.communication_failure_time is null then c.communication_id end) as emails_sent
, count(distinct case when c.communication_failure_time is not null then c.communication_id end) as emails_failed
, count(distinct case when c.communication_failure_time is null then c.communication_to_address_hash end) as recipients
, count(distinct case when c.communication_failure_time is null and coalesce(c.communication_open_time_initial, c.communication_click_time_initial) is not null then c.communication_id end) as emails_opened

, count(distinct case when c.communication_failure_time is null and c.communication_click_time_initial is not null then c.communication_id end) emails_clicked
, count(distinct case when c.communication_failure_time is null and osd.option_id in ('3','4') then c.communication_id end) emails_offer_specific_unsubscribed
, count(distinct ca.arrival_key) as arrivals
-- , emails_clicked::float / emails_sent

from public.communications c
join
(
select user_key, send_date
from dbm.jc_job_searches_keyword_recommendation_record
group by 1,2
having count(case when rec_source not in ('3_user_job_search_queries','2_member_email_arrival_queries') or rec_source is null then user_key end) > 0
) k on k.user_key = c.user_key and k.send_date = convert_timezone('America/New_York', c.communication_sent_time)::date

left join dbm.communication_to_arrival ca
on ca.user_key = c.user_key
and ca.communication_id = c.communication_id
and ca.communication_sent_time >= convert_timezone('America/New_York', 'UTC', '2018-11-14')
and ca.arrival_created_at >= convert_timezone('America/New_York', 'UTC', '2018-11-14')
and ca.communication_channel in ('EMAIL')


left join
(
select sendid || '_' || batchid as email_batch_id
, emailaddress as email_address
, eventdate as offer_specific_preference_updated_at
, offer_id
, offer_subtype
, option_id
, case when option_id = '1' then 'immediate' when option_id = '2' then 'daily' when option_id = '3' then 'weekly' when option_id = '4' then 'never' end as option_name
from dbm.jobcase_preferences
where option_id in ('3','4')
) osd on c.communication_to_address = osd.email_address and c.bulk_send_id = osd.email_batch_id
where c.communication_channel in ('EMAIL')
and c.communication_sent_time >= convert_timezone('America/New_York', 'UTC', '2018-11-14')
and c.communication_sending_domain in ('jobcase.com', 'post.jobcase.com', 't.jobcase.com')
and c.communication_vendor_template_name = 'JC_ALL_Jobs_10CAT_LOGO'

group by 1,2
order by 1,2


  "

# run query
ab_results <- dbGetQuery(conn, sqlText)
ab_results

ab_results["emails_sent"]
ab_results[,c("emails_sent","emails_opened","emails_clicked")]
ab_results_agg <- aggregate(x = ab_results[,c("emails_sent","emails_opened","emails_clicked")], 
          by = list(unique.test_groups = ab_results$test_group), #, unique.dates = ab_results$send_date), 
          FUN = sum) #length)

ab_results_metrics <- cbind(
  ab_results_agg
, ab_results_agg$emails_opened / ab_results_agg$emails_sent
, ab_results_agg$emails_clicked / ab_results_agg$emails_sent
)
colnames(ab_results_metrics) <- c(colnames(ab_results_agg),"pct_emails_opened","pct_emails_clicked")
ab_results_metrics

freqTable = cbind(ab_results_metrics$emails_clicked, ab_results_metrics$emails_sent)
# Conduct significance test
prop.test(freqTable, conf.level = .95)

# close connection
dbDisconnect(conn)