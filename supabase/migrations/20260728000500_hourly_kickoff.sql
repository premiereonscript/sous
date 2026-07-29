-- Sous — T12: per-household, timezone-aware weekly kickoff.
--
-- Replaces the single Fri-6pm-Pacific UTC tick with an HOURLY cron that sends
-- {"scheduled": true}. kickoff_week then kicks off only the households whose
-- LOCAL plan_day/plan_hour (in households.timezone) is the current hour — so a
-- household in London or Tokyo gets its plan at its own Friday 6pm, and DST no
-- longer drifts it. Manual trigger_kickoff_now (empty body) still forces all.
--
-- Vault secrets gate it exactly as before: a fresh deploy with no Vault is a
-- clean no-op until the secrets are added (see SETUP.md).

-- Retire the old fixed-time job if present.
select cron.unschedule('kickoff_week_friday')
where exists (select 1 from cron.job where jobname = 'kickoff_week_friday');

select cron.schedule(
  'kickoff_week_hourly',
  '0 * * * *',
  $job$
  select net.http_post(
    url := (select decrypted_secret from vault.decrypted_secrets where name = 'project_url')
           || '/functions/v1/kickoff_week',
    headers := jsonb_build_object(
      'content-type', 'application/json',
      'x-kickoff-secret', (select decrypted_secret from vault.decrypted_secrets where name = 'kickoff_secret')
    ),
    body := '{"scheduled": true}'::jsonb
  )
  where exists (select 1 from vault.decrypted_secrets where name = 'kickoff_secret')
    and exists (select 1 from vault.decrypted_secrets where name = 'project_url');
  $job$
);
