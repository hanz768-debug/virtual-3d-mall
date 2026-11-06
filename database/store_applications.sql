-- Run ONLY in World Virtual Mall Supabase SQL Editor.
-- Authenticated seller applications; no storefront allocation without admin approval.
create table if not exists public.mall_store_applications (
 id uuid primary key default gen_random_uuid(),
 applicant_id uuid not null references auth.users(id) on delete cascade,
 market_id text not null references public.mall_markets(id),
 unit_number integer not null check(unit_number between 1 and 20),
 brand_name text not null check(char_length(trim(brand_name)) between 2 and 120),
 description text not null default '' check(char_length(description)<=2000),
 status text not null default 'pending' check(status in ('pending','approved','rejected')),
 reviewed_at timestamptz,
 created_at timestamptz not null default now()
);
create unique index if not exists mall_one_pending_per_user on public.mall_store_applications(applicant_id) where status='pending';
create table if not exists public.mall_admins (
 user_id uuid primary key references auth.users(id) on delete cascade
);
alter table public.mall_store_applications enable row level security;
alter table public.mall_admins enable row level security;
drop policy if exists "Applicant reads own applications" on public.mall_store_applications;
create policy "Applicant reads own applications" on public.mall_store_applications
for select to authenticated using (applicant_id=(select auth.uid()));
drop policy if exists "Applicant submits own application" on public.mall_store_applications;
create policy "Applicant submits own application" on public.mall_store_applications
for insert to authenticated with check (applicant_id=(select auth.uid()) and status='pending' and reviewed_at is null
and exists(select 1 from public.mall_units u where u.market_id=mall_store_applications.market_id
and u.unit_number=mall_store_applications.unit_number and u.status='available' and u.seller_id is null));
-- Admin role cannot be assigned by browser clients.
create or replace function public.mall_is_admin()
returns boolean language sql stable security definer set search_path='' as $$
select exists(select 1 from public.mall_admins where user_id=(select auth.uid()));
$$;
revoke all on function public.mall_is_admin() from public;
grant execute on function public.mall_is_admin() to authenticated;
drop policy if exists "Admins read applications" on public.mall_store_applications;
create policy "Admins read applications" on public.mall_store_applications
for select to authenticated using (public.mall_is_admin());
create or replace function public.mall_review_application(p_id uuid,p_approve boolean)
returns text language plpgsql security definer set search_path='' as $$
declare a public.mall_store_applications%rowtype;
declare u public.mall_units%rowtype;
declare s uuid;
begin
 if not public.mall_is_admin() then raise exception 'Not authorized'; end if;
 select * into a from public.mall_store_applications where id=p_id for update;
 if not found or a.status <> 'pending' then raise exception 'Application not pending'; end if;
 if not p_approve then
  update public.mall_store_applications set status='rejected',reviewed_at=now() where id=p_id;
  return 'rejected';
 end if;
 select * into u from public.mall_units where market_id=a.market_id and unit_number=a.unit_number for update;
 if not found or u.status <> 'available' or u.seller_id is not null then raise exception 'Store no longer available'; end if;
 select id into s from public.mall_sellers where user_id=a.applicant_id for update;
 if s is null then
  insert into public.mall_sellers(user_id,brand_name,status) values(a.applicant_id,a.brand_name,'approved') returning id into s;
 else
  if exists(select 1 from public.mall_units where seller_id=s) then raise exception 'Seller already owns a store'; end if;
  update public.mall_sellers set brand_name=a.brand_name,status='approved' where id=s;
 end if;
 update public.mall_units set seller_id=s,status='occupied' where id=u.id;
 update public.mall_store_applications set status='approved',reviewed_at=now() where id=p_id;
 return 'approved';
end $$;
revoke all on function public.mall_review_application(uuid,boolean) from public,anon;
grant execute on function public.mall_review_application(uuid,boolean) to authenticated;
-- AFTER verifying the admin email in Authentication > Users, manually grant admin role:
-- insert into public.mall_admins(user_id) values ('REPLACE_WITH_VERIFIED_ADMIN_USER_UUID');
