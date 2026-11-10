alter table public.memberships drop constraint memberships_role_check;
update public.memberships set role=case when role in ('people','finance') then 'data_admin' when role in ('programme_lead','viewer') then 'programme_manager' else role end;
alter table public.memberships alter column role set default 'programme_manager';
alter table public.memberships add constraint memberships_role_check check(role in ('superadmin','data_admin','leadership','programme_manager'));
alter table public.memberships add column can_view_salary boolean not null default false;
alter table public.memberships add column can_approve boolean not null default false;
alter table public.memberships add constraint assigned_programme_required check(not active or role<>'programme_manager' or programme_id is not null);
alter table public.programmes add column geography text not null default '';
alter table public.programmes add column roster_mode boolean not null default false;
alter table public.programmes add column active boolean not null default true;

create or replace function private.can_read_programme(target uuid) returns boolean language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and exists(select 1 from public.memberships m where m.user_id=auth.uid() and m.active and not m.needs_password_change and (m.role in ('superadmin','data_admin','leadership') or m.programme_id=target)); $$;
create or replace function private.can_read_budget(target uuid) returns boolean language sql stable security definer set search_path='' as $$ select private.can_read_programme(target); $$;
create or replace function private.can_write_budget() returns boolean language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and exists(select 1 from public.memberships m where m.user_id=auth.uid() and m.active and not m.needs_password_change and m.role in ('superadmin','data_admin')); $$;
create or replace function private.can_request(target uuid) returns boolean language sql stable security definer set search_path='' as $$ select private.can_read_programme(target); $$;
create function private.salary_access() returns boolean language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and exists(select 1 from public.memberships m where m.user_id=auth.uid() and m.active and not m.needs_password_change and (m.role='superadmin' or m.can_view_salary)); $$;
create function private.approver() returns boolean language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and exists(select 1 from public.memberships m where m.user_id=auth.uid() and m.active and not m.needs_password_change and (m.role='superadmin' or (m.role='leadership' and m.can_approve))); $$;
create function private.array_total(items numeric[]) returns numeric language sql immutable set search_path='' as $$ select coalesce(sum(n),0) from unnest(items) n; $$;
revoke all on function private.salary_access(),private.approver(),private.array_total(numeric[]) from public,anon;
grant execute on function private.salary_access(),private.approver(),private.array_total(numeric[]) to authenticated,service_role;

create table public.workforce_inputs (
 id uuid primary key default gen_random_uuid(), programme_id uuid not null references public.programmes(id), fiscal_year integer not null check(fiscal_year between 2020 and 2100),
 role_index integer not null check(role_index between 0 and 5), donor_posts integer not null default 0 check(donor_posts>=0), org_plan integer not null default 0 check(org_plan>=0),
 current_staff integer not null default 0 check(current_staff>=0), hiring_requests integer not null default 0 check(hiring_requests>=0),
 reference text not null check(length(reference)>0),updated_at timestamptz not null default now(), unique(programme_id,fiscal_year,role_index)
);
create table public.policy_settings (
 id uuid primary key default gen_random_uuid(), fiscal_year integer not null unique check(fiscal_year between 2020 and 2100),
 project_per_programme integer not null default 3 check(project_per_programme between 1 and 20), associates_per_project integer not null default 3 check(associates_per_project between 1 and 30),
 junior_per_senior integer[] not null default '{1,3,2}' check(cardinality(junior_per_senior)=3 and 0<all(junior_per_senior)),
 surge integer[] not null default '{4,2,0}' check(cardinality(surge)=3 and 0<=all(surge)),
 is_ratified boolean not null default false, effective_date date not null, reference text not null,updated_at timestamptz not null default now()
);
create table public.people_records (
 id uuid primary key default gen_random_uuid(), employee_id text not null unique, display_name text not null, programme_id uuid not null references public.programmes(id),
 role_index integer not null check(role_index between 0 and 5), allocation numeric(5,2) not null default 100 check(allocation>0 and allocation<=100),
 start_date date, end_date date, reporting_manager text not null default '',active boolean not null default true,reference text not null,updated_at timestamptz not null default now(),check(end_date is null or start_date is null or end_date>=start_date)
);
create index people_records_programme_idx on public.people_records(programme_id);
create table public.role_costs (
 id uuid primary key default gen_random_uuid(),programme_id uuid not null references public.programmes(id), fiscal_year integer not null,
 role_index integer not null check(role_index between 0 and 5),monthly_base numeric(14,2) not null check(monthly_base>=0),employer_percent numeric(5,2) not null default 0 check(employer_percent between 0 and 100),
 effective_date date not null,reference text not null,updated_at timestamptz not null default now(),unique(programme_id,fiscal_year,role_index)
);
create table public.budget_lines (
 id uuid primary key default gen_random_uuid(),programme_id uuid not null references public.programmes(id),fiscal_year integer not null check(fiscal_year between 2020 and 2100),
 category text not null,line_item text not null,quantity numeric(14,2),unit_cost numeric(14,2),original_annual numeric(14,2) not null check(original_annual>=0),annual_budget numeric(14,2) not null check(annual_budget>=0),
 monthly_plan numeric[] not null check(cardinality(monthly_plan)=12 and 0<=all(monthly_plan)),
 status text not null default 'draft' check(status in ('draft','approved')),is_sample boolean not null default false,
 reference text not null,approved_by uuid references auth.users(id),approved_at timestamptz,updated_at timestamptz not null default now(),
 check(abs(annual_budget-private.array_total(monthly_plan))<0.011),unique(programme_id,fiscal_year,line_item,is_sample)
);
create index budget_lines_approved_by_idx on public.budget_lines(approved_by);
create table public.financial_entries (
 id uuid primary key default gen_random_uuid(),programme_id uuid not null references public.programmes(id),budget_line_id uuid not null references public.budget_lines(id),
 month_index integer not null check(month_index between 0 and 11),kind text not null check(kind in ('actual','commitment','forecast')),
 amount numeric(14,2) not null check(amount>=0),reference text not null,updated_at timestamptz not null default now(),
 unique(budget_line_id,month_index,kind)
);
create index financial_entries_programme_idx on public.financial_entries(programme_id);
create table public.grants (
 id uuid primary key default gen_random_uuid(),programme_id uuid not null references public.programmes(id),fiscal_year integer not null,
 name text not null,amount numeric(14,2) not null check(amount>=0),status text not null check(status in ('confirmed','pipeline')),
 start_date date not null,end_date date not null,allocated_fte numeric(10,2) not null default 0 check(allocated_fte>=0),restrictions text not null default '',reference text not null,
 updated_at timestamptz not null default now(),check(end_date>=start_date)
);
create index grants_programme_idx on public.grants(programme_id);
create table public.period_locks (
 id uuid primary key default gen_random_uuid(),programme_id uuid not null references public.programmes(id),fiscal_year integer not null,
 month_index integer not null check(month_index between 0 and 11),closed boolean not null default false,reference text not null,
 updated_at timestamptz not null default now(),unique(programme_id,fiscal_year,month_index)
);
create table public.saved_scenarios (
 id uuid primary key default gen_random_uuid(),programme_id uuid not null references public.programmes(id),user_id uuid not null references auth.users(id),
 fiscal_year integer not null,name text not null,assumptions jsonb not null,source_snapshot jsonb not null,created_at timestamptz not null default now()
);
create index saved_scenarios_programme_idx on public.saved_scenarios(programme_id);
create index saved_scenarios_user_idx on public.saved_scenarios(user_id);

do $$ declare t text; begin
 foreach t in array array['workforce_inputs','policy_settings','people_records','role_costs','budget_lines','financial_entries','grants','period_locks','saved_scenarios'] loop
  execute format('alter table public.%I enable row level security',t);
  execute format('revoke all on public.%I from anon,authenticated',t);
  execute format('grant select on public.%I to authenticated',t);
  execute format('grant all on public.%I to service_role',t);
  execute format('create trigger audit_%I after insert or update or delete on public.%I for each row execute function private.log_change()',t,t);
 end loop;
 foreach t in array array['workforce_inputs','people_records','budget_lines','financial_entries','grants'] loop
  execute format('create policy read_scoped on public.%I for select to authenticated using(private.can_read_programme(programme_id))',t);
  execute format('grant insert,update on public.%I to authenticated',t);
  execute format('create policy insert_sources on public.%I for insert to authenticated with check((select private.can_write_budget()))',t);
  execute format('create policy update_sources on public.%I for update to authenticated using((select private.can_write_budget())) with check((select private.can_write_budget()))',t);
 end loop;
end $$;
create policy policies_read on public.policy_settings for select to authenticated using(exists(select 1 from public.memberships m where m.user_id=(select auth.uid()) and m.active and not m.needs_password_change));
create policy policies_insert on public.policy_settings for insert to authenticated with check((select private.can_write_budget()));
create policy policies_update on public.policy_settings for update to authenticated using((select private.can_write_budget())) with check((select private.can_write_budget()));
grant insert,update on public.policy_settings to authenticated;
create policy costs_read on public.role_costs for select to authenticated using(private.can_read_programme(programme_id) and (select private.salary_access()));
create policy costs_insert on public.role_costs for insert to authenticated with check((select private.can_write_budget()) and (select private.salary_access()));
create policy costs_update on public.role_costs for update to authenticated using((select private.can_write_budget()) and (select private.salary_access())) with check((select private.can_write_budget()) and (select private.salary_access()));
grant insert,update on public.role_costs to authenticated;
create policy locks_read on public.period_locks for select to authenticated using(private.can_read_programme(programme_id));
create policy scenarios_read on public.saved_scenarios for select to authenticated using(private.can_read_programme(programme_id) and (user_id=(select auth.uid()) or (select private.approver())));
create policy scenarios_insert on public.saved_scenarios for insert to authenticated with check(private.can_read_programme(programme_id) and user_id=(select auth.uid()));
grant insert on public.saved_scenarios to authenticated;
create policy programmes_insert on public.programmes for insert to authenticated with check((select private.can_write_budget()));
create policy programmes_update on public.programmes for update to authenticated using((select private.can_write_budget())) with check((select private.can_write_budget()));
grant insert,update on public.programmes to authenticated;
drop policy audit_read on public.audit_events;
create policy audit_read on public.audit_events for select to authenticated using((select private.is_admin()) or ((select private.can_write_budget()) and table_name not in ('memberships','role_costs')));

create function private.guard_financial_entry() returns trigger language plpgsql set search_path='' as $$
declare p uuid; y integer;
begin
 select programme_id,fiscal_year into p,y from public.budget_lines where id=new.budget_line_id;
 if p is null or p<>new.programme_id then raise exception 'Budget line and programme do not match'; end if;
 if exists(select 1 from public.period_locks where programme_id=p and fiscal_year=y and month_index=new.month_index and closed) and new.kind='actual' then raise exception 'This reporting month is closed. An authorised approver must reopen it.'; end if;
 if TG_OP='UPDATE' and old.kind='actual' and exists(select 1 from public.period_locks where programme_id=old.programme_id and fiscal_year=y and month_index=old.month_index and closed) then raise exception 'Closed actuals cannot be moved or reclassified'; end if;
 new.updated_at=now(); return new;
end $$;
revoke all on function private.guard_financial_entry() from public,anon,authenticated;
create trigger validate_financial_entry before insert or update on public.financial_entries for each row execute function private.guard_financial_entry();
create function private.guard_budget() returns trigger language plpgsql set search_path='' as $$
begin
 if new.status='approved' and auth.uid() is not null and not private.approver() then raise exception 'Only an authorised approver can approve a budget. Save changes as a draft.'; end if;
 if new.status='draft' then new.approved_by=null;new.approved_at=null; end if;
 new.updated_at=now();return new;
end $$;
revoke all on function private.guard_budget() from public,anon,authenticated;
create trigger guard_budget before insert or update on public.budget_lines for each row execute function private.guard_budget();

create function public.save_workforce(p_programme uuid,p_year integer,p_rows jsonb,p_reference text) returns void language plpgsql security invoker set search_path='' as $$
begin
 if not private.can_write_budget() then raise exception 'Data Administrator access required'; end if;
 if jsonb_array_length(p_rows)<>6 or length(trim(p_reference))=0 then raise exception 'Provide six role rows and a source reference'; end if;
 insert into public.workforce_inputs(programme_id,fiscal_year,role_index,donor_posts,org_plan,current_staff,hiring_requests,reference)
 select p_programme,p_year,x.role_index,x.donor_posts,x.org_plan,x.current_staff,x.hiring_requests,p_reference
 from jsonb_to_recordset(p_rows) x(role_index integer,donor_posts integer,org_plan integer,current_staff integer,hiring_requests integer)
 on conflict(programme_id,fiscal_year,role_index) do update set donor_posts=excluded.donor_posts,org_plan=excluded.org_plan,current_staff=excluded.current_staff,hiring_requests=excluded.hiring_requests,reference=excluded.reference,updated_at=now();
end $$;
revoke all on function public.save_workforce(uuid,integer,jsonb,text) from public,anon;
grant execute on function public.save_workforce(uuid,integer,jsonb,text) to authenticated;
insert into public.policy_settings(fiscal_year,effective_date,reference) values(2026,'2026-04-01','Workbook within-layer ratios and surge; cross-layer 1:3:9 is an unratified planning assumption');
