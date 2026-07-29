-- Sous — Friday kickoff cron (SPEC §9.5).
-- pg_cron + pg_net call the kickoff_week Edge Function. The function URL and
-- shared secret are read from Supabase Vault at run time, so no secret lives in
-- this committed migration. Insert them out-of-band (see deploy notes):
--   select vault.create_secret('https://<ref>.supabase.co', 'project_url');
--   select vault.create_secret('<random>', 'kickoff_secret');
--
-- Schedule note: pg_cron runs in UTC. Fri 18:00 America/Los_Angeles is
-- Sat 01:00 UTC during PDT (most of the year). It drifts to 17:00 local under
-- PST; acceptable for a personal tool, and the job is idempotent per week.

create extension if not exists pg_cron;
create extension if not exists pg_net;

-- The job is scheduled immediately, but only fires once the Vault secrets
-- exist — so a fresh deploy (no Vault yet) is a clean no-op rather than a
-- weekly error. Add the secrets to enable the Friday auto-plan (see SETUP.md).
select cron.schedule(
  'kickoff_week_friday',
  '0 1 * * 6',
  $job$
  select net.http_post(
    url := (select decrypted_secret from vault.decrypted_secrets where name = 'project_url')
           || '/functions/v1/kickoff_week',
    headers := jsonb_build_object(
      'content-type', 'application/json',
      'x-kickoff-secret', (select decrypted_secret from vault.decrypted_secrets where name = 'kickoff_secret')
    ),
    body := '{}'::jsonb
  )
  where exists (select 1 from vault.decrypted_secrets where name = 'kickoff_secret')
    and exists (select 1 from vault.decrypted_secrets where name = 'project_url');
  $job$
);
