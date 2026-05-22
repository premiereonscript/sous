-- Goodbye Fresh — core schema (remainder of SPEC §9.2 + ops tables)
-- Adds the household / planning / conversation tables on top of the recipe
-- catalog from 20260521000000_recipes_schema.sql.
--
-- RLS: enabled on every household-scoped table. Edge Functions call with the
-- service-role key (which bypasses RLS); policies are defense-in-depth so a
-- leaked anon key has no direct table access (SPEC §10.2). Each policy ties
-- rows back to the household resolved into app.household_id via set_config.

-- ---------------------------------------------------------------------------
-- Helper: the household the current request is scoped to (NULL if unset).
create or replace function app_household_id() returns uuid
  language sql stable
  as $$ select nullif(current_setting('app.household_id', true), '')::uuid $$;

-- ---------------------------------------------------------------------------
-- households
create table if not exists households (
  id         uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  name       text not null,
  timezone   text not null default 'America/Los_Angeles'
);

-- users (adults + toddlers; toddlers are constraints, not chat participants)
create table if not exists users (
  id           uuid primary key default gen_random_uuid(),
  created_at   timestamptz not null default now(),
  household_id uuid not null references households(id) on delete cascade,
  display_name text not null,
  role         text not null check (role in ('adult','toddler')),
  telegram_id  bigint unique,
  birthdate    date
);
create index if not exists users_household_id_idx on users (household_id);

-- taste_profile (one row per user/dimension/value)
create table if not exists taste_profile (
  id         uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  user_id    uuid not null references users(id) on delete cascade,
  dimension  text not null check (dimension in ('spice_tolerance','dislike','restriction','loves')),
  value      jsonb not null,
  confidence real not null default 0.7,
  updated_at timestamptz not null default now(),
  unique (user_id, dimension, value)
);

-- meal_plans (one per household per week, week_of = Monday)
create table if not exists meal_plans (
  id           uuid primary key default gen_random_uuid(),
  created_at   timestamptz not null default now(),
  household_id uuid not null references households(id) on delete cascade,
  week_of      date not null,
  status       text not null default 'draft' check (status in ('draft','proposed','locked','archived')),
  locked_at    timestamptz,
  unique (household_id, week_of)
);

-- meal_plan_items (v1: dinners only)
create table if not exists meal_plan_items (
  id                     uuid primary key default gen_random_uuid(),
  created_at             timestamptz not null default now(),
  plan_id                uuid not null references meal_plans(id) on delete cascade,
  day                    date not null,
  slot                   text not null default 'dinner' check (slot in ('dinner')),
  recipe_id              uuid not null references recipes(id) on delete restrict,
  toddler_variant_active boolean not null default true,
  position               int,
  unique (plan_id, day, slot)
);

-- feedback (tag chips + optional free text, per meal per rater)
create table if not exists feedback (
  id            uuid primary key default gen_random_uuid(),
  created_at    timestamptz not null default now(),
  plan_item_id  uuid not null references meal_plan_items(id) on delete cascade,
  rater_user_id uuid not null references users(id) on delete cascade,
  rating        int check (rating between 1 and 5),
  tags          text[] not null default '{}',
  free_text     text
);

-- shopping_lists (one per plan)
create table if not exists shopping_lists (
  id           uuid primary key default gen_random_uuid(),
  created_at   timestamptz not null default now(),
  plan_id      uuid not null unique references meal_plans(id) on delete cascade,
  generated_at timestamptz not null default now()
);

-- shopping_list_items (split by where you buy it)
create table if not exists shopping_list_items (
  id            uuid primary key default gen_random_uuid(),
  created_at    timestamptz not null default now(),
  list_id       uuid not null references shopping_lists(id) on delete cascade,
  ingredient_id uuid not null references ingredients(id) on delete restrict,
  quantity      numeric,
  unit          text,
  source        text not null check (source in ('farmers_market','grocery')),
  checked       boolean not null default false
);

-- conversations (one per Telegram chat / household)
create table if not exists conversations (
  id               uuid primary key default gen_random_uuid(),
  created_at       timestamptz not null default now(),
  household_id     uuid not null references households(id) on delete cascade,
  telegram_chat_id bigint not null unique,
  active_plan_id   uuid references meal_plans(id) on delete set null,
  state            text not null default 'idle'
                     check (state in ('idle','awaiting_feedback','proposing','editing','locked')),
  state_payload    jsonb not null default '{}'
);

-- messages (durable log; persisted before any Telegram send — SPEC §9.6)
create table if not exists messages (
  id                 uuid primary key default gen_random_uuid(),
  created_at         timestamptz not null default now(),
  conversation_id    uuid not null references conversations(id) on delete cascade,
  direction          text not null check (direction in ('in','out')),
  sender_user_id     uuid references users(id) on delete set null,
  text               text,
  tool_calls         jsonb,
  telegram_update_id bigint unique
);
create index if not exists messages_conversation_id_idx on messages (conversation_id, created_at);

-- system_flags (per-household kill switch + daily cost guardrails — SPEC §10.4)
create table if not exists system_flags (
  household_id     uuid primary key references households(id) on delete cascade,
  llm_enabled      boolean not null default true,
  daily_llm_calls  int not null default 0,
  daily_tokens     int not null default 0,
  window_date      date not null default current_date
);

-- ---------------------------------------------------------------------------
-- RLS: enable + scope every household table to app_household_id()
alter table households          enable row level security;
alter table users               enable row level security;
alter table taste_profile       enable row level security;
alter table meal_plans          enable row level security;
alter table meal_plan_items     enable row level security;
alter table feedback            enable row level security;
alter table shopping_lists      enable row level security;
alter table shopping_list_items enable row level security;
alter table conversations       enable row level security;
alter table messages            enable row level security;
alter table system_flags        enable row level security;

create policy hh_isolation on households
  for all using (id = app_household_id());
create policy hh_isolation on users
  for all using (household_id = app_household_id());
create policy hh_isolation on taste_profile
  for all using (user_id in (select id from users where household_id = app_household_id()));
create policy hh_isolation on meal_plans
  for all using (household_id = app_household_id());
create policy hh_isolation on meal_plan_items
  for all using (plan_id in (select id from meal_plans where household_id = app_household_id()));
create policy hh_isolation on feedback
  for all using (plan_item_id in (
    select mpi.id from meal_plan_items mpi
    join meal_plans mp on mp.id = mpi.plan_id
    where mp.household_id = app_household_id()));
create policy hh_isolation on shopping_lists
  for all using (plan_id in (select id from meal_plans where household_id = app_household_id()));
create policy hh_isolation on shopping_list_items
  for all using (list_id in (
    select sl.id from shopping_lists sl
    join meal_plans mp on mp.id = sl.plan_id
    where mp.household_id = app_household_id()));
create policy hh_isolation on conversations
  for all using (household_id = app_household_id());
create policy hh_isolation on messages
  for all using (conversation_id in (select id from conversations where household_id = app_household_id()));
create policy hh_isolation on system_flags
  for all using (household_id = app_household_id());
