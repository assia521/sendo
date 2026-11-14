-- تشغيل مرة واحدة في Supabase > SQL Editor.
create extension if not exists pgcrypto;
create table if not exists public.profiles(id uuid primary key references auth.users(id) on delete cascade,full_name text not null default 'عضو Sendo',username text unique,created_at timestamptz not null default now());
create table if not exists public.posts(id uuid primary key default gen_random_uuid(),user_id uuid not null references public.profiles(id) on delete cascade,content text not null default '',media_url text,media_type text,created_at timestamptz not null default now(),constraint post_text_or_media check(length(trim(content))>0 or media_url is not null));
create table if not exists public.likes(post_id uuid not null references public.posts(id) on delete cascade,user_id uuid not null references public.profiles(id) on delete cascade,created_at timestamptz not null default now(),primary key(post_id,user_id));
create table if not exists public.messages(id uuid primary key default gen_random_uuid(),sender_id uuid not null references public.profiles(id) on delete cascade,recipient_id uuid not null references public.profiles(id) on delete cascade,body text not null check(length(trim(body)) between 1 and 2000),created_at timestamptz not null default now(),constraint messages_no_self check(sender_id<>recipient_id));
create index if not exists posts_created_idx on public.posts(created_at desc);
create index if not exists messages_pair_idx on public.messages(sender_id,recipient_id,created_at);
create or replace function public.handle_new_user() returns trigger language plpgsql security definer set search_path='' as $$ begin insert into public.profiles(id,full_name,username) values(new.id,coalesce(nullif(new.raw_user_meta_data->>'full_name',''),split_part(new.email,'@',1)),lower(regexp_replace(split_part(new.email,'@',1),'[^a-zA-Z0-9_]','','g'))||'_'||substr(new.id::text,1,6)); return new; end; $$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users for each row execute procedure public.handle_new_user();
alter table public.profiles enable row level security; alter table public.posts enable row level security; alter table public.likes enable row level security; alter table public.messages enable row level security;
drop policy if exists "profiles public read" on public.profiles; create policy "profiles public read" on public.profiles for select using(true);
drop policy if exists "profile owner update" on public.profiles; create policy "profile owner update" on public.profiles for update to authenticated using((select auth.uid())=id) with check((select auth.uid())=id);
drop policy if exists "posts public read" on public.posts; create policy "posts public read" on public.posts for select using(true);
drop policy if exists "post owner insert" on public.posts; create policy "post owner insert" on public.posts for insert to authenticated with check((select auth.uid())=user_id);
drop policy if exists "post owner update" on public.posts; create policy "post owner update" on public.posts for update to authenticated using((select auth.uid())=user_id) with check((select auth.uid())=user_id);
drop policy if exists "post owner delete" on public.posts; create policy "post owner delete" on public.posts for delete to authenticated using((select auth.uid())=user_id);
drop policy if exists "likes public read" on public.likes; create policy "likes public read" on public.likes for select using(true);
drop policy if exists "like as self" on public.likes; create policy "like as self" on public.likes for insert to authenticated with check((select auth.uid())=user_id);
drop policy if exists "unlike as self" on public.likes; create policy "unlike as self" on public.likes for delete to authenticated using((select auth.uid())=user_id);
-- Private messages: only sender or recipient can read; sender can send as themselves.
drop policy if exists "participants read messages" on public.messages; create policy "participants read messages" on public.messages for select to authenticated using((select auth.uid())=sender_id or (select auth.uid())=recipient_id);
drop policy if exists "sender creates message" on public.messages; create policy "sender creates message" on public.messages for insert to authenticated with check((select auth.uid())=sender_id);
-- Public media URLs support displaying attachments in posts. Uploads are scoped to the user's folder.
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values('sendo-media','sendo-media',true,52428800,array['image/jpeg','image/png','image/webp','image/gif','video/mp4','video/webm','audio/webm','audio/ogg','audio/mp4','audio/mpeg']) on conflict(id) do update set public=true,file_size_limit=52428800,allowed_mime_types=excluded.allowed_mime_types;
drop policy if exists "read Sendo files" on storage.objects; create policy "read Sendo files" on storage.objects for select using(bucket_id='sendo-media');
drop policy if exists "upload own Sendo files" on storage.objects; create policy "upload own Sendo files" on storage.objects for insert to authenticated with check(bucket_id='sendo-media' and (storage.foldername(name))[1]=(select auth.uid())::text);
drop policy if exists "delete own Sendo files" on storage.objects; create policy "delete own Sendo files" on storage.objects for delete to authenticated using(bucket_id='sendo-media' and (storage.foldername(name))[1]=(select auth.uid())::text);
