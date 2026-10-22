-- Cron jobs run INSIDE the database. They do not run while it is down, so a gap in the run history is a rough measure of the downtime.
-- Gaps longer than 15 seconds in the history of the heartbeat job (a 10-second job normally shows 10 or 11). Times are UTC.
with runs as (
  select start_time, lag(start_time) over (order by start_time) as prev
  from cron.job_run_details
  where jobid = (select jobid from cron.job where jobname = 'ssl-demo-heartbeat')
    and start_time > now() - interval '30 minutes')
select to_char(prev, 'HH24:MI:SS') as last_run_before_utc,
       to_char(start_time, 'HH24:MI:SS') as next_run_utc,
       extract(epoch from (start_time - prev))::int as gap_seconds
from runs
where start_time - prev > interval '15 seconds'
order by start_time;
