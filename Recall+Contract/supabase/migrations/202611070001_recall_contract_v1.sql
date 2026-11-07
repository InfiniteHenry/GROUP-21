-- Recall contract v1. All writes are performed through validated RPCs.
create extension if not exists pgcrypto with schema extensions;

create table if not exists public.profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null default 'Learner' check (char_length(display_name) between 1 and 60),
  timezone text not null default 'UTC', daily_goal integer not null default 20 check (daily_goal between 1 and 500),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table if not exists public.decks (
  id uuid primary key, user_id uuid not null references auth.users(id) on delete cascade,
  name text not null check (char_length(name) between 1 and 120), emoji text not null default '' check (char_length(emoji)<=16),
  color text not null default '#6c63ff' check (color='' or color ~ '^#[0-9a-fA-F]{6}$'),
  description text not null default '' check (char_length(description)<=500), card_order text not null default 'saved' check(card_order in ('saved','shuffle')),
  position integer not null, created_at timestamptz not null, updated_at timestamptz not null, deleted_at timestamptz
);
create table if not exists public.cards (
  id uuid primary key, user_id uuid not null references auth.users(id) on delete cascade,
  deck_id uuid not null references public.decks(id), front text not null check(char_length(front) between 1 and 4000),
  back text not null check(char_length(back) between 1 and 8000), position integer not null,
  created_at timestamptz not null, updated_at timestamptz not null, deleted_at timestamptz
);
create table if not exists public.card_state (
  card_id uuid primary key references public.cards(id), user_id uuid not null references auth.users(id) on delete cascade,
  due_at timestamptz not null, interval_days integer not null default 0 check(interval_days>=0),
  correct_streak integer not null default 0 check(correct_streak>=0), reps integer not null default 0 check(reps>=0),
  lapses integer not null default 0 check(lapses>=0), last_reviewed_at timestamptz
);
create table if not exists public.reviews (
  id uuid primary key, user_id uuid not null references auth.users(id) on delete cascade,
  card_id uuid not null references public.cards(id), session_id uuid not null, rating smallint not null check(rating in (0,1)), reviewed_at timestamptz not null
);
create index if not exists reviews_user_reviewed_idx on public.reviews(user_id, reviewed_at desc);
create table if not exists public.study_sessions (
  id uuid primary key, user_id uuid not null references auth.users(id) on delete cascade,
  deck_id uuid, mode text not null check(mode in ('due','manual','shuffle')), started_at timestamptz not null,
  finished_at timestamptz, card_ids uuid[] not null default '{}', answers integer not null default 0, correct integer not null default 0
);
create table if not exists public.sync_changes (
  id uuid primary key, user_id uuid not null references auth.users(id) on delete cascade,
  entity text not null, entity_id uuid not null, change_type text not null, payload jsonb not null,
  created_at timestamptz not null, unique(user_id,id)
);
create table if not exists public.tombstones (
  user_id uuid not null references auth.users(id) on delete cascade, entity text not null check(entity in ('decks','cards')),
  entity_id uuid not null, deleted_at timestamptz not null, primary key(user_id,entity,entity_id)
);

create or replace function public.prevent_user_id_change() returns trigger language plpgsql set search_path = '' as $$
begin
  if new.user_id is distinct from old.user_id then raise exception using errcode='42501', message='user_id is immutable'; end if;
  return new;
end $$;
do $$ declare t text; begin
  foreach t in array array['profiles','decks','cards','card_state','reviews','study_sessions','sync_changes','tombstones'] loop
    execute format('drop trigger if exists immutable_user_id on public.%I',t);
    execute format('create trigger immutable_user_id before update on public.%I for each row execute function public.prevent_user_id_change()',t);
    execute format('alter table public.%I enable row level security',t);
    execute format('drop policy if exists own_rows on public.%I',t);
    execute format('create policy own_rows on public.%I for select to authenticated using (user_id = (select auth.uid()))',t);
    execute format('revoke all on public.%I from anon, authenticated',t);
    execute format('grant select on public.%I to authenticated',t);
  end loop;
end $$;

create or replace function public.sync_push(p_changes jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v_uid uuid := auth.uid(); c jsonb; v_entity text; v_id uuid; v_payload jsonb; v_at timestamptz; v_rejected jsonb := '[]'::jsonb;
begin
  if v_uid is null then raise exception using errcode='42501', message='auth_required'; end if;
  if jsonb_typeof(p_changes) <> 'array' then raise exception using errcode='22023', message='invalid_input'; end if;
  for c in select value from jsonb_array_elements(p_changes) loop
    v_entity := c->>'entity'; v_payload := c->'payload';
    v_id := coalesce(nullif(v_payload->>'id','')::uuid, case when v_entity='states' then nullif(v_payload->>'card_id','')::uuid else null end);
    if c->>'id' is null or v_entity not in ('decks','cards','states','reviews','sessions') or v_id is null then
      raise exception using errcode='22023', message='invalid_input';
    end if;
    insert into public.sync_changes(id,user_id,entity,entity_id,change_type,payload,created_at)
      values ((c->>'id')::uuid,v_uid,v_entity,v_id,c->>'type',v_payload,coalesce(nullif(v_payload->>'updated_at','')::timestamptz,now())) on conflict(user_id,id) do nothing;
    if v_entity in ('decks','cards') and c->>'type'='delete' then
      v_at := coalesce(nullif(v_payload->>'deleted_at','')::timestamptz,now());
      insert into public.tombstones(user_id,entity,entity_id,deleted_at) values(v_uid,v_entity,v_id,v_at)
        on conflict(user_id,entity,entity_id) do update set deleted_at=greatest(public.tombstones.deleted_at,excluded.deleted_at);
      if v_entity='decks' then
        update public.decks set deleted_at=v_at where id=v_id and user_id=v_uid;
        insert into public.tombstones(user_id,entity,entity_id,deleted_at) select v_uid,'cards',id,v_at from public.cards where deck_id=v_id and user_id=v_uid
          on conflict(user_id,entity,entity_id) do update set deleted_at=greatest(public.tombstones.deleted_at,excluded.deleted_at);
        update public.cards set deleted_at=v_at where deck_id=v_id and user_id=v_uid;
      else update public.cards set deleted_at=v_at where id=v_id and user_id=v_uid; end if;
    elsif v_entity='decks' then
      if char_length(coalesce(v_payload->>'name','')) not between 1 and 120 or char_length(coalesce(v_payload->>'emoji',''))>16 or char_length(coalesce(v_payload->>'description',''))>500 or coalesce(v_payload->>'card_order','saved') not in ('saved','shuffle') or (coalesce(v_payload->>'color','')<>'' and v_payload->>'color' !~ '^#[0-9a-fA-F]{6}$') then raise exception using errcode='22023',message='invalid_input'; end if;
      if not exists(select 1 from public.tombstones t where t.user_id=v_uid and t.entity='decks' and t.entity_id=v_id) then
        insert into public.decks(id,user_id,name,emoji,color,description,card_order,position,created_at,updated_at)
        values(v_id,v_uid,btrim(v_payload->>'name'),coalesce(v_payload->>'emoji',''),coalesce(v_payload->>'color','#6c63ff'),coalesce(v_payload->>'description',''),coalesce(v_payload->>'card_order','saved'),(v_payload->>'position')::int,coalesce((v_payload->>'created_at')::timestamptz,now()),coalesce((v_payload->>'updated_at')::timestamptz,now()))
        on conflict(id) do update set name=excluded.name,emoji=excluded.emoji,color=excluded.color,description=excluded.description,card_order=excluded.card_order,position=excluded.position,updated_at=excluded.updated_at where public.decks.user_id=v_uid and public.decks.deleted_at is null;
      end if;
    elsif v_entity='cards' then
      if char_length(coalesce(v_payload->>'front','')) not between 1 and 4000 or char_length(coalesce(v_payload->>'back','')) not between 1 and 8000 then raise exception using errcode='22023',message='invalid_input'; end if;
      if not exists(select 1 from public.tombstones t where t.user_id=v_uid and t.entity='cards' and t.entity_id=v_id) and exists(select 1 from public.decks d where d.id=(v_payload->>'deck_id')::uuid and d.user_id=v_uid and d.deleted_at is null) then
        insert into public.cards(id,user_id,deck_id,front,back,position,created_at,updated_at) values(v_id,v_uid,(v_payload->>'deck_id')::uuid,v_payload->>'front',v_payload->>'back',(v_payload->>'position')::int,coalesce((v_payload->>'created_at')::timestamptz,now()),coalesce((v_payload->>'updated_at')::timestamptz,now()))
        on conflict(id) do update set deck_id=excluded.deck_id,front=excluded.front,back=excluded.back,position=excluded.position,updated_at=excluded.updated_at where public.cards.user_id=v_uid and public.cards.deleted_at is null;
      end if;
    elsif v_entity='states' then
      if exists(select 1 from public.cards x where x.id=(v_payload->>'card_id')::uuid and x.user_id=v_uid and x.deleted_at is null) then
        insert into public.card_state(card_id,user_id,due_at,interval_days,correct_streak,reps,lapses,last_reviewed_at) values((v_payload->>'card_id')::uuid,v_uid,(v_payload->>'due_at')::timestamptz,(v_payload->>'interval_days')::int,(v_payload->>'correct_streak')::int,(v_payload->>'reps')::int,(v_payload->>'lapses')::int,nullif(v_payload->>'last_reviewed_at','')::timestamptz)
        on conflict(card_id) do update set due_at=excluded.due_at,interval_days=excluded.interval_days,correct_streak=excluded.correct_streak,reps=excluded.reps,lapses=excluded.lapses,last_reviewed_at=excluded.last_reviewed_at where public.card_state.user_id=v_uid and coalesce(excluded.last_reviewed_at,'-infinity')>=coalesce(public.card_state.last_reviewed_at,'-infinity');
      end if;
    elsif v_entity='reviews' then
      if (v_payload->>'rating')::int not in (0,1) then raise exception using errcode='22023',message='invalid_input'; end if;
      insert into public.reviews(id,user_id,card_id,session_id,rating,reviewed_at) values(v_id,v_uid,(v_payload->>'card_id')::uuid,(v_payload->>'session_id')::uuid,(v_payload->>'rating')::smallint,(v_payload->>'reviewed_at')::timestamptz) on conflict(id) do nothing;
    elsif v_entity='sessions' then
      insert into public.study_sessions(id,user_id,deck_id,mode,started_at,finished_at,card_ids,answers,correct)
      values(v_id,v_uid,nullif(v_payload->>'deck_id','')::uuid,v_payload->>'mode',(v_payload->>'started_at')::timestamptz,nullif(v_payload->>'finished_at','')::timestamptz,
        array(select jsonb_array_elements_text(coalesce(v_payload->'card_ids','[]'::jsonb))::uuid),coalesce((v_payload->>'answers')::int,0),coalesce((v_payload->>'correct')::int,0))
      on conflict(id) do update set finished_at=excluded.finished_at,answers=excluded.answers,correct=excluded.correct where public.study_sessions.user_id=v_uid;
    end if;
  end loop;
  return jsonb_build_object('accepted',jsonb_array_length(p_changes),'rejected',v_rejected);
end $$;

create or replace function public.sync_pull(p_since timestamptz default null) returns jsonb
language sql stable security definer set search_path = '' as $$
 select jsonb_build_object('data',jsonb_build_object(
  'profile',(select to_jsonb(p) from public.profiles p where p.user_id=auth.uid()),
  'decks',coalesce((select jsonb_agg(to_jsonb(d)) from public.decks d where d.user_id=auth.uid()),'[]'::jsonb),
  'cards',coalesce((select jsonb_agg(to_jsonb(c)) from public.cards c where c.user_id=auth.uid()),'[]'::jsonb),
  'states',coalesce((select jsonb_agg(to_jsonb(s)-'user_id') from public.card_state s where s.user_id=auth.uid()),'[]'::jsonb),
  'reviews',coalesce((select jsonb_agg(to_jsonb(r)) from public.reviews r where r.user_id=auth.uid()),'[]'::jsonb),
  'sessions',coalesce((select jsonb_agg(to_jsonb(s)) from public.study_sessions s where s.user_id=auth.uid()),'[]'::jsonb),
  'tombstones',coalesce((select jsonb_agg(to_jsonb(t)) from public.tombstones t where t.user_id=auth.uid()),'[]'::jsonb)
  ));
$$;
create or replace function public.profile_update(p_profile jsonb) returns jsonb language plpgsql security definer set search_path = '' as $$
declare uid uuid:=auth.uid(); begin if uid is null then raise exception using errcode='42501',message='auth_required'; end if;
 if char_length(p_profile->>'display_name') not between 1 and 60 or (p_profile->>'daily_goal')::int not between 1 and 500 then raise exception using errcode='22023',message='invalid_input'; end if;
 insert into public.profiles(user_id,display_name,timezone,daily_goal) values(uid,p_profile->>'display_name',p_profile->>'timezone',(p_profile->>'daily_goal')::int) on conflict(user_id) do update set display_name=excluded.display_name,timezone=excluded.timezone,daily_goal=excluded.daily_goal,updated_at=now(); return (select to_jsonb(p) from public.profiles p where p.user_id=uid); end $$;
create table if not exists public.account_action_limits(user_id uuid not null references auth.users(id) on delete cascade, action text not null, acted_at timestamptz not null default now());
alter table public.account_action_limits enable row level security; revoke all on public.account_action_limits from anon,authenticated;
create or replace function public.account_delete() returns jsonb language plpgsql security definer set search_path = '' as $$
declare uid uuid:=auth.uid(); begin if uid is null then raise exception using errcode='42501',message='auth_required'; end if;
 if exists(select 1 from public.account_action_limits where user_id=uid and action='delete' and acted_at>now()-interval '1 hour') then raise exception using errcode='P0001',message='rate_limited'; end if;
 insert into public.account_action_limits(user_id,action) values(uid,'delete'); delete from auth.users where id=uid; return jsonb_build_object('deleted',true); end $$;
create or replace function public.account_export(p_format text) returns jsonb language plpgsql security definer set search_path = '' as $$
declare uid uuid:=auth.uid(); begin if uid is null then raise exception using errcode='42501',message='auth_required'; end if;
 if p_format not in ('json','csv') then raise exception using errcode='22023',message='invalid_input'; end if;
 if exists(select 1 from public.account_action_limits where user_id=uid and action='export' and acted_at>now()-interval '1 hour') then raise exception using errcode='P0001',message='rate_limited'; end if;
 insert into public.account_action_limits(user_id,action) values(uid,'export');
 if p_format='csv' then return jsonb_build_object('csv',coalesce((select string_agg(quote_nullable(d.name)||','||quote_nullable(c.front)||','||quote_nullable(c.back),E'\n') from public.cards c join public.decks d on d.id=c.deck_id where c.user_id=uid and c.deleted_at is null and d.deleted_at is null),'')); end if;
 return jsonb_build_object('profiles',(select to_jsonb(p) from public.profiles p where p.user_id=uid),'decks',(select coalesce(jsonb_agg(to_jsonb(d)),'[]') from public.decks d where d.user_id=uid),'cards',(select coalesce(jsonb_agg(to_jsonb(c)),'[]') from public.cards c where c.user_id=uid),'reviews',(select coalesce(jsonb_agg(to_jsonb(r)),'[]') from public.reviews r where r.user_id=uid),'sessions',(select coalesce(jsonb_agg(to_jsonb(s)),'[]') from public.study_sessions s where s.user_id=uid)); end $$;
create or replace function public.server_history(p_days integer) returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare uid uuid:=auth.uid(); z text; begin if uid is null then raise exception using errcode='42501',message='auth_required'; end if; if p_days not between 1 and 365 then raise exception using errcode='22023',message='invalid_input'; end if;
 select timezone into z from public.profiles where user_id=uid; return (select jsonb_build_object('days',coalesce(jsonb_agg(jsonb_build_object('date',d::date::text,'reviews',coalesce(x.n,0),'correct',coalesce(x.c,0)) order by d),'[]'::jsonb),'accuracy',case when sum(coalesce(x.n,0))=0 then null else sum(coalesce(x.c,0))::numeric/sum(coalesce(x.n,0)) end,'total_reviews',sum(coalesce(x.n,0)),'streak',jsonb_build_object('current',0,'longest',0)) from generate_series(current_date-(p_days-1),current_date,interval '1 day') d left join lateral(select count(*) n,count(*) filter(where rating=1) c from public.reviews r where r.user_id=uid and (r.reviewed_at at time zone coalesce(z,'UTC'))::date=d::date) x on true); end $$;
revoke all on function public.sync_push(jsonb),public.sync_pull(timestamptz),public.profile_update(jsonb),public.account_delete(),public.account_export(text),public.server_history(integer) from public, anon;
grant execute on function public.sync_push(jsonb),public.sync_pull(timestamptz),public.profile_update(jsonb),public.account_delete(),public.account_export(text),public.server_history(integer) to authenticated;
