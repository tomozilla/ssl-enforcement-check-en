import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import postgres from "https://deno.land/x/postgresjs@v3.4.5/mod.js";

// API for the status page. It returns: whether this function's connection to the database is encrypted, when the database last restarted,
// and the time ranges where cron runs were interrupted (a rough measure of the restart gap). Read-only: it changes nothing.
// NOTE: Verify JWT is OFF; instead the function checks inside that the app's publishable key is present.
//    The publishable key is public by design, so this is only an entry ticket. For a public page, add a real login.
const sql = postgres(Deno.env.get("SUPABASE_DB_URL")!);
// The one cron job that runs every 10 seconds (sql/00_heartbeat_cron.sql). Only its history is used, so other jobs in your project cannot create fake gaps.
const HEARTBEAT_JOB = Deno.env.get("HEARTBEAT_JOB") ?? "ssl-demo-heartbeat";
// A normal 10-second job shows gaps of 10-11 seconds; the restarts I measured showed 17-62 seconds. 15 separates them in my small sample.
const GAP_SECONDS = 15;
const PUBLISHABLE_KEYS: string[] = Object.values(JSON.parse(Deno.env.get("SUPABASE_PUBLISHABLE_KEYS") ?? "{}"));

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "apikey, content-type, authorization",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  const key = req.headers.get("apikey");
  if (!key || !PUBLISHABLE_KEYS.includes(key)) return json({ error: "unauthorized" }, 401);

  try {
    // Is this function -> database connection encrypted? (pg_stat_ssl lets a connection see its own state)
    const [conn] = await sql`
      select ssl, version as tls_version, cipher, bits
      from pg_stat_ssl where pid = pg_backend_pid()`;

    // When did Postgres start? (= the last restart)
    const [db] = await sql`
      select pg_postmaster_start_time() as started_at, now() as now,
             current_setting('server_version') as server_version`;

    // Count cron runs per minute over the last 60 minutes (a 10-second job gives about 6 per minute)
    const perMinute = await sql`
      select date_trunc('minute', start_time) as minute, count(*)::int as runs
      from cron.job_run_details
      where start_time > now() - interval '60 minutes'
        and jobid = (select jobid from cron.job where jobname = ${HEARTBEAT_JOB})
      group by 1 order by 1`;

    // Gaps in the last 72 hours where the interval between runs exceeded GAP_SECONDS
    const gaps = await sql`
      with runs as (
        select start_time, lag(start_time) over (order by start_time) as prev
        from cron.job_run_details
        where start_time > now() - interval '72 hours'
          and jobid = (select jobid from cron.job where jobname = ${HEARTBEAT_JOB}))
      select prev as from_ts, start_time as to_ts, extract(epoch from (start_time - prev))::int as seconds
      from runs where start_time - prev > make_interval(secs => ${GAP_SECONDS})
      order by start_time desc limit 20`;

    return json({ connection: conn ?? null, database: db, perMinute, gaps, gapThresholdSeconds: GAP_SECONDS });
  } catch (e) {
    console.error(String(e));
    return json({ error: "server error" }, 500);
  }
});
