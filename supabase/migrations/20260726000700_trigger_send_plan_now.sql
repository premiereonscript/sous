-- Manual "re-post the current plan (recipe cards + shopping list) to the chats
-- right now" helper. Fires send_list in mode=plan, which resends the existing
-- plan without regenerating the week (non-destructive). Reads URL + secret from
-- Vault so no secret is exposed. Safe to call anytime.
create or replace function trigger_send_plan_now()
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
           || '/functions/v1/send_list',
    headers := jsonb_build_object(
      'content-type', 'application/json',
      'x-kickoff-secret', (select decrypted_secret from vault.decrypted_secrets where name = 'kickoff_secret')
    ),
    body := '{"mode":"plan"}'::jsonb
  ) into rid;
  return rid;
end;
$$;

revoke all on function trigger_send_plan_now() from public, anon, authenticated;
