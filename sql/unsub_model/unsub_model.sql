-- Define Audience
-- members who first registered between September 1, 2018- September 30, 2018
drop table if exists #unsubber_model_audience;
create table #unsubber_model_audience
	distkey(user_key) sortkey(membership_arrival_created_at) as

select user_key
, membership_arrival_created_at
, user_computed_birth_year_estimate
, user_computed_email_domain_group
, membership_arrival_computed_traffic_type
from users
where membership_arrival_created_at >= convert_timezone('America/New_York', 'UTC', '2018-09-01')
	and membership_arrival_created_at <  convert_timezone('America/New_York', 'UTC', '2018-10-01')
;

-- Want to subset to emails sent after members already had 1+ offer-specific downgrade.
-- So pull all osd's.
drop table if exists #offer_specific_unsubs;
create table #offer_specific_unsubs
	distkey(user_key) as
select o.SubscriberKey as user_key
, convert_timezone('US/Mountain', 'UTC', eventdate) as eventdate
, sendid
, batchid
, o.offer_id
, o.option_id
from dbm.jobcase_preferences o
join #unsubber_model_audience a on o.SubscriberKey = a.user_key
where eventdate >= convert_timezone('America/New_York', 'UTC', '2018-08-31')
	and eventdate < convert_timezone('America/New_York', 'UTC', '2018-10-23')
;

-- 397k osd's from 158k people
/*
osd's by option_id:
- 361k 4 (92%)
- 5k 3 (1%)
- 12k 2 (3%)
- 16k 1 (4%)
*/
select
option_id
, count(*) , count(distinct user_key)
from #offer_specific_unsubs
group by 1
order by 1
;

-- Distribution of osd's during this period per member
-- 32% 1, 26% 2, 17% 3, 12% 4, .... max 21, top 1% have 6-7
select
-- n_rows
n_unsubs
, count(distinct user_key) as n_members
, n_members::float / sum(n_members) over() as pct_of_total
from
(
select user_key, count(*) as n_rows, count(distinct user_key || offer_id || sendid || batchid) as n_unsubs
from #offer_specific_unsubs
group by 1
)
group by 1
order by 1
;

-- Pull emails sent between September 1, 2018 - October 23, 2018 ** after the member already had 1+ offer-specific unsub
drop table if exists #first_osd;
create table #first_osd distkey(user_key) as
select distinct user_key
, first_value(eventdate) over(partition by user_key order by eventdate rows unbounded preceding) as first_osd
from #offer_specific_unsubs
;


-- Pull relevant emails & email response metrics for model
drop table if exists #emails_sent;
create table #emails_sent
	distkey(user_key) sortkey(communication_sent_time) as
select c.user_key
, c.communication_id
, c.communication_sent_time
, c.communication_vendor_template_name
, c.communication_open_time_initial
, case when count(distinct ca.user_key) > 0 then TRUE else FALSE end as email_arrived
, case when count(distinct case when osu.offer_id is not null then osu.user_key end) > 0 then TRUE else FALSE end as email_osd
, case when count(distinct case when osu.option_id in ('4') then osu.user_key end) > 0 then TRUE else FALSE end as email_osd_4
, case when count(distinct case when osu.option_id in ('3') then osu.user_key end) > 0 then TRUE else FALSE end as email_osd_3
, case when count(distinct case when osu.option_id in ('2') then osu.user_key end) > 0 then TRUE else FALSE end as email_osd_2
, case when count(distinct case when osu.option_id in ('1') then osu.user_key end) > 0 then TRUE else FALSE end as email_osd_1
, count(distinct osu2.offer_id || osu2.sendid || osu2.batchid) as n_osus_previously
from public.communications c
join #first_osd o on c.user_key = o.user_key and o.first_osd < c.communication_sent_time
left join dbm.communication_to_arrival ca
	on ca.user_key = c.user_key
	and ca.communication_id = c.communication_id
	and ca.communication_sent_time >= convert_timezone('America/New_York', 'UTC', '2018-09-01 00:00:00')
	and ca.arrival_created_at >= convert_timezone('America/New_York', 'UTC', '2018-09-01 00:00:00')
	and ca.communication_sent_time < convert_timezone('America/New_York', 'UTC', '2018-10-23')
	and ca.arrival_created_at < convert_timezone('America/New_York', 'UTC', '2018-10-23')
	and ca.communication_channel in ('EMAIL')
left join #offer_specific_unsubs osu
	on c.user_key = osu.user_key
	and c.bulk_send_id = osu.sendid || '_' || osu.batchid
left join #offer_specific_unsubs osu2
	on c.user_key = osu2.user_key
	and osu2.eventdate < c.communication_sent_time
where c.communication_sent_time >= convert_timezone('America/New_York', 'UTC', '2018-09-01')
	and c.communication_sent_time < convert_timezone('America/New_York', 'UTC', '2018-10-23')
	and c.communication_channel = 'EMAIL'
	and c.communication_sending_domain in ('post.jobcase.com')
	and c.communication_failure_time is null
group by 1,2,3,4,5
;


/*
compile data on previous email history
*/

-- dates 9/1 - 10/22
create table #reference_dates
	diststyle all as
select convert_timezone('America/New_York', communication_sent_time)::date as reference_date
from #emails_sent
group by 1
;

-- days mailable
drop table if exists #days_mailable;
create table #days_mailable
	distkey(user_key) sortkey(reference_date) as
select user_key
, r.reference_date
, count(*) as n_days_mailable_last_7d
from dbm.jc_ip_warmup ipw
join #unsubber_model_audience using(user_key)
join #reference_dates r
	on r.reference_date <= ipw.classification_date + interval '7 days'
	and r.reference_date > ipw.classification_date
where classification_date >= '2018-09-01'::date - interval '7 days'
	and classification_date < '2018-10-23'
group by 1,2
;


-- emails sent

drop table if exists #emails_sent_history;
create table #emails_sent_history
	distkey(user_key) sortkey(reference_date) as
select user_key
, r.reference_date
, count(distinct c.communication_id) as emails_sent_last_7d
, count(distinct case when convert_timezone('America/New_York', c.communication_sent_time) >= r.reference_date - interval '2 days' then c.communication_id end) as emails_sent_last_2d
from public.communications c
join #unsubber_model_audience using(user_key)
join #reference_dates r
	on r.reference_date <= convert_timezone('America/New_York', c.communication_sent_time + interval '7 days')
	and r.reference_date > convert_timezone('America/New_York', c.communication_sent_time)
where c.communication_sent_time >= convert_timezone('America/New_York', 'UTC', '2018-09-01'::date  - interval '7 days')
	and c.communication_sent_time < convert_timezone('America/New_York', 'UTC', '2018-10-23')
	and c.communication_channel = 'EMAIL'
	and c.communication_sending_domain in ('post.jobcase.com')
	and c.communication_failure_time is null
group by 1,2
;


-- email arrivals
-- takes around 4min to run

drop table if exists #email_arrivals_history;
create table #email_arrivals_history
	distkey(user_key) sortkey(reference_date) as
select a.user_key
, r.reference_date
, count(distinct a.arrival_key) as email_arrivals_last_7d
, count(distinct case when convert_timezone('America/New_York', a.arrival_created_at) >= r.reference_date - interval '2 days' then a.arrival_key end) as email_arrivals_last_2d
, count(distinct er.arrival_key) as expired_job_email_arrivals_last_7d
, count(distinct case when convert_timezone('America/New_York', er.arrival_created_at) >= r.reference_date - interval '2 days' then er.arrival_key end) as expired_job_email_arrivals_last_2d
, count(distinct epv.arrival_key) as errored_email_arrivals_last_7d
, count(distinct case when convert_timezone('America/New_York', epv.arrival_created_at) >= r.reference_date - interval '2 days' then epv.arrival_key end) as errored_email_arrivals_last_2d
from public.arrivals a
join #unsubber_model_audience using(user_key)
join #reference_dates r
	on r.reference_date <= convert_timezone('America/New_York', a.arrival_created_at + interval '7 days')
	and r.reference_date > convert_timezone('America/New_York', a.arrival_created_at)
left join public.event_reportables er
	on er.user_key = a.user_key
	and er.arrival_key = a.arrival_key
	and er.reportable_event_name = 'BragiFetchExpiredJob'
	and er.arrival_created_at >= convert_timezone('America/New_York', 'UTC', '2018-09-01'::date  - interval '7 days')
	and er.arrival_created_at < convert_timezone('America/New_York', 'UTC', '2018-10-23')
left join public.event_page_views epv
	on epv.user_key = a.user_key
	and epv.arrival_key = a.arrival_key
	and substring(epv.page_view_event_status,1,1) in ('4','5')
	and epv.arrival_created_at >= convert_timezone('America/New_York', 'UTC', '2018-09-01'::date  - interval '7 days')
	and epv.arrival_created_at < convert_timezone('America/New_York', 'UTC', '2018-10-23')
where a.arrival_created_at >= convert_timezone('America/New_York', 'UTC', '2018-09-01'::date  - interval '7 days')
	and a.arrival_created_at < convert_timezone('America/New_York', 'UTC', '2018-10-23')
	and a.arrival_computed_traffic_type = 'Email'
	and a.arrival_application = 'jobcase.com'
	and a.arrival_computed_bot_classification is null
group by 1,2
;


select *
from #email_arrivals_history
order by user_key, reference_date
limit 1000
;

-- 533k arrivers
-- 41% arrived on expired job at some point during period
-- 15% had 400 or 500 page error at some point
select count(distinct user_key) a
, count(distinct case when expired_job_email_arrivals_last_2d > 0 then user_key end) b
, count(distinct case when email_arrivals_last_2d > 0 then user_key end) c
, count(distinct case when errored_email_arrivals_last_2d > 0 then user_key end) d
, b::float / a
, c::float / a
, d::float / a
from #email_arrivals_history
;


-- osd's
drop table if exists #emails_osd_history;
create table #emails_osd_history
	distkey(user_key) sortkey(reference_date) as
select o.user_key
, r.reference_date
, count(distinct o.user_key || offer_id || sendid || batchid) as osds_last_7d
, count(distinct case when convert_timezone('America/New_York', o.eventdate) >= r.reference_date - interval '2 days' then o.user_key || offer_id || sendid || batchid end) as osds_last_2d
from #offer_specific_unsubs o
join #unsubber_model_audience using(user_key)
join #reference_dates r
	on r.reference_date <= convert_timezone('America/New_York', o.eventdate + interval '7 days')
	and r.reference_date > convert_timezone('America/New_York', o.eventdate)
where o.eventdate >= convert_timezone('America/New_York', 'UTC', '2018-09-01'::date  - interval '7 days')
	and o.eventdate < convert_timezone('America/New_York', 'UTC', '2018-10-23')
group by 1,2
;


select *
from #emails_osd_history
order by user_key, reference_date
limit 1000
;


-- unsub survey responses

drop table if exists #prefs_survey_responses;
create table #prefs_survey_responses
	distkey(user_key)
	sortkey(eventdate) as
select o.SubscriberKey as user_key
, convert_timezone('US/Mountain', 'UTC', eventdate) as eventdate
, sendid
, batchid
, question_id
, question_answer
from dbm.jc_prefs_survey o
join #unsubber_model_audience a on o.SubscriberKey = a.user_key
where eventdate >= convert_timezone('America/New_York', 'UTC', '2018-08-31')
	and eventdate < convert_timezone('America/New_York', 'UTC', '2018-10-23')
	and question_id between 1 and 8
	and question_answer = 'true'
;

drop table if exists #emails_prefs_survey_history;
create table #emails_prefs_survey_history
	distkey(user_key) sortkey(reference_date) as
select o.user_key
, r.reference_date
, count(distinct case when o.question_id = 1 then o.user_key end) as survey_response_1
, count(distinct case when o.question_id = 2 then o.user_key end) as survey_response_2
, count(distinct case when o.question_id = 3 then o.user_key end) as survey_response_3
, count(distinct case when o.question_id = 4 then o.user_key end) as survey_response_4
, count(distinct case when o.question_id = 5 then o.user_key end) as survey_response_5
, count(distinct case when o.question_id = 6 then o.user_key end) as survey_response_6
, count(distinct case when o.question_id = 7 then o.user_key end) as survey_response_7
, count(distinct case when o.question_id = 8 then o.user_key end) as survey_response_8
from #prefs_survey_responses o
join #unsubber_model_audience using(user_key)
join #reference_dates r
	on r.reference_date > convert_timezone('America/New_York', o.eventdate)
where o.eventdate >= convert_timezone('America/New_York', 'UTC', '2018-09-01'::date)
	and o.eventdate < convert_timezone('America/New_York', 'UTC', '2018-10-23')
group by 1,2
;


select * from #unsubber_model_audience limit 1;
select * from #emails_sent limit 1;
select * from #days_mailable limit 1;
select * from #emails_sent_history limit 1;
select * from #email_arrivals_history limit 1;
select * from #emails_osd_history limit 1;
select * from #prefs_survey_responses limit 1;
select * from #emails_prefs_survey_history limit 1;

select date_part('year', '2018-02-01')
;
drop table if exists #dataset;
create table #dataset distkey(user_key) sortkey(communication_sent_time) as
select
a.user_key
, datediff('days', a.membership_arrival_created_at, b.communication_sent_time) as dsfr
, date_part('year', b.communication_sent_time) - a.user_computed_birth_year_estimate::int as computed_age
-- , user_computed_gender
-- , a.membership_arrival_computed_traffic_type
, case when a.user_computed_email_domain_group in ('GMAIL','AOL','MSN','YAHOO') then a.user_computed_email_domain_group else 'OTHER' end as email_domain_group
, b.communication_sent_time
, b.communication_vendor_template_name
, case when b.communication_open_time_initial is not null then 1 else 0 end as email_opened
, case when b.email_arrived then 1 else 0 end as email_arrived
, case when b.email_osd then 1 else 0 end as email_osd
, case when b.email_osd_4 then 1 else 0 end as email_osd_4
, coalesce(b.n_osus_previously,0) as n_osus_previously
, coalesce(c.n_days_mailable_last_7d,0) as n_days_mailable_last_7d
, coalesce(d.emails_sent_last_7d,0) as emails_sent_last_7d
, coalesce(d.emails_sent_last_2d,0) as emails_sent_last_2d
, coalesce(e.email_arrivals_last_7d,0) as email_arrivals_last_7d
, coalesce(e.email_arrivals_last_2d,0) as email_arrivals_last_2d
, coalesce(e.expired_job_email_arrivals_last_7d,0) as expired_job_email_arrivals_last_7d
, coalesce(e.expired_job_email_arrivals_last_2d,0) as expired_job_email_arrivals_last_2d
, coalesce(e.errored_email_arrivals_last_7d,0) as errored_email_arrivals_last_7d
, coalesce(e.errored_email_arrivals_last_2d,0) as errored_email_arrivals_last_2d
, coalesce(f.osds_last_7d,0) as osds_last_7d
, coalesce(f.osds_last_2d,0) as osds_last_2d
, coalesce(g.survey_response_1,0) as survey_response_1
, coalesce(g.survey_response_2,0) as survey_response_2
, coalesce(g.survey_response_3,0) as survey_response_3
, coalesce(g.survey_response_4,0) as survey_response_4
, coalesce(g.survey_response_5,0) as survey_response_5
, coalesce(g.survey_response_6,0) as survey_response_6
, coalesce(g.survey_response_7,0) as survey_response_7
, coalesce(g.survey_response_8,0) as survey_response_8
from #unsubber_model_audience a
join #emails_sent b using(user_key)
left join #days_mailable c on c.user_key = b.user_key and c.reference_date = convert_timezone('America/New_York', 'UTC', b.communication_sent_time)::date
left join #emails_sent_history d on d.user_key = b.user_key and d.reference_date = convert_timezone('America/New_York', 'UTC', b.communication_sent_time)::date
left join #email_arrivals_history e on e.user_key = b.user_key and e.reference_date = convert_timezone('America/New_York', 'UTC', b.communication_sent_time)::date
left join #emails_osd_history f on f.user_key = b.user_key and f.reference_date = convert_timezone('America/New_York', 'UTC', b.communication_sent_time)::date
left join #emails_prefs_survey_history g on g.user_key = b.user_key and g.reference_date = convert_timezone('America/New_York', 'UTC', b.communication_sent_time)::date
;


-- select count(*), count(distinct user_key)
select *
from #dataset
order by user_key, communication_sent_time
limit 100000
;


select expired_job_email_arrivals_last_7d
-- , email_osd_4
, email_arrived
, count(*) a
, a::float / sum(a) over(partition by expired_job_email_arrivals_last_7d)
from #dataset
group by 1,2
order by 1,2
;
