create extension if not exists pgcrypto;
create extension if not exists pg_trgm;

drop table if exists public.saved_posts cascade;
drop table if exists public.comment_votes cascade;
drop table if exists public.post_votes cascade;
drop table if exists public.comments cascade;
drop table if exists public.community_posts cascade;
drop table if exists public.profiles cascade;

drop function if exists public.sync_post_comment_count();
drop function if exists public.sync_comment_upvotes();
drop function if exists public.sync_post_upvotes();
drop function if exists public.ensure_comment_parent_same_post();
drop function if exists public.set_updated_at();

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null check (char_length(btrim(display_name)) between 1 and 50),
  email text unique,
  bio text not null default '' check (char_length(bio) <= 500),
  hide_activity boolean not null default false,
  show_online_status boolean not null default true,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

create table public.community_posts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references public.profiles(id) on delete set null,
  title text not null check (char_length(btrim(title)) between 1 and 300),
  content text not null default '' check (char_length(content) <= 10000),
  channel text not null check (
    channel in (
      'b/Anxiety',
      'b/Depression',
      'b/Stress',
      'b/Sleep',
      'b/Relationships',
      'b/Academic',
      'b/General'
    )
  ),
  upvotes integer not null default 0,
  comment_count integer not null default 0,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

create table public.comments (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references public.community_posts(id) on delete cascade,
  user_id uuid references public.profiles(id) on delete set null,
  parent_comment_id uuid references public.comments(id) on delete cascade,
  content text not null check (char_length(btrim(content)) between 1 and 5000),
  upvotes integer not null default 0,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint comments_parent_not_self
    check (parent_comment_id is null or parent_comment_id <> id)
);

create table public.post_votes (
  post_id uuid not null references public.community_posts(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  vote_type smallint not null check (vote_type in (-1, 1)),
  created_at timestamptz not null default timezone('utc', now()),
  primary key (post_id, user_id)
);

create table public.comment_votes (
  comment_id uuid not null references public.comments(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  vote_type smallint not null check (vote_type in (-1, 1)),
  created_at timestamptz not null default timezone('utc', now()),
  primary key (comment_id, user_id)
);

create table public.saved_posts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  post_id uuid not null references public.community_posts(id) on delete cascade,
  post_title text not null,
  post_content text not null default '',
  saved_at timestamptz not null default timezone('utc', now()),
  unique (user_id, post_id)
);

create index community_posts_channel_created_idx
  on public.community_posts (channel, created_at desc);

create index community_posts_channel_upvotes_idx
  on public.community_posts (channel, upvotes desc);

create index community_posts_user_created_idx
  on public.community_posts (user_id, created_at desc);

create index community_posts_search_idx
  on public.community_posts
  using gin ((coalesce(title, '') || ' ' || coalesce(content, '')) gin_trgm_ops);

create index comments_post_created_idx
  on public.comments (post_id, created_at asc);

create index comments_parent_created_idx
  on public.comments (parent_comment_id, created_at asc);

create index comments_user_created_idx
  on public.comments (user_id, created_at desc);

create index saved_posts_user_saved_idx
  on public.saved_posts (user_id, saved_at desc);

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = timezone('utc', now());
  return new;
end;
$$;

create or replace function public.ensure_comment_parent_same_post()
returns trigger
language plpgsql
as $$
begin
  if new.parent_comment_id is null then
    return new;
  end if;

  if not exists (
    select 1
    from public.comments c
    where c.id = new.parent_comment_id
      and c.post_id = new.post_id
  ) then
    raise exception 'parent comment must belong to the same post';
  end if;

  return new;
end;
$$;

create or replace function public.sync_post_upvotes()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  target_post_id uuid;
begin
  if tg_op = 'DELETE' then
    target_post_id := old.post_id;
  else
    target_post_id := new.post_id;
  end if;

  update public.community_posts p
  set upvotes = coalesce((
    select sum(v.vote_type)::int
    from public.post_votes v
    where v.post_id = target_post_id
  ), 0)
  where p.id = target_post_id;

  return null;
end;
$$;

create or replace function public.sync_comment_upvotes()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  target_comment_id uuid;
begin
  if tg_op = 'DELETE' then
    target_comment_id := old.comment_id;
  else
    target_comment_id := new.comment_id;
  end if;

  update public.comments c
  set upvotes = coalesce((
    select sum(v.vote_type)::int
    from public.comment_votes v
    where v.comment_id = target_comment_id
  ), 0)
  where c.id = target_comment_id;

  return null;
end;
$$;

create or replace function public.sync_post_comment_count()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op in ('INSERT', 'UPDATE') then
    update public.community_posts p
    set comment_count = (
      select count(*)::int
      from public.comments c
      where c.post_id = new.post_id
    )
    where p.id = new.post_id;
  end if;

  if tg_op = 'DELETE'
     or (tg_op = 'UPDATE' and old.post_id is distinct from new.post_id) then
    update public.community_posts p
    set comment_count = (
      select count(*)::int
      from public.comments c
      where c.post_id = old.post_id
    )
    where p.id = old.post_id;
  end if;

  return null;
end;
$$;

create trigger profiles_set_updated_at
before update on public.profiles
for each row
execute function public.set_updated_at();

create trigger community_posts_set_updated_at
before update on public.community_posts
for each row
execute function public.set_updated_at();

create trigger comments_set_updated_at
before update on public.comments
for each row
execute function public.set_updated_at();

create trigger comments_parent_same_post
before insert or update on public.comments
for each row
execute function public.ensure_comment_parent_same_post();

create trigger post_votes_sync_upvotes
after insert or update or delete on public.post_votes
for each row
execute function public.sync_post_upvotes();

create trigger comment_votes_sync_upvotes
after insert or update or delete on public.comment_votes
for each row
execute function public.sync_comment_upvotes();

create trigger comments_sync_count
after insert or update or delete on public.comments
for each row
execute function public.sync_post_comment_count();

alter table public.profiles enable row level security;
alter table public.community_posts enable row level security;
alter table public.comments enable row level security;
alter table public.post_votes enable row level security;
alter table public.comment_votes enable row level security;
alter table public.saved_posts enable row level security;

create policy profiles_select_all
on public.profiles
for select
using (true);

create policy profiles_insert_own
on public.profiles
for insert
to authenticated
with check (auth.uid() = id);

create policy profiles_update_own
on public.profiles
for update
to authenticated
using (auth.uid() = id)
with check (auth.uid() = id);

create policy community_posts_select_all
on public.community_posts
for select
using (true);

create policy community_posts_insert_own
on public.community_posts
for insert
to authenticated
with check (auth.uid() = user_id);

create policy community_posts_update_own
on public.community_posts
for update
to authenticated
using (auth.uid() = user_id)
with check (auth.uid() = user_id);

create policy community_posts_delete_own
on public.community_posts
for delete
to authenticated
using (auth.uid() = user_id);

create policy comments_select_all
on public.comments
for select
using (true);

create policy comments_insert_own
on public.comments
for insert
to authenticated
with check (auth.uid() = user_id);

create policy comments_update_own
on public.comments
for update
to authenticated
using (auth.uid() = user_id)
with check (auth.uid() = user_id);

create policy comments_delete_own
on public.comments
for delete
to authenticated
using (auth.uid() = user_id);

create policy post_votes_select_own
on public.post_votes
for select
to authenticated
using (auth.uid() = user_id);

create policy post_votes_insert_own
on public.post_votes
for insert
to authenticated
with check (auth.uid() = user_id);

create policy post_votes_update_own
on public.post_votes
for update
to authenticated
using (auth.uid() = user_id)
with check (auth.uid() = user_id);

create policy post_votes_delete_own
on public.post_votes
for delete
to authenticated
using (auth.uid() = user_id);

create policy comment_votes_select_own
on public.comment_votes
for select
to authenticated
using (auth.uid() = user_id);

create policy comment_votes_insert_own
on public.comment_votes
for insert
to authenticated
with check (auth.uid() = user_id);

create policy comment_votes_update_own
on public.comment_votes
for update
to authenticated
using (auth.uid() = user_id)
with check (auth.uid() = user_id);

create policy comment_votes_delete_own
on public.comment_votes
for delete
to authenticated
using (auth.uid() = user_id);

create policy saved_posts_select_own
on public.saved_posts
for select
to authenticated
using (auth.uid() = user_id);

create policy saved_posts_insert_own
on public.saved_posts
for insert
to authenticated
with check (auth.uid() = user_id);

create policy saved_posts_delete_own
on public.saved_posts
for delete
to authenticated
using (auth.uid() = user_id);
