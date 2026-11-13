-- Run once in the SQL editor of a dedicated Supabase project.
-- No real volunteer data is seeded. All writes go through authorised RPCs.
begin;
create table public.rota_members (
 user_id uuid primary key references auth.users(id) on delete cascade,
 name text not null check (length(trim(name)) between 1 and 80),
 coordinator boolean not null default false,
 trusted boolean not null default false
);
create table public.rota_fixtures (
 id uuid primary key default gen_random_uuid(),
 team text not null check(team in ('Men’s First Team','Men’s Development Team')),
 opponent text not null check(length(trim(opponent)) between 1 and 100),
 day date not null,
 side text not null check(side in ('Home','Away')),
 status text not null check(status in ('Scheduled','Postponed','Cancelled')),
 updated_at timestamptz not null default now()
);
alter table public.rota_fixtures enable row level security;
revoke all on public.rota_fixtures from anon,authenticated;
create table public.rota_shifts (
 id uuid primary key default gen_random_uuid(),
 role text not null check(length(trim(role)) between 1 and 80),
 day date not null, start time not null, "end" time not null,
 capacity integer not null check(capacity between 1 and 30),
 cancelled boolean not null default false,
 kind text,
 staffing text not null default 'minimum' check(staffing in ('ideal','minimum')),
 conditional boolean not null default false,
 fixture_active boolean not null default true,
 unique(day,kind),
 created_by uuid not null references auth.users(id),
 check("end">start)
);
create table public.rota_requests (
 shift_id uuid references public.rota_shifts(id) on delete cascade,
 user_id uuid references public.rota_members(user_id) on delete cascade,
 status text not null check(status in ('pending','confirmed','withdrawn','declined','cancelled')),
 expenses text not null check(expenses in ('claim','waive')),
 age_confirmed boolean not null default false,
 updated_at timestamptz not null default now(),
 primary key(shift_id,user_id)
);
create index rota_shifts_day on public.rota_shifts(day);
create index rota_requests_user on public.rota_requests(user_id);
alter table public.rota_members enable row level security;
alter table public.rota_shifts enable row level security;
alter table public.rota_requests enable row level security;
revoke all on public.rota_members,public.rota_shifts,public.rota_requests from anon,authenticated;

create function public.rota_enrol(p_name text) returns void
language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null or coalesce(auth.jwt()->>'email','')='' then raise exception 'Sign in with your email first.'; end if;
 if length(trim(p_name)) not between 1 and 80 then raise exception 'Enter your name (up to 80 characters).'; end if;
 insert into public.rota_members(user_id,name) values(auth.uid(),trim(p_name))
 on conflict(user_id) do update set name=excluded.name;
end $$;

-- Called only from coordinator RPCs. Fixed six-week window, idempotent by day/kind.
create function public.rota_sync_schedule() returns void
language plpgsql security definer set search_path='' as $$
declare sat date; d date; base date; t record; active boolean;
begin
 if not exists(select 1 from public.rota_members where user_id=auth.uid() and coordinator) then raise exception 'Coordinator access required.'; end if;
 perform pg_advisory_xact_lock(735710);
 base=(now() at time zone 'Europe/London')::date;
 base=base+case when extract(isodow from base)=7 then -1 else 6-extract(isodow from base)::integer end;
 for i in 0..5 loop
  sat=base+7*i;
  for t in select * from (values
   ('saturday-kitchen-am','Kitchen · Saturday morning','09:00'::time,'13:00'::time,2,'ideal',false,0),
   ('saturday-kitchen-pm','Kitchen · Saturday afternoon','14:00'::time,'18:00'::time,2,'minimum',true,0),
   ('saturday-bar-pm','Bar · Saturday afternoon','14:00'::time,'18:00'::time,1,'minimum',true,0),
   ('sunday-kitchen-am','Kitchen · Sunday morning','09:00'::time,'13:00'::time,2,'minimum',false,1)
  ) as x(kind,role,start,finish,capacity,staffing,conditional,offset_days) loop
   d=sat+t.offset_days;
   active=not t.conditional or exists(select 1 from public.rota_fixtures f where f.day=d and f.side='Home' and f.status='Scheduled');
   insert into public.rota_shifts(role,day,start,"end",capacity,created_by,kind,staffing,conditional,fixture_active)
   values(t.role,d,t.start,t.finish,t.capacity,auth.uid(),t.kind,t.staffing,t.conditional,active)
   on conflict(day,kind) do update set fixture_active=excluded.fixture_active;
  end loop;
 end loop;
 update public.rota_requests r set status='cancelled',updated_at=now()
 from public.rota_shifts s where s.id=r.shift_id and not s.fixture_active and r.status in ('pending','confirmed');
end $$;
revoke all on function public.rota_sync_schedule() from public,anon,authenticated;

create function public.rota_snapshot() returns jsonb
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
 'shifts',coalesce((select jsonb_agg(jsonb_build_object('id',s.id,'role',s.role,'day',s.day,'start',to_char(s.start,'HH24:MI'),'end',to_char(s."end",'HH24:MI'),'capacity',s.capacity,'cancelled',s.cancelled or not s.fixture_active,'kind',s.kind,'staffing',s.staffing,'conditional',s.conditional,'fixture_active',s.fixture_active,'filled',(select count(*) from public.rota_requests r where r.shift_id=s.id and r.status='confirmed')) order by s.day,s.start) from public.rota_shifts s where s.day >= (now() at time zone 'Europe/London')::date),'[]'::jsonb),
 'requests',coalesce((select jsonb_agg(jsonb_build_object('shift_id',r.shift_id,'user_id',r.user_id,'status',r.status,'name',m.name,'expenses',r.expenses,'age_confirmed',r.age_confirmed)) from public.rota_requests r join public.rota_members m on m.user_id=r.user_id join public.rota_shifts s on s.id=r.shift_id where (me.coordinator or r.user_id=me.user_id) and s.day >= (now() at time zone 'Europe/London')::date),'[]'::jsonb));
end $$;

create function public.rota_action(p_op text,p_args jsonb) returns void
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
 select count(*) into places from public.rota_requests where shift_id=s.id and status='confirmed';
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
revoke all on function public.rota_enrol(text),public.rota_snapshot(),public.rota_action(text,jsonb) from public,anon;
grant execute on function public.rota_enrol(text),public.rota_snapshot(),public.rota_action(text,jsonb) to authenticated;
commit;
