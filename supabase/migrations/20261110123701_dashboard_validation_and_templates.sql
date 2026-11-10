alter table public.programmes add column reference text not null default 'Imported staffing workbook';
alter table public.memberships add column last_changed_by uuid;
alter table public.period_locks add column updated_by uuid;
create or replace function private.log_change() returns trigger language plpgsql security definer set search_path='' as $$
declare previous jsonb; current_value jsonb; actor uuid;
begin
 if TG_OP<>'INSERT' then previous=to_jsonb(old); end if;
 if TG_OP<>'DELETE' then current_value=to_jsonb(new); end if;
 actor=auth.uid();
 if actor is null then actor=coalesce((current_value->>'last_changed_by')::uuid,(current_value->>'updated_by')::uuid,(current_value->>'approved_by')::uuid,(current_value->>'reviewed_by')::uuid,(current_value->>'created_by')::uuid); end if;
 insert into public.audit_events(table_name,record_id,operation,actor_id,before_data,after_data)
 values(TG_TABLE_NAME,coalesce(current_value->>'id',current_value->>'user_id',previous->>'id',previous->>'user_id'),TG_OP,actor,previous,current_value);
 if TG_OP='DELETE' then return old; end if;return new;
end $$;
create trigger audit_programmes after insert or update on public.programmes for each row execute function private.log_change();
do $$ declare t text; begin foreach t in array array['workforce_inputs','policy_settings','people_records','role_costs','grants','period_locks'] loop
 execute format('create trigger touch_record before update on public.%I for each row execute function private.touch_updated()',t);
end loop; end $$;
create function private.guard_policy() returns trigger language plpgsql set search_path='' as $$
begin
 if new.is_ratified and not private.approver() and auth.uid() is not null then raise exception 'An authorised approver must ratify this policy'; end if;
 return new;
end $$;
revoke all on function private.guard_policy() from public,anon,authenticated;
create trigger guard_policy before insert or update on public.policy_settings for each row execute function private.guard_policy();
create or replace function private.guard_financial_entry() returns trigger language plpgsql set search_path='' as $$
declare p uuid; y integer; old_y integer;
begin
 select programme_id,fiscal_year into p,y from public.budget_lines where id=new.budget_line_id;
 if p is null or p<>new.programme_id then raise exception 'Budget line and programme do not match'; end if;
 if exists(select 1 from public.period_locks where programme_id=p and fiscal_year=y and month_index=new.month_index and closed) and new.kind='actual' then raise exception 'This reporting month is closed. An authorised approver must reopen it.'; end if;
 if TG_OP='UPDATE' and old.kind='actual' then
 select fiscal_year into old_y from public.budget_lines where id=old.budget_line_id;
 if exists(select 1 from public.period_locks where programme_id=old.programme_id and fiscal_year=old_y and month_index=old.month_index and closed) then raise exception 'Closed actuals cannot be moved or reclassified'; end if;
 end if;
 new.updated_at=now();return new;
end $$;
create or replace function private.guard_budget() returns trigger language plpgsql set search_path='' as $$
begin
 if TG_OP='UPDATE' and (new.programme_id<>old.programme_id or new.fiscal_year<>old.fiscal_year or new.is_sample<>old.is_sample) and exists(select 1 from public.financial_entries where budget_line_id=old.id) then raise exception 'Budget programme, year and dataset cannot change after monthly records exist'; end if;
 if new.status='approved' and auth.uid() is not null and not private.approver() then raise exception 'Only an authorised approver can approve a budget. Save changes as a draft.'; end if;
 if new.status='draft' then new.approved_by=null;new.approved_at=null; end if;
 new.updated_at=now();return new;
end $$;
create function public.create_sample_budget(p_programme uuid,p_year integer) returns void language plpgsql security invoker set search_path='' as $$
declare categories text[]:=array['People & employer costs','Teacher training','Travel & field delivery','Technology & equipment','Assessment & MEL','Innovation activities','Shared / central allocation']; annual numeric[]:=array[15600000,2400000,1800000,1800000,600000,600000,1200000]; i integer; m integer; line uuid; ref text:='ILLUSTRATIVE TEMPLATE — not approved Peepul budget or expenditure';
begin
 if not private.can_write_budget() then raise exception 'Data Administrator access required'; end if;
 for i in 1..7 loop
 insert into public.budget_lines(programme_id,fiscal_year,category,line_item,original_annual,annual_budget,monthly_plan,is_sample,reference)
 values(p_programme,p_year,categories[i],'Sample · '||categories[i],annual[i],annual[i],array_fill(annual[i]/12,array[12]),true,ref)
 on conflict(programme_id,fiscal_year,line_item,is_sample) do nothing;
 select id into line from public.budget_lines where programme_id=p_programme and fiscal_year=p_year and line_item='Sample · '||categories[i] and is_sample;
 for m in 0..11 loop
 insert into public.financial_entries(programme_id,budget_line_id,month_index,kind,amount,reference)
 values(p_programme,line,m,'forecast',round(annual[i]/12*(0.92+0.01*m),2),ref) on conflict(budget_line_id,month_index,kind) do nothing;
 if not exists(select 1 from public.period_locks where programme_id=p_programme and fiscal_year=p_year and month_index=m and closed) then
 insert into public.financial_entries(programme_id,budget_line_id,month_index,kind,amount,reference)
 values(p_programme,line,m,'actual',round(annual[i]/12*(0.87+0.015*m),2),ref) on conflict(budget_line_id,month_index,kind) do nothing;
 end if;
 insert into public.financial_entries(programme_id,budget_line_id,month_index,kind,amount,reference)
 values(p_programme,line,m,'commitment',round(annual[i]/12*0.25,2),ref) on conflict(budget_line_id,month_index,kind) do nothing;
 end loop;
 end loop;
end $$;
revoke all on function public.create_sample_budget(uuid,integer) from public,anon;
grant execute on function public.create_sample_budget(uuid,integer) to authenticated;
