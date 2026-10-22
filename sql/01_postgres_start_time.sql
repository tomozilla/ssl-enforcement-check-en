-- Ask the database itself when Postgres started (i.e. whether it restarted)
select pg_postmaster_start_time() as postgres_started_at, now() as checked_at;
