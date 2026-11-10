-- People & Planning pilot. No employee data or credentials are stored in migrations.
create schema if not exists private;
revoke all on schema private from public, anon;
grant usage on schema private to authenticated, service_role;

create table public.programmes (
 id uuid primary key default gen_random_uuid(), name text not null,
 short_name text not null, colour text not null default '#285d49', sort_order integer not null default 0,
 donor_posts integer not null check (donor_posts >= 0), current_staff integer not null check (current_staff >= 0),
 above_cap integer not null check (above_cap >= 0), promotions_possible integer not null check (promotions_possible >= 0),
 hiring_requested integer not null check (hiring_requested >= 0), recommended_hires integer not null check (recommended_hires >= 0),
 hiring_on_hold integer not null check (hiring_on_hold >= 0), funded_open integer not null check (funded_open >= 0),
 action text not null, source_name text not null, imported_at timestamptz not null default now()
);
create table public.memberships (
 user_id uuid primary key references auth.users(id) on delete cascade,
 email text not null, display_name text not null,
 role text not null default 'viewer' check (role in ('superadmin','leadership','people','finance','programme_lead','viewer')),
 programme_id uuid references public.programmes(id), active boolean not null default false,
 needs_password_change boolean not null default false, created_at timestamptz not null default now()
);
create index memberships_programme_idx on public.memberships(programme_id);
create table public.programme_layers (
 id uuid primary key default gen_random_uuid(), programme_id uuid not null references public.programmes(id) on delete cascade,
 layer text not null, sort_order integer not null default 0,
 donor_posts integer not null check(donor_posts >= 0), current_staff integer not null check(current_staff >= 0),
 allowed_surge integer not null check(allowed_surge >= 0), above_cap integer not null check(above_cap >= 0),
 funded_open integer not null check(funded_open >= 0), unique(programme_id,layer)
);
create index programme_layers_programme_idx on public.programme_layers(programme_id);
create table public.monthly_budgets (
 id uuid primary key default gen_random_uuid(), programme_id uuid not null references public.programmes(id),
 month date not null check(extract(day from month)=1 and month between date '2026-04-01' and date '2027-03-01'),
 budget numeric(14,2) not null check(budget>=0), actual numeric(14,2) not null check(actual>=0),
 notes text not null check(char_length(notes) between 1 and 2000), updated_by uuid not null references auth.users(id),
 updated_at timestamptz not null default now(), unique(programme_id,month)
);
create index monthly_budgets_updated_by_idx on public.monthly_budgets(updated_by);
create table public.planning_requests (
 id uuid primary key default gen_random_uuid(), programme_id uuid not null references public.programmes(id),
 kind text not null check(kind in ('hiring','promotion','transfer')),
 role_title text not null check(char_length(role_title) between 1 and 150), positions integer not null check(positions between 1 and 100),
 rationale text not null check(char_length(rationale) between 10 and 3000),
 status text not null default 'submitted' check(status in ('submitted','reviewed','on_hold')),
 review_note text check(char_length(review_note)<=3000), reviewed_by uuid references auth.users(id),
 created_by uuid not null references auth.users(id), created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);
create index planning_requests_programme_idx on public.planning_requests(programme_id);
create index planning_requests_created_by_idx on public.planning_requests(created_by);
create index planning_requests_reviewed_by_idx on public.planning_requests(reviewed_by);
create table public.audit_events (
 id bigint generated always as identity primary key, table_name text not null, record_id text not null,
 operation text not null, actor_id uuid, before_data jsonb, after_data jsonb, created_at timestamptz not null default now()
);
create index audit_events_created_idx on public.audit_events(created_at desc);

-- Lookup functions are deliberately private, with fixed search paths and identity checks.
-- They read administrator-managed memberships, never user-editable JWT metadata.
create function private.is_admin() returns boolean language sql stable security definer set search_path = '' as $$
 select auth.uid() is not null and exists(select 1 from public.memberships m where m.user_id=auth.uid() and m.active and not m.needs_password_change and m.role='superadmin');
$$;
create function private.can_read_programme(target uuid) returns boolean language sql stable security definer set search_path = '' as $$
 select auth.uid() is not null and exists(select 1 from public.memberships m where m.user_id=auth.uid() and m.active and not m.needs_password_change and (m.role in ('superadmin','leadership','people','finance') or m.programme_id=target));
$$;
create function private.can_read_budget(target uuid) returns boolean language sql stable security definer set search_path = '' as $$
 select auth.uid() is not null and exists(select 1 from public.memberships m where m.user_id=auth.uid() and m.active and not m.needs_password_change and (m.role in ('superadmin','leadership','finance') or (m.role='programme_lead' and m.programme_id=target)));
$$;
create function private.can_write_budget() returns boolean language sql stable security definer set search_path = '' as $$
 select auth.uid() is not null and exists(select 1 from public.memberships m where m.user_id=auth.uid() and m.active and not m.needs_password_change and m.role in ('superadmin','finance'));
$$;
create function private.can_request(target uuid) returns boolean language sql stable security definer set search_path = '' as $$
 select auth.uid() is not null and exists(select 1 from public.memberships m where m.user_id=auth.uid() and m.active and not m.needs_password_change and (m.role in ('superadmin','leadership','people') or (m.role='programme_lead' and m.programme_id=target)));
$$;
revoke all on function private.is_admin(),private.can_read_programme(uuid),private.can_read_budget(uuid),private.can_write_budget(),private.can_request(uuid) from public, anon;
grant execute on function private.is_admin(),private.can_read_programme(uuid),private.can_read_budget(uuid),private.can_write_budget(),private.can_request(uuid) to authenticated;

alter table public.memberships enable row level security;
alter table public.programmes enable row level security;
alter table public.programme_layers enable row level security;
alter table public.monthly_budgets enable row level security;
alter table public.planning_requests enable row level security;
alter table public.audit_events enable row level security;

create policy memberships_read on public.memberships for select to authenticated using(user_id=(select auth.uid()) or (select private.is_admin()));
create policy programmes_read on public.programmes for select to authenticated using(private.can_read_programme(id));
create policy layers_read on public.programme_layers for select to authenticated using(private.can_read_programme(programme_id));
create policy budgets_read on public.monthly_budgets for select to authenticated using(private.can_read_budget(programme_id));
create policy budgets_insert on public.monthly_budgets for insert to authenticated with check((select private.can_write_budget()) and updated_by=(select auth.uid()));
create policy budgets_update on public.monthly_budgets for update to authenticated using((select private.can_write_budget())) with check((select private.can_write_budget()) and updated_by=(select auth.uid()));
create policy requests_read on public.planning_requests for select to authenticated using(private.can_read_programme(programme_id));
create policy requests_insert on public.planning_requests for insert to authenticated with check(private.can_request(programme_id) and created_by=(select auth.uid()) and status='submitted' and review_note is null and reviewed_by is null);
create policy audit_read on public.audit_events for select to authenticated using((select private.is_admin()));

revoke all on public.memberships,public.programmes,public.programme_layers,public.monthly_budgets,public.planning_requests,public.audit_events from anon,authenticated;
grant select on public.memberships,public.programmes,public.programme_layers,public.monthly_budgets,public.planning_requests,public.audit_events to authenticated;
grant insert,update on public.monthly_budgets to authenticated;
grant insert on public.planning_requests to authenticated;
grant all on public.memberships,public.programmes,public.programme_layers,public.monthly_budgets,public.planning_requests,public.audit_events to service_role;
grant usage,select on sequence public.audit_events_id_seq to service_role;

create function private.new_auth_user() returns trigger language plpgsql security definer set search_path='' as $$
begin
 insert into public.memberships(user_id,email,display_name)
 values(new.id,coalesce(new.email,''),left(coalesce(nullif(new.raw_user_meta_data->>'full_name',''),split_part(coalesce(new.email,'New member'),'@',1)),120));
 return new;
end;
$$;
revoke all on function private.new_auth_user() from public,anon,authenticated;
create trigger people_new_auth_user after insert on auth.users for each row execute function private.new_auth_user();

create function private.log_change() returns trigger language plpgsql security definer set search_path='' as $$
declare previous jsonb; current_value jsonb; actor uuid;
begin
 if TG_OP<>'INSERT' then previous=to_jsonb(old); end if;
 if TG_OP<>'DELETE' then current_value=to_jsonb(new); end if;
 actor=auth.uid();
 if actor is null and TG_TABLE_NAME='planning_requests' then actor=coalesce((current_value->>'reviewed_by')::uuid,(current_value->>'created_by')::uuid); end if;
 if actor is null and TG_TABLE_NAME='monthly_budgets' then actor=(current_value->>'updated_by')::uuid; end if;
 insert into public.audit_events(table_name,record_id,operation,actor_id,before_data,after_data)
 values(TG_TABLE_NAME,coalesce(current_value->>'id',current_value->>'user_id',previous->>'id',previous->>'user_id'),TG_OP,actor,previous,current_value);
 if TG_OP='DELETE' then return old; end if;
 return new;
end;
$$;
revoke all on function private.log_change() from public,anon,authenticated;
create trigger audit_memberships after insert or update or delete on public.memberships for each row execute function private.log_change();
create trigger audit_requests after insert or update or delete on public.planning_requests for each row execute function private.log_change();
create trigger audit_budgets after insert or update or delete on public.monthly_budgets for each row execute function private.log_change();
create function private.touch_updated() returns trigger language plpgsql set search_path='' as $$ begin new.updated_at=now(); return new; end; $$;
revoke all on function private.touch_updated() from public,anon,authenticated;
create trigger touch_budgets before update on public.monthly_budgets for each row execute function private.touch_updated();
create trigger touch_requests before update on public.planning_requests for each row execute function private.touch_updated();

-- Preserve the platform's automatic-RLS event trigger but remove unnecessary RPC grants.
revoke execute on function public.rls_auto_enable() from public,anon,authenticated;
