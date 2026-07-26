create or replace function net_last_responses()
returns table (id bigint, status_code int, error_msg text, content text, created timestamptz)
language sql
security definer
set search_path = public, net, extensions
as $$
  select id, status_code, error_msg, left(content, 500) as content, created
  from net._http_response
  order by id desc
  limit 6;
$$;
revoke all on function net_last_responses() from public, anon, authenticated;
