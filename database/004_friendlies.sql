begin;
create table if not exists public.club_teams(name text primary key);
insert into public.club_teams(name) values ('U8 Reds'),('U8 Yellows'),('U8 Blacks'),('U9 Blacks'),('U9 Yellows'),('U10 Blacks'),('U10 Reds'),('U11 Yellows'),('U11 Blacks'),('U11 Bees'),('U12 Yellows'),('U12 Blacks'),('U13 Yellows'),('U13 Blacks'),('U14 Blacks'),('U14 Blues'),('U15 Reds'),('U15 Blacks'),('U15 Yellows'),('U16 Yellows'),('U16 Reds'),('U18'),('U10 Girls'),('U12 Girls'),('U14 Girls'),('Men’s First Team'),('Men’s Development Team') on conflict do nothing;
create table if not exists public.team_managers(user_id uuid references auth.users(id),team text references public.club_teams(name),primary key(user_id,team));
create table if not exists public.club_friendlies(
 id uuid primary key,team text not null references public.club_teams(name),opponent text not null check(length(trim(opponent)) between 1 and 100),
 day date not null,kickoff time not null,side text not null check(side in ('Home','Away')),venue text not null check(length(trim(venue)) between 1 and 200),
 status text not null default 'Scheduled' check(status in ('Scheduled','Postponed','Cancelled')),
 created_by uuid not null references auth.users(id),updated_at timestamptz not null default clock_timestamp(),
 unique(team,day,kickoff,opponent)
);
create index if not exists friendly_day on public.club_friendlies(day);
alter table public.club_teams enable row level security;
alter table public.team_managers enable row level security;
alter table public.club_friendlies enable row level security;
revoke all on public.club_teams,public.team_managers,public.club_friendlies from public,anon,authenticated;
create or replace function public.friendly_list() returns jsonb language sql security definer set search_path='' as $$
select coalesce(jsonb_agg(jsonb_build_object('id',id,'team',team,'opponent',opponent,'date',day,'time',to_char(kickoff,'HH24:MI'),'side',side,'venue',venue,'status',status,'kind','Friendly') order by day,kickoff),'[]'::jsonb) from public.club_friendlies where day >= (now() at time zone 'Europe/London')::date;
$$;
create or replace function public.friendly_manager() returns jsonb language plpgsql security definer set search_path='' as $$
declare allowed text[];
begin
 if auth.uid() is null then raise exception 'Sign in first.'; end if;
 select array_agg(t.name order by t.name) into allowed from public.club_teams t where exists(select 1 from public.team_managers m where m.user_id=auth.uid() and m.team=t.name) or exists(select 1 from public.rota_members m where m.user_id=auth.uid() and m.coordinator);
 if allowed is null then raise exception 'Your manager account has not been assigned a team yet. Contact the club coordinator.'; end if;
 return jsonb_build_object('teams',allowed,'fixtures',coalesce((select jsonb_agg(to_jsonb(f) order by day,kickoff) from public.club_friendlies f where team=any(allowed) and day >= (now() at time zone 'Europe/London')::date-30),'[]'::jsonb));
end $$;
create or replace function public.friendly_save(p_data jsonb) returns uuid language plpgsql security definer set search_path='' as $$
declare old public.club_friendlies; fid uuid; chosen text; permitted boolean;
begin
 if auth.uid() is null then raise exception 'Sign in first.'; end if;
 fid=(p_data->>'id')::uuid; chosen=p_data->>'team';
 select * into old from public.club_friendlies where id=fid for update;
 permitted=exists(select 1 from public.rota_members where user_id=auth.uid() and coordinator);
 if not permitted and (not exists(select 1 from public.team_managers where user_id=auth.uid() and team=chosen) or (old.id is not null and not exists(select 1 from public.team_managers where user_id=auth.uid() and team=old.team))) then raise exception 'You can only manage friendlies for your assigned team.'; end if;
 if old.id is not null and (p_data->>'updated_at')::timestamptz is distinct from old.updated_at then raise exception 'This game has changed. Refresh before editing.'; end if;
 if (p_data->>'day')::date < (now() at time zone 'Europe/London')::date then raise exception 'Choose today or a future date.'; end if;
 insert into public.club_friendlies(id,team,opponent,day,kickoff,side,venue,status,created_by)
 values(fid,chosen,trim(p_data->>'opponent'),(p_data->>'day')::date,(p_data->>'kickoff')::time,p_data->>'side',trim(p_data->>'venue'),coalesce(p_data->>'status','Scheduled'),auth.uid())
 on conflict(id) do update set team=excluded.team,opponent=excluded.opponent,day=excluded.day,kickoff=excluded.kickoff,side=excluded.side,venue=excluded.venue,status=excluded.status,updated_at=clock_timestamp();
 return fid;
end $$;
revoke all on function public.friendly_list(),public.friendly_manager(),public.friendly_save(jsonb) from public,anon,authenticated;
grant execute on function public.friendly_list() to anon,authenticated;
grant execute on function public.friendly_manager(),public.friendly_save(jsonb) to authenticated;
commit;
