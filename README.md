# Check what "Enforce SSL" really changes on a Supabase project (English demo)

Small scripts, SQL and a status page to check how connections behave **before** and **after** you switch on "Enforce SSL on incoming connections" in a Supabase project, and to measure what the restart behind it does. No real database password is used anywhere.

> This is a **personal learning project**, not official Supabase material. Everything here is demo-grade. Read "Security" before you reuse any of it.

The walkthrough is the Dev.to article that goes with this repo (link added when published).

## Files
| Path | What it is |
|---|---|
| `scripts/check-ssl.sh` | Connects with `sslmode=disable` and `sslmode=require` using a **deliberately wrong password** and prints at which stage the server refuses |
| `scripts/poll.sh` | Calls the status function every few seconds and prints time, HTTP status and the database start time, so you can see an outage from the outside |
| `sql/00_heartbeat_cron.sql` | A cron job every 10 seconds (`ssl-demo-heartbeat`); its run history is how downtime is measured |
| `sql/01_postgres_start_time.sql` | Asks Postgres when it started (proves a restart happened) |
| `sql/02_cron_gap.sql` | Lists gaps longer than 15 seconds in the heartbeat's run history (UTC) |
| `supabase/functions/security-status/` | The Edge Function behind the status page (read-only) |
| `app/index.html`, `app/config.example.js` | The status page (one file, no build step) |

## Prerequisites
- A Supabase project (Free plan is enough) with `pg_cron` enabled, and permission to change Database Settings.
- `psql` (PostgreSQL client), `curl`, Python 3, a browser. I only used a Mac.

## Steps
1. Run `sql/00_heartbeat_cron.sql`. Keep it as the **only** 10-second job you care about: the page reads only the job named `ssl-demo-heartbeat`.
2. Deploy `supabase/functions/security-status` (Verify JWT off, see Security). Optional secret `HEARTBEAT_JOB` if you named the job differently.
3. Find your Session pooler host and user in the dashboard under Connect (mine was `aws-0-<region>.pooler.supabase.com` and `postgres.<PROJECT_REF>`).
4. Test **before** switching: `export PGHOST=... PGUSER=...` then `./scripts/check-ssl.sh`.
5. Database Settings -> **Enforce SSL on incoming connections**: switch it, confirm the dialog.
6. Test **after**: run `./scripts/check-ssl.sh` again.
7. See the restart: `sql/01_postgres_start_time.sql` and `sql/02_cron_gap.sql` in the SQL Editor, or run `./scripts/poll.sh 3` (with `STATUS_URL` and `PUBLISHABLE_KEY` set) in a terminal while you restart.
8. Status page: copy `app/config.example.js` to `app/config.js`, fill in your project URL and **publishable** key, then `cd app && python3 -m http.server 8765 --bind 127.0.0.1` and open `http://127.0.0.1:8765/index.html`.

## What I measured (2026-10-22, Free plan, nearly empty database, one region)
`check-ssl.sh` with a wrong password:

| Enforcement | `sslmode=disable` | `sslmode=require` |
|---|---|---|
| off | `password authentication failed` (it got as far as the password check) | `password authentication failed` |
| on | `(ESSLREQUIRED) SSL connection is required` (refused before the password) | `password authentication failed` |

Restarts, measured by the gap in the 10-second heartbeat's run history and by `poll.sh` (about one call every 3 seconds):

| What I did | Heartbeat gap | API calls that failed |
|---|---|---|
| SSL enforcement off | 18 s | 1 |
| SSL enforcement on | 21 s | 1 |
| Dashboard: Fast database reboot | 17 s | 1 (plus one unexplained 20 s timeout a minute later) |
| Dashboard: Restart project, run 1 | 62 s | calls failed or timed out for about 51 s |
| Restart project, run 2 | 64 s | about 48 s |
| Restart project, run 3 | 63 s | about 46 s |

A normal gap is 10 s (in my first 15 minutes of heartbeat history, 91 normal gaps: 90 at 10 s and 1 at 11 s). One run per row for the first three, so treat them as examples, not averages.

## Cost
- The setting itself costs nothing I could see on the Free plan. I did not check how it is handled on paid plans.
- The status page calls the function every 30 seconds: about 2,880 calls a day per open tab, about 86,000 a month (arithmetic). Free includes 500,000 Edge Function invocations a month (Supabase docs, checked 2026-10-22), so one open tab is about 17%. Several tabs add up fast. I did not read the usage page after the run.
- The heartbeat is a database-side job; it makes no function calls.

## Security
- `security-status` runs with **Verify JWT off** and checks that the request carries your **publishable** key. That key is public by design, so it is an entry ticket, **not** authentication. The function is read-only, but for a public page add a real login.
- No real database password is used. `check-ssl.sh` sets a deliberately wrong one. Never put your real password into scripts or environment variables.
- `config.js` is git-ignored. Only the publishable key belongs there, never a `service_role` / secret key.

## Not verified
- `sslmode=verify-full` with the downloaded certificate (the dashboard offers one; I did not test it).
- Large databases and many connections: the restart times above are from an almost empty database.
- Paid-plan behavior, other regions, other browsers, mobile layout.
- Why one 20-second timeout appeared a minute after the Fast database reboot.
- Which services Restart project restarts internally: I could not find a public description.

## Limits of the status page
- The start time is known only for the **last** restart, so earlier gaps show as "cause unknown".
- The gap threshold (15 s) fits a 10-second job and a small sample (normal gaps were 10-11 s); it will not suit other schedules.

## Cleanup
`select cron.unschedule('ssl-demo-heartbeat');` and delete the `security-status` function. Switch "Enforce SSL" back if you do not want it.

## License
MIT. See `LICENSE`.
