-- Apply after 001_rota.sql. Re-runnable; preserves existing authenticated bookings.
begin;
create table if not exists public.rota_guest_requests (
 id uuid primary key default gen_random_uuid(),
 request_key uuid not null unique,
 shift_id uuid not null references public.rota_shifts(id),
 name text not null check(length(trim(name)) between 1 and 80),
 mobile text not null check(mobile ~ '^0[0-9]{10}$'),
 expenses text not null check(expenses in ('later','claim','waive')),
 age_confirmed boolean not null default false,
 status text not null default 'pending' check(status in ('pending','confirmed','declined','cancelled')),
 created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
 reviewed_by uuid references auth.users(id)
);
create index if not exists guest_shift on public.rota_guest_requests(shift_id,status);
create index if not exists guest_mobile on public.rota_guest_requests(mobile,created_at);
alter table public.rota_guest_requests enable row level security;
revoke all on public.rota_guest_requests from public,anon,authenticated;

create or replace function public.rota_public_shifts() returns jsonb
language sql security definer set search_path='' as $$
 select coalesce(jsonb_agg(jsonb_build_object('id',s.id,'role',s.role,'day',s.day,
 'start',to_char(s.start,'HH24:MI'),'end',to_char(s."end",'HH24:MI'),
 'capacity',s.capacity,'staffing',s.staffing,'conditional',s.conditional,
 'bar',coalesce(s.kind='saturday-bar-pm',false) or s.role ilike '%bar%',
 'filled',(select count(*) from public.rota_requests r where r.shift_id=s.id and r.status='confirmed')+
 (select count(*) from public.rota_guest_requests g where g.shift_id=s.id and g.status='confirmed')) order by s.day,s.start),'[]'::jsonb)
 from public.rota_shifts s where not s.cancelled and s.fixture_active and
 s.day+s."end">now() at time zone 'Europe/London' and s.day< (now() at time zone 'Europe/London')::date+43;
$$;

create or replace function public.rota_guest_request(p_shift uuid,p_name text,p_mobile text,p_expenses text,p_age boolean,p_key uuid) returns void
language plpgsql security definer set search_path='' as $$
declare s public.rota_shifts; phone text; n integer;
begin
 phone=regexp_replace(coalesce(p_mobile,''),'[^0-9]','','g');
 if left(phone,2)='44' then phone='0'||substr(phone,3); end if;
 if length(trim(coalesce(p_name,''))) not between 1 and 80 or phone !~ '^0[0-9]{10}$' or coalesce(p_expenses,'') not in ('later','claim','waive') or p_key is null then raise exception 'Check your name, UK mobile number and expenses choice.'; end if;
 -- Serialize rate checks for this phone; serialize capacity with all booking paths.
 perform pg_advisory_xact_lock(hashtextextended(phone,735711));
 select * into s from public.rota_shifts where id=p_shift for update;
 if s.id is null or s.cancelled or not s.fixture_active or s.day+s."end"<=now() at time zone 'Europe/London' then raise exception 'This shift is no longer available.'; end if;
 if (coalesce(s.kind='saturday-bar-pm',false) or s.role ilike '%bar%') and p_age is distinct from true then raise exception 'Bar volunteers must be 18 or over.'; end if;
 -- Generic success for retries/duplicates; never reveal another person's request or details.
 if exists(select 1 from public.rota_guest_requests where request_key=p_key or (shift_id=p_shift and mobile=phone and status in ('pending','confirmed'))) then return; end if;
 select (select count(*) from public.rota_requests where shift_id=p_shift and status='confirmed')+(select count(*) from public.rota_guest_requests where shift_id=p_shift and status='confirmed') into n;
 if n>=s.capacity then raise exception 'This shift is full. Please choose another.'; end if;
 if (select count(*) from public.rota_guest_requests where mobile=phone and created_at>now()-interval '1 day')>=5 or (select count(*) from public.rota_guest_requests where shift_id=p_shift and status='pending')>=100 then raise exception 'Requests are temporarily limited. Please contact the club coordinator.'; end if;
 insert into public.rota_guest_requests(request_key,shift_id,name,mobile,expenses,age_confirmed) values(p_key,p_shift,trim(p_name),phone,p_expenses,coalesce(p_age,false));
end $$;

create or replace function public.rota_guest_admin() returns jsonb
language plpgsql security definer set search_path='' as $$
begin
 if not exists(select 1 from public.rota_members where user_id=auth.uid() and coordinator) then raise exception 'Coordinator access required.'; end if;
 perform public.rota_sync_schedule();
 return coalesce((select jsonb_agg(to_jsonb(g)||jsonb_build_object('role',s.role,'day',s.day,'start',to_char(s.start,'HH24:MI'),'end',to_char(s."end",'HH24:MI'),'bar',coalesce(s.kind='saturday-bar-pm',false) or s.role ilike '%bar%') order by s.day,s.start,g.created_at) from public.rota_guest_requests g join public.rota_shifts s on s.id=g.shift_id where s.day>=(now() at time zone 'Europe/London')::date),'[]'::jsonb);
end $$;

create or replace function public.rota_guest_review(p_id uuid,p_status text,p_contact_checked boolean,p_age_checked boolean) returns void
language plpgsql security definer set search_path='' as $$
declare g public.rota_guest_requests; s public.rota_shifts; sid uuid; n integer;
begin
 if not exists(select 1 from public.rota_members where user_id=auth.uid() and coordinator) then raise exception 'Coordinator access required.'; end if;
 if coalesce(p_status,'') not in ('confirmed','declined','cancelled') then raise exception 'Invalid review.'; end if;
 select shift_id into sid from public.rota_guest_requests where id=p_id;
 select * into s from public.rota_shifts where id=sid for update;
 select * into g from public.rota_guest_requests where id=p_id for update;
 if g.id is null then raise exception 'Request not found.'; end if;
 if g.status=p_status then return; end if;
 if p_status='confirmed' then
  if g.status<>'pending' or s.cancelled or not s.fixture_active or s.day+s."end"<=now() at time zone 'Europe/London' then raise exception 'Request is no longer available for approval.'; end if;
  if p_contact_checked is distinct from true then raise exception 'Contact the volunteer to verify this request before approval.'; end if;
  if (coalesce(s.kind='saturday-bar-pm',false) or s.role ilike '%bar%') and (not g.age_confirmed or p_age_checked is distinct from true) then raise exception 'Check the bar volunteer is 18 or over.'; end if;
  select (select count(*) from public.rota_requests where shift_id=s.id and status='confirmed')+(select count(*) from public.rota_guest_requests where shift_id=s.id and status='confirmed') into n;
  if n>=s.capacity then raise exception 'This shift is full.'; end if;
 end if;
 update public.rota_guest_requests set status=p_status,reviewed_by=auth.uid(),updated_at=now() where id=p_id;
end $$;

create or replace function public.rota_cancel_guests() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if new.cancelled or not new.fixture_active then update public.rota_guest_requests set status='cancelled',updated_at=now() where shift_id=new.id and status in ('pending','confirmed'); end if;
 return new;
end $$;
drop trigger if exists cancel_guest_requests on public.rota_shifts;
create trigger cancel_guest_requests after update of cancelled,fixture_active on public.rota_shifts for each row execute function public.rota_cancel_guests();
revoke all on function public.rota_cancel_guests() from public,anon,authenticated;
revoke all on function public.rota_public_shifts(),public.rota_guest_request(uuid,text,text,text,boolean,uuid),public.rota_guest_admin(),public.rota_guest_review(uuid,text,boolean,boolean) from public,anon,authenticated;
grant execute on function public.rota_public_shifts(),public.rota_guest_request(uuid,text,text,text,boolean,uuid) to anon,authenticated;
grant execute on function public.rota_guest_admin(),public.rota_guest_review(uuid,text,boolean,boolean) to authenticated;
create or replace function public.rota_snapshot() returns jsonb
language plpgsql security definer set search_path='' as $$
declare me public.rota_members;
begin
 if auth.uid() is null then raise exception 'Sign in first.'; end if;
 select * into me from public.rota_members where user_id=auth.uid();
 if me.user_id is null then return jsonb_build_object('me',null,'shifts','[]'::jsonb,'requests','[]'::jsonb); end if;
 if me.coordinator then perform public.rota_sync_schedule(); end if;
 return jsonb_build_object(
 'fixtures',coalesce((select jsonb_agg(to_jsonb(f) order by f.day) from public.rota_fixtures f where f.day >= (now() at time zone 'Europe/London')::date),'[]'::jsonb),
 'me',jsonb_build_object('id',me.user_id,'name',me.name,'coordinator',me.coordinator,'trusted',me.trusted),
 'shifts',coalesce((select jsonb_agg(jsonb_build_object('id',s.id,'role',s.role,'day',s.day,'start',to_char(s.start,'HH24:MI'),'end',to_char(s."end",'HH24:MI'),'capacity',s.capacity,'cancelled',s.cancelled or not s.fixture_active,'kind',s.kind,'staffing',s.staffing,'conditional',s.conditional,'fixture_active',s.fixture_active,'filled',(select count(*) from public.rota_requests r where r.shift_id=s.id and r.status='confirmed')+(select count(*) from public.rota_guest_requests g where g.shift_id=s.id and g.status='confirmed')) order by s.day,s.start) from public.rota_shifts s where s.day >= (now() at time zone 'Europe/London')::date),'[]'::jsonb),
 'requests',coalesce((select jsonb_agg(jsonb_build_object('shift_id',r.shift_id,'user_id',r.user_id,'status',r.status,'name',m.name,'expenses',r.expenses,'age_confirmed',r.age_confirmed)) from public.rota_requests r join public.rota_members m on m.user_id=r.user_id join public.rota_shifts s on s.id=r.shift_id where (me.coordinator or r.user_id=me.user_id) and s.day >= (now() at time zone 'Europe/London')::date),'[]'::jsonb));
end $$;

create or replace function public.rota_action(p_op text,p_args jsonb) returns void
language plpgsql security definer set search_path='' as $$
declare me public.rota_members; s public.rota_shifts; target uuid; current_status text; places integer; d date; t time; e time; c integer;
begin
 if auth.uid() is null then raise exception 'Sign in first.'; end if;
 select * into me from public.rota_members where user_id=auth.uid();
 if me.user_id is null then raise exception 'Add your name first.'; end if;
 if p_op='fixture' then
  if not me.coordinator then raise exception 'Coordinator access required.'; end if;
  perform pg_advisory_xact_lock(735710);
  if nullif(p_args->>'fixture_id','') is not null then
   update public.rota_fixtures set team=p_args->>'team',opponent=trim(p_args->>'opponent'),day=(p_args->>'day')::date,side=p_args->>'side',status=p_args->>'status',updated_at=now() where id=(p_args->>'fixture_id')::uuid;
   if not found then raise exception 'Fixture not found.'; end if;
  else
   insert into public.rota_fixtures(team,opponent,day,side,status) values(p_args->>'team',trim(p_args->>'opponent'),(p_args->>'day')::date,p_args->>'side',p_args->>'status');
  end if;
  perform public.rota_sync_schedule();
  return;
 end if;
 if p_op='create' then
  if not me.coordinator then raise exception 'Coordinator access required.'; end if;
  d=(p_args->>'day')::date;t=(p_args->>'start')::time;e=(p_args->>'end')::time;c=(p_args->>'capacity')::integer;
  if d is null or d<(now() at time zone 'Europe/London')::date or t is null or e is null or e<=t or c is null or c not between 1 and 30 or length(trim(coalesce(p_args->>'role',''))) not between 1 and 80 then raise exception 'Check the role, date, times and number of places.'; end if;
  insert into public.rota_shifts(role,day,start,"end",capacity,created_by) values(trim(p_args->>'role'),d,t,e,c,me.user_id);
  return;
 end if;
 -- All operations on a shift lock the same row: simultaneous approvals cannot overbook.
 select * into s from public.rota_shifts where id=(p_args->>'shift_id')::uuid for update;
 if s.id is null then raise exception 'Shift not found.'; end if;
 if p_op='close' then
  if not me.coordinator then raise exception 'Coordinator access required.'; end if;
  update public.rota_shifts set cancelled=true where id=s.id;
  update public.rota_requests set status='cancelled',updated_at=now() where shift_id=s.id;
  return;
 end if;
 if s.cancelled or not s.fixture_active then raise exception 'This shift has been cancelled.'; end if;
 if (s.day+s."end") <= (now() at time zone 'Europe/London') then raise exception 'This shift has finished.'; end if;
 target=me.user_id;
 if p_op in ('approve','decline') then
  if not me.coordinator then raise exception 'Coordinator access required.'; end if;
  target=(p_args->>'user_id')::uuid;
 end if;
 select status into current_status from public.rota_requests where shift_id=s.id and user_id=target;
 select (select count(*) from public.rota_requests where shift_id=s.id and status='confirmed')+(select count(*) from public.rota_guest_requests where shift_id=s.id and status='confirmed') into places;
 if p_op='request' then
  if current_status in ('pending','confirmed') then return; end if;
  if places>=s.capacity then raise exception 'This shift has just filled. Choose another shift.'; end if;
  if coalesce(p_args->>'expenses','') not in ('claim','waive') then raise exception 'Choose your expenses preference.'; end if;
  if (s.kind='saturday-bar-pm' or s.role ilike '%bar%') and (p_args->'age_confirmed') is distinct from 'true'::jsonb then raise exception 'Bar volunteers must confirm they are 18 or over.'; end if;
  insert into public.rota_requests(shift_id,user_id,status,expenses,age_confirmed) values(s.id,me.user_id,case when me.trusted and not (coalesce(s.kind,'')='saturday-bar-pm' or s.role ilike '%bar%') then 'confirmed' else 'pending' end,p_args->>'expenses',coalesce((p_args->'age_confirmed')='true'::jsonb,false))
  on conflict(shift_id,user_id) do update set status=excluded.status,expenses=excluded.expenses,age_confirmed=excluded.age_confirmed,updated_at=now();
 elsif p_op='withdraw' then
  update public.rota_requests set status='withdrawn',updated_at=now() where shift_id=s.id and user_id=me.user_id;
 elsif p_op in ('approve','decline') then
  if current_status is distinct from 'pending' then raise exception 'This request is no longer awaiting approval.'; end if;
  if p_op='approve' and (s.kind='saturday-bar-pm' or s.role ilike '%bar%') and ((p_args->'age_verified') is distinct from 'true'::jsonb or not exists(select 1 from public.rota_requests where shift_id=s.id and user_id=target and age_confirmed)) then raise exception 'Confirm the bar volunteer is 18 or over before approval.'; end if;
  if p_op='approve' and places>=s.capacity then raise exception 'This shift is full.'; end if;
  update public.rota_requests set status=case when p_op='approve' then 'confirmed' else 'declined' end,updated_at=now() where shift_id=s.id and user_id=target;
 else raise exception 'Unknown action.';
 end if;
end $$;

commit;
