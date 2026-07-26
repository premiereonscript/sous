-- Manual "run the Friday kickoff right now" helper. Fires the exact same
-- net.http_post the pg_cron job uses, reading the function URL + shared secret
-- from Vault so no secret is ever exposed to the caller. Useful for an
-- off-cycle replan or for testing the kickoff path without waiting for Friday.
-- SECURITY DEFINER so it can read Vault; only reachable by trusted roles.
create or replace function trigger_kickoff_now()
returns bigint
language plpgsql
security definer
set search_path = public, vault, extensions, net
as $$
declare
  rid bigint;
begin
  select net.http_post(
    url := (select decrypted_secret from vault.decrypted_secrets where name = 'project_url')
           || '/functions/v1/kickoff_week',
    headers := jsonb_build_object(
      'content-type', 'application/json',
      'x-kickoff-secret', (select decrypted_secret from vault.decrypted_secrets where name = 'kickoff_secret')
    ),
    body := '{}'::jsonb
  ) into rid;
  return rid;
end;
$$;

revoke all on function trigger_kickoff_now() from public, anon, authenticated;
