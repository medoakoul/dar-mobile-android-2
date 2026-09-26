-- مخطط قاعدة بيانات دار العقارية - شغّل الملف كاملًا في Supabase SQL Editor
create extension if not exists pgcrypto;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  email text not null unique,
  name text not null,
  phone text,
  role text not null default 'seeker' check (role in ('admin','broker','seeker')),
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.properties (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.profiles(id) on delete cascade,
  purpose text not null check (purpose in ('buy','rent','sale')),
  kind text not null,
  title text not null,
  city text not null,
  district text not null,
  price numeric not null check (price > 0),
  beds integer,
  baths integer,
  area numeric check (area > 0),
  label text,
  description text not null,
  features jsonb not null default '[]'::jsonb,
  status text not null default 'pending' check (status in ('pending','active','rejected','archived')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.property_favorites (
  user_id uuid not null references public.profiles(id) on delete cascade,
  property_id uuid not null references public.properties(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, property_id)
);

create table if not exists public.property_requests (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  purpose text not null default 'buy' check (purpose in ('buy','rent')),
  kind text not null,
  city text not null,
  budget numeric not null check (budget > 0),
  status text not null default 'open' check (status in ('open','matched','closed')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  property_id uuid references public.properties(id) on delete set null,
  title text not null,
  body text,
  kind text not null default 'system',
  read boolean not null default false,
  created_at timestamptz not null default now()
);

alter table public.profiles enable row level security;
alter table public.properties enable row level security;
alter table public.property_favorites enable row level security;
alter table public.property_requests enable row level security;
alter table public.notifications enable row level security;

create or replace function public.is_admin() returns boolean
language sql stable security definer set search_path=public
as $$ select exists(select 1 from public.profiles where id=auth.uid() and role='admin' and active=true); $$;

create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path=public
as $$
begin
  insert into public.profiles(id,email,name,phone,role)
  values(new.id,new.email,coalesce(new.raw_user_meta_data->>'name',new.email),new.raw_user_meta_data->>'phone',
    case when new.raw_user_meta_data->>'role'='broker' then 'broker' else 'seeker' end)
  on conflict(id) do update set email=excluded.email,name=excluded.name,phone=excluded.phone;
  return new;
end $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users for each row execute procedure public.handle_new_user();

drop policy if exists profiles_self_admin_select on public.profiles;
create policy profiles_self_admin_select on public.profiles for select to authenticated using (id=auth.uid() or public.is_admin());
drop policy if exists profiles_admin_update on public.profiles;
create policy profiles_admin_update on public.profiles for update to authenticated using (public.is_admin()) with check (public.is_admin());

drop policy if exists properties_public_active_select on public.properties;
create policy properties_public_active_select on public.properties for select to authenticated using (status='active' or owner_id=auth.uid() or public.is_admin());
drop policy if exists properties_owner_insert on public.properties;
create policy properties_owner_insert on public.properties for insert to authenticated with check (owner_id=auth.uid() or public.is_admin());
drop policy if exists properties_owner_update on public.properties;
create policy properties_owner_update on public.properties for update to authenticated using (owner_id=auth.uid() or public.is_admin()) with check (owner_id=auth.uid() or public.is_admin());

drop policy if exists favorites_own_all on public.property_favorites;
create policy favorites_own_all on public.property_favorites for all to authenticated using (user_id=auth.uid()) with check (user_id=auth.uid());

drop policy if exists requests_own_all on public.property_requests;
create policy requests_own_all on public.property_requests for all to authenticated using (user_id=auth.uid() or public.is_admin()) with check (user_id=auth.uid() or public.is_admin());

drop policy if exists notifications_own_select on public.notifications;
create policy notifications_own_select on public.notifications for select to authenticated using (user_id=auth.uid() or public.is_admin());
drop policy if exists notifications_own_update on public.notifications;
create policy notifications_own_update on public.notifications for update to authenticated using (user_id=auth.uid() or public.is_admin()) with check (user_id=auth.uid() or public.is_admin());

grant select on public.profiles,public.properties,public.property_favorites,public.property_requests,public.notifications to authenticated;
grant insert,update,delete on public.properties,public.property_favorites,public.property_requests to authenticated;
grant update on public.profiles,public.notifications to authenticated;

-- بعد إنشاء أول حساب:
-- update public.profiles set role='admin' where email='your-email@example.com';
