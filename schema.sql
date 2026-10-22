-- 0001_initial_schema.sql
-- MartinezCh. Cristhian — initial schema
-- Safe initial migration: creates app tables; it does not modify the user's other Supabase project.

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null default '' check (char_length(display_name) <= 80),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.app_admins (
  user_id uuid primary key references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);

create table public.matches (
  id uuid primary key default gen_random_uuid(),
  provider text not null default 'football-data.org',
  provider_match_id bigint not null,
  competition_code text,
  competition_name text not null,
  season_start_date date,
  utc_date timestamptz not null,
  status text not null,
  home_team_provider_id bigint,
  home_team_name text not null,
  away_team_provider_id bigint,
  away_team_name text not null,
  home_score integer,
  away_score integer,
  last_synced_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  unique (provider, provider_match_id)
);

create table public.picks (
  id uuid primary key default gen_random_uuid(),
  match_id uuid not null references public.matches(id) on delete restrict,
  market text not null check (char_length(market) between 1 and 80),
  selection text not null check (char_length(selection) between 1 and 160),
  decimal_odds numeric(8,3) check (decimal_odds is null or decimal_odds > 1),
  estimated_probability numeric(5,4) check (estimated_probability is null or (estimated_probability > 0 and estimated_probability < 1)),
  confidence text not null default 'medium' check (confidence in ('low','medium','high')),
  risk_level text not null default 'medium' check (risk_level in ('low','medium','high')),
  stake_units numeric(8,2) not null default 1 check (stake_units > 0),
  rationale text not null default '' check (char_length(rationale) <= 4000),
  result text not null default 'pending' check (result in ('pending','won','lost','push','void')),
  published_at timestamptz,
  settled_at timestamptz,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (published_at is null or (decimal_odds is not null and estimated_probability is not null)),
  check ((result = 'pending' and settled_at is null) or (result <> 'pending' and settled_at is not null))
);

create index matches_utc_date_idx on public.matches (utc_date);
create index matches_competition_date_idx on public.matches (competition_code, utc_date);
create index matches_status_idx on public.matches (status);
create index picks_published_created_idx on public.picks (published_at desc) where published_at is not null;
create index picks_match_id_idx on public.picks (match_id);
create index picks_result_settled_idx on public.picks (result, settled_at desc);

alter table public.profiles enable row level security;
alter table public.app_admins enable row level security;
alter table public.matches enable row level security;
alter table public.picks enable row level security;

create or replace function public.is_app_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.app_admins a where a.user_id = auth.uid()
  );
$$;
revoke all on function public.is_app_admin() from public;
grant execute on function public.is_app_admin() to anon, authenticated;

create or replace function public.handle_new_app_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, display_name)
  values (
    new.id,
    coalesce(nullif(trim(new.raw_user_meta_data ->> 'display_name'), ''), '')
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

create trigger on_auth_user_created_make_profile
after insert on auth.users
for each row execute procedure public.handle_new_app_user();

create policy profiles_select_self on public.profiles
for select to authenticated using (id = (select auth.uid()));
create policy profiles_insert_self on public.profiles
for insert to authenticated with check (id = (select auth.uid()));
create policy profiles_update_self on public.profiles
for update to authenticated using (id = (select auth.uid())) with check (id = (select auth.uid()));

create policy matches_public_read on public.matches
for select to anon, authenticated using (true);

create policy picks_read_published on public.picks
for select to anon, authenticated
using (published_at is not null or (select public.is_app_admin()));
create policy picks_admin_insert on public.picks
for insert to authenticated
with check ((select public.is_app_admin()));
create policy picks_admin_update on public.picks
for update to authenticated
using ((select public.is_app_admin()))
with check ((select public.is_app_admin()));
create policy picks_admin_delete on public.picks
for delete to authenticated
using ((select public.is_app_admin()));

revoke all on public.app_admins from anon, authenticated;
grant select, insert, update on public.profiles to authenticated;
grant select on public.matches to anon, authenticated;
grant select on public.picks to anon, authenticated;
grant insert, update, delete on public.picks to authenticated;

create or replace view public.performance_summary
with (security_invoker = true)
as
select
  count(*) filter (where result in ('won','lost','push','void'))::integer as settled_picks,
  count(*) filter (where result = 'won')::integer as wins,
  count(*) filter (where result = 'lost')::integer as losses,
  count(*) filter (where result = 'push')::integer as pushes,
  count(*) filter (where result = 'void')::integer as voids,
  round(
    100.0 * count(*) filter (where result = 'won') /
    nullif(count(*) filter (where result in ('won','lost','push')), 0),
    2
  ) as hit_rate_pct,
  round(
    sum(case when result = 'won' then stake_units * (decimal_odds - 1)
             when result = 'lost' then -stake_units
             else 0 end),
    2
  ) as net_units,
  round(
    100.0 * sum(case when result = 'won' then stake_units * (decimal_odds - 1)
                     when result = 'lost' then -stake_units
                     else 0 end) /
    nullif(sum(stake_units) filter (where result in ('won','lost','push')), 0),
    2
  ) as roi_pct
from public.picks
where published_at is not null;

grant select on public.performance_summary to anon, authenticated;

create or replace view public.performance_by_day
with (security_invoker = true)
as
select
  (settled_at at time zone 'America/Guayaquil')::date as settled_day,
  count(*)::integer as settled_picks,
  count(*) filter (where result = 'won')::integer as wins,
  count(*) filter (where result = 'lost')::integer as losses,
  round(
    sum(case when result = 'won' then stake_units * (decimal_odds - 1)
             when result = 'lost' then -stake_units
             else 0 end),
    2
  ) as net_units
from public.picks
where published_at is not null and result in ('won','lost','push','void') and settled_at is not null
group by (settled_at at time zone 'America/Guayaquil')::date
order by settled_day;

grant select on public.performance_by_day to anon, authenticated;

-- 0002_security_hardening.sql
-- Move privileged authorization data/functions out of the exposed public API schema.
create schema if not exists private;
revoke all on schema private from public;
grant usage on schema private to anon, authenticated;

alter table public.app_admins set schema private;
alter function public.is_app_admin() set schema private;

create or replace function private.is_app_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from private.app_admins a where a.user_id = auth.uid()
  );
$$;
revoke all on function private.is_app_admin() from public;
grant execute on function private.is_app_admin() to anon, authenticated;

-- The profile trigger executes on new auth users; it is not an RPC for clients.
revoke all on function public.handle_new_app_user() from public, anon, authenticated;

create index if not exists picks_created_by_idx on public.picks (created_by);

-- 0003_admin_bootstrap.sql
-- Grant administration only to an explicitly allowlisted owner email on registration.
-- The allowlist lives in the private schema and is not exposed by the REST API.
create table private.admin_bootstrap_emails (
  normalized_email text primary key,
  created_at timestamptz not null default now(),
  check (normalized_email = lower(trim(normalized_email)))
);
alter table private.admin_bootstrap_emails enable row level security;
-- Add the first administrator's email privately in Supabase after deployment;
-- do not commit a personal email address to a public repository.

create or replace function public.handle_new_app_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, display_name)
  values (
    new.id,
    coalesce(nullif(trim(new.raw_user_meta_data ->> 'display_name'), ''), '')
  )
  on conflict (id) do nothing;

  if new.email is not null and exists (
    select 1 from private.admin_bootstrap_emails a
    where a.normalized_email = lower(trim(new.email))
  ) then
    insert into private.app_admins (user_id)
    values (new.id)
    on conflict (user_id) do nothing;
  end if;

  return new;
end;
$$;
revoke all on function public.handle_new_app_user() from public, anon, authenticated;

-- A minimal, non-privileged RPC for the signed-in UI to show owner-only controls.
create or replace function public.is_my_admin()
returns boolean
language sql
stable
security invoker
set search_path = ''
as $$
  select private.is_app_admin();
$$;
revoke all on function public.is_my_admin() from public, anon;
grant execute on function public.is_my_admin() to authenticated;

create policy matches_admin_insert on public.matches
for insert to authenticated
with check ((select private.is_app_admin()));
grant insert on public.matches to authenticated;
