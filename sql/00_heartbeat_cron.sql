-- (Optional) A cron job every 10 seconds, to see the gap during the restart.
-- Create it only if you have no other 10-second job. Remove it with the unschedule below when you are done.
select cron.schedule('ssl-demo-heartbeat', '10 seconds', 'select 1');

-- Cleanup:
-- select cron.unschedule('ssl-demo-heartbeat');
