-- Sendo: شغّل هذا الملف مرة واحدة في Supabase > SQL Editor.
create extension if not exists pgcrypto;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null default 'عضو Sendo',
  username text unique,
  created_at timestamptz not null default now()
);

create table if not exists public.posts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  content text not null default '',
  media_url text,
  media_type text,
  created_at timestamptz not null default now(),
  constraint posts_content_or_media check (length(trim(content)) > 0 or media_url is not null)
);

create table if not exists public.likes (
  post_id uuid not null references public.posts(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (post_id, user_id)
);

create index if not exists posts_created_at_idx on public.posts (created_at desc);
create index if not exists posts_user_id_idx on public.posts (user_id);
create index if not exists likes_post_id_idx on public.likes (post_id);

-- Create the matching profile automatically whenever someone registers.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = ''
as $$
begin
  insert into public.profiles (id, full_name, username)
  values (
    new.id,
    coalesce(nullif(new.raw_user_meta_data ->> 'full_name', ''), split_part(new.email, '@', 1)),
    lower(regexp_replace(split_part(new.email, '@', 1), '[^a-zA-Z0-9_]', '', 'g')) || '_' || substr(new.id::text, 1, 6)
  );
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

alter table public.profiles enable row level security;
alter table public.posts enable row level security;
alter table public.likes enable row level security;

drop policy if exists "Profiles are visible to everyone" on public.profiles;
create policy "Profiles are visible to everyone" on public.profiles for select using (true);
drop policy if exists "Users can update their profile" on public.profiles;
create policy "Users can update their profile" on public.profiles for update to authenticated using ((select auth.uid()) = id) with check ((select auth.uid()) = id);

drop policy if exists "Posts are visible to everyone" on public.posts;
create policy "Posts are visible to everyone" on public.posts for select using (true);
drop policy if exists "Signed-in users can create posts" on public.posts;
create policy "Signed-in users can create posts" on public.posts for insert to authenticated with check ((select auth.uid()) = user_id);
drop policy if exists "Authors can update their posts" on public.posts;
create policy "Authors can update their posts" on public.posts for update to authenticated using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
drop policy if exists "Authors can delete their posts" on public.posts;
create policy "Authors can delete their posts" on public.posts for delete to authenticated using ((select auth.uid()) = user_id);

drop policy if exists "Likes are visible to everyone" on public.likes;
create policy "Likes are visible to everyone" on public.likes for select using (true);
drop policy if exists "Users can like as themselves" on public.likes;
create policy "Users can like as themselves" on public.likes for insert to authenticated with check ((select auth.uid()) = user_id);
drop policy if exists "Users can remove their likes" on public.likes;
create policy "Users can remove their likes" on public.likes for delete to authenticated using ((select auth.uid()) = user_id);

-- Public media bucket: posts are viewable by anyone; only signed-in users may upload.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('sendo-media', 'sendo-media', true, 52428800, array['image/jpeg','image/png','image/webp','image/gif','video/mp4','video/webm','audio/webm','audio/ogg','audio/mp4','audio/mpeg'])
on conflict (id) do update set public = true, file_size_limit = 52428800,
  allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "Sendo media is publicly readable" on storage.objects;
create policy "Sendo media is publicly readable" on storage.objects for select using (bucket_id = 'sendo-media');
drop policy if exists "Signed-in users upload their own Sendo media" on storage.objects;
create policy "Signed-in users upload their own Sendo media" on storage.objects for insert to authenticated with check (bucket_id = 'sendo-media' and (storage.foldername(name))[1] = (select auth.uid())::text);
drop policy if exists "Users can delete their own Sendo media" on storage.objects;
create policy "Users can delete their own Sendo media" on storage.objects for delete to authenticated using (bucket_id = 'sendo-media' and (storage.foldername(name))[1] = (select auth.uid())::text);
