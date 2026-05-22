-- Sous — household onboarding preferences.
-- Captured conversationally on first run (see _shared/onboarding.ts) and used by
-- the planner + persona instead of hardcoded constraints. One row per household.

create table if not exists household_preferences (
  household_id       uuid primary key references households(id) on delete cascade,
  adults             int not null default 2,
  kids               jsonb not null default '[]'::jsonb,   -- [{"age_months": 30}, {"age_months": 9}]
  meals_per_week     int not null default 5 check (meals_per_week between 1 and 7),
  monthly_budget_usd numeric,
  cuisines           text[] not null default '{}',
  onboarded          boolean not null default false,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now()
);

alter table household_preferences enable row level security;
create policy hh_isolation on household_preferences
  for all using (household_id = app_household_id());
