-- Private first-team ledger. Requires 001_rota.sql. Re-runnable.
begin;
create table if not exists public.finance_members(user_id uuid primary key references auth.users(id));
create table if not exists public.finance_settings(id boolean primary key default true check(id),budget_pence bigint not null default 1000000 check(budget_pence between 0 and 1000000000));
insert into public.finance_settings(id) values(true) on conflict do nothing;
create table if not exists public.finance_players(id uuid primary key default gen_random_uuid(),name text not null check(length(trim(name)) between 1 and 100),fee_pence integer not null check(fee_pence between 0 and 10000000));
create table if not exists public.finance_matches(
 id uuid primary key,day date not null,opponent text not null check(length(trim(opponent)) between 1 and 100),
 type text not null check(type in ('league','cup')),league_number integer unique check(league_number between 1 and 30),
 status text not null default 'draft' check(status in ('draft','approved')),lines jsonb not null,
 cost_pence bigint not null default 0,paid_pence bigint not null default 0,
 approved_by uuid references auth.users(id), updated_at timestamptz not null default now(),
 check((type='league' and league_number is not null) or (type='cup' and league_number is null)),
 check(cost_pence>=0 and paid_pence between 0 and cost_pence),check(type<>'cup' or cost_pence=0)
);
create table if not exists public.finance_audit(id bigint generated always as identity primary key,actor uuid not null,operation text not null,record jsonb not null,created_at timestamptz not null default now());
alter table public.finance_members enable row level security;
alter table public.finance_settings enable row level security;
alter table public.finance_players enable row level security;
alter table public.finance_matches enable row level security;
alter table public.finance_audit enable row level security;
revoke all on public.finance_members,public.finance_settings,public.finance_players,public.finance_matches,public.finance_audit from public,anon,authenticated;

create or replace function public.finance_snapshot() returns jsonb language plpgsql security definer set search_path='' as $$
begin
 if not exists(select 1 from public.finance_members where user_id=auth.uid()) then raise exception 'Finance access required.'; end if;
 return jsonb_build_object('budget_pence',(select budget_pence from public.finance_settings where id),
 'players',coalesce((select jsonb_agg(to_jsonb(p) order by p.name) from public.finance_players p),'[]'::jsonb),
 'matches',coalesce((select jsonb_agg(to_jsonb(m) order by m.day,m.league_number) from public.finance_matches m),'[]'::jsonb));
end $$;

create or replace function public.finance_action(p_op text,p_args jsonb) returns void language plpgsql security definer set search_path='' as $$
declare m public.finance_matches; pl public.finance_players; entry jsonb; lines jsonb='[]'::jsonb; seen uuid[]='{}';
 gross bigint; deduct bigint; total bigint=0; mid uuid; typ text; before_row jsonb; payment bigint;
begin
 if not exists(select 1 from public.finance_members where user_id=auth.uid()) then raise exception 'Finance access required.'; end if;
 -- Serialize ledger operations to make duplicate approvals/payment updates safe.
 perform pg_advisory_xact_lock(735712);
 if p_op='budget' then
  select to_jsonb(s) into before_row from public.finance_settings s where id;
  update public.finance_settings set budget_pence=(p_args->>'budget_pence')::bigint where id;
 elsif p_op='player' then
  if nullif(p_args->>'id','') is null then
   insert into public.finance_players(name,fee_pence) values(trim(p_args->>'name'),(p_args->>'fee_pence')::integer);
  else
   select to_jsonb(p) into before_row from public.finance_players p where id=(p_args->>'id')::uuid;
   if before_row is null then raise exception 'Player not found.'; end if;
   update public.finance_players set name=trim(p_args->>'name'),fee_pence=(p_args->>'fee_pence')::integer where id=(p_args->>'id')::uuid;
  end if;
 elsif p_op='save_match' then
  mid=(p_args->>'id')::uuid;typ=p_args->>'type';
  select * into m from public.finance_matches where id=mid;
  before_row=to_jsonb(m);
  if m.id is not null and (p_args->>'expected_updated_at')::timestamptz is distinct from m.updated_at then raise exception 'This sheet changed. Refresh before editing.'; end if;
  if m.status='approved' then raise exception 'Approved match is locked. Reopen it before editing.'; end if;
  if coalesce(jsonb_typeof(p_args->'lines'),'')<>'array' or jsonb_array_length(p_args->'lines') not between 1 and 30 then raise exception 'Select between 1 and 30 players.'; end if;
  for entry in select value from jsonb_array_elements(p_args->'lines') loop
   select * into pl from public.finance_players where id=(entry->>'player_id')::uuid;
   if pl.id is null or pl.id=any(seen) or coalesce(entry->>'appearance','') not in ('starter','used','unused') then raise exception 'Check each player and appearance; no duplicates allowed.'; end if;
   seen=array_append(seen,pl.id);
   gross=case when typ='cup' or entry->>'appearance'='unused' then 0 when entry->>'appearance'='used' then round(pl.fee_pence/2.0)::bigint else pl.fee_pence end;
   deduct=coalesce((entry->>'deduction_pence')::bigint,0);
   if deduct<0 or deduct>gross or (deduct>0 and length(trim(coalesce(entry->>'reason',''))) not between 1 and 200) then raise exception 'Deductions need a reason and cannot exceed the match fee.'; end if;
   lines=lines||jsonb_build_array(jsonb_build_object('player_id',pl.id,'name',pl.name,'appearance',entry->>'appearance','fee_pence',pl.fee_pence,'gross_pence',gross,'deduction_pence',deduct,'reason',left(coalesce(entry->>'reason',''),200),'net_pence',gross-deduct));
   total=total+gross-deduct;
  end loop;
  insert into public.finance_matches(id,day,opponent,type,league_number,lines,cost_pence) values(mid,(p_args->>'day')::date,trim(p_args->>'opponent'),typ,case when typ='league' then (p_args->>'league_number')::integer else null end,lines,total)
  on conflict(id) do update set day=excluded.day,opponent=excluded.opponent,type=excluded.type,league_number=excluded.league_number,lines=excluded.lines,cost_pence=excluded.cost_pence,updated_at=now();
 elsif p_op in ('approve','paid','reopen') then
  select * into m from public.finance_matches where id=(p_args->>'id')::uuid for update;
  if m.id is null then raise exception 'Match not found.'; end if;
  before_row=to_jsonb(m);
  if m.id is not null and (p_args->>'expected_updated_at')::timestamptz is distinct from m.updated_at then raise exception 'This sheet changed. Refresh before editing.'; end if;
  if p_op='approve' then
   if m.day>(now() at time zone 'Europe/London')::date then raise exception 'Approve appearances after the match has been played.'; end if;
   if m.status='approved' then return; end if;
   update public.finance_matches set status='approved',approved_by=auth.uid(),updated_at=now() where id=m.id;
  elsif p_op='paid' then
   if m.status<>'approved' then raise exception 'Approve the match before recording payments.'; end if;
   payment=(p_args->>'paid_pence')::bigint;
   if payment is null or payment<0 or payment>m.cost_pence then raise exception 'Paid must be between zero and the approved cost.'; end if;
   update public.finance_matches set paid_pence=payment,updated_at=now() where id=m.id;
  else
   if m.paid_pence>0 then raise exception 'Reconcile recorded payments before reopening this match.'; end if;
   update public.finance_matches set status='draft',approved_by=null,updated_at=now() where id=m.id;
  end if;
 else raise exception 'Unknown finance action.';
 end if;
 insert into public.finance_audit(actor,operation,record) values(auth.uid(),p_op,jsonb_build_object('before',before_row,'input',p_args));
end $$;
revoke all on function public.finance_snapshot(),public.finance_action(text,jsonb) from public,anon,authenticated;
grant execute on function public.finance_snapshot(),public.finance_action(text,jsonb) to authenticated;
commit;
