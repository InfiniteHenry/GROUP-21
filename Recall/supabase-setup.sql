create table if not exists public.recall_data (
  user_id uuid primary key references auth.users(id) on delete cascade,
  data jsonb not null default '{"decks":[],"sessions":[]}'::jsonb
    check (jsonb_typeof(data) = 'object'),
  updated_at timestamptz not null default now()
);

alter table public.recall_data enable row level security;
revoke all on public.recall_data from anon, authenticated;
grant select, insert, update, delete on public.recall_data to authenticated;

drop policy if exists "Users can read their own Recall data" on public.recall_data;
drop policy if exists "Users can create their own Recall data" on public.recall_data;
drop policy if exists "Users can update their own Recall data" on public.recall_data;
drop policy if exists "Users can delete their own Recall data" on public.recall_data;

create policy "Users can read their own Recall data"
  on public.recall_data for select to authenticated
  using ((select auth.uid()) = user_id);
create policy "Users can create their own Recall data"
  on public.recall_data for insert to authenticated
  with check ((select auth.uid()) = user_id);
create policy "Users can update their own Recall data"
  on public.recall_data for update to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);
create policy "Users can delete their own Recall data"
  on public.recall_data for delete to authenticated
  using ((select auth.uid()) = user_id);
