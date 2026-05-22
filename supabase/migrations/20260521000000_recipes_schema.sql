-- Goodbye Fresh — recipe schema (subset of SPEC §9.2)
-- The three tables the curated seed (supabase/seeds/recipes.sql) depends on.
-- The remaining household/plan/conversation tables come in a later migration.

-- pgvector for recipes.embedding (SPEC §9.1 "with pgvector later").
create extension if not exists vector;

-- ---------------------------------------------------------------------------
create table if not exists ingredients (
  id              uuid primary key default gen_random_uuid(),
  created_at      timestamptz not null default now(),
  name_canonical  text not null unique,
  aliases         text[] not null default '{}',
  unit_default    text,
  source_hint     text check (source_hint in ('farmers_market','grocery','either')),
  seasonal_months int[],
  is_free         boolean not null default false
);

-- ---------------------------------------------------------------------------
create table if not exists recipes (
  id                    uuid primary key default gen_random_uuid(),
  created_at            timestamptz not null default now(),
  title                 text not null,
  cuisine_tag           text not null check (cuisine_tag in ('mexican','asian','italian','other')),
  body_md               text,
  time_minutes          int,
  toddler_variant_notes text,
  source                text not null check (source in ('llm_generated','curated')),
  last_used_on          date,
  times_used            int not null default 0,
  embedding             vector(1024)
);

-- ---------------------------------------------------------------------------
create table if not exists recipe_ingredients (
  recipe_id     uuid not null references recipes(id) on delete cascade,
  ingredient_id uuid not null references ingredients(id) on delete restrict,
  quantity      numeric,
  unit          text,
  optional      boolean not null default false,
  primary key (recipe_id, ingredient_id)
);

create index if not exists recipe_ingredients_ingredient_id_idx
  on recipe_ingredients (ingredient_id);
