-- Manual "post the current shopping list to the chats right now" helper —
-- fires the send_list Edge Function (which re-sends each household's active
-- plan's list without regenerating the week). Reads URL + secret from Vault so
-- no secret is exposed. Non-destructive; safe to call anytime.
create or replace function trigger_send_list_now()
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
    body := '{}'::jsonb
  ) into rid;
  return rid;
end;
$$;

revoke all on function trigger_send_list_now() from public, anon, authenticated;
