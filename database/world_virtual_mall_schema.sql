-- World Virtual Mall initial schema. Run ONLY in the world-virtual-mall project.
create extension if not exists pgcrypto;
create table if not exists public.mall_markets (
 id text primary key, name text not null, created_at timestamptz not null default now()
);
create table if not exists public.mall_sellers (
 id uuid primary key default gen_random_uuid(),
 user_id uuid not null unique references auth.users(id) on delete cascade,
 brand_name text not null check(length(brand_name) between 2 and 120),
 status text not null default 'pending' check(status in ('pending','approved','suspended')),
 created_at timestamptz not null default now()
);
create table if not exists public.mall_units (
 id uuid primary key default gen_random_uuid(),
 market_id text not null references public.mall_markets(id),
 unit_number integer not null check(unit_number > 0),
 seller_id uuid unique references public.mall_sellers(id) on delete set null,
 status text not null default 'available' check(status in ('available','reserved','occupied','inactive')),
 created_at timestamptz not null default now(),
 unique(market_id,unit_number),
 check((status = 'occupied' and seller_id is not null) or status <> 'occupied')
);
create table if not exists public.mall_products (
 id uuid primary key default gen_random_uuid(),
 seller_id uuid not null references public.mall_sellers(id) on delete cascade,
 unit_id uuid not null references public.mall_units(id),
 title text not null,
 description text,
 price_cents bigint not null check(price_cents >= 0),
 currency text not null default 'USD' check(currency ~ '^[A-Z]{3}$'),
 status text not null default 'draft' check(status in ('draft','published','archived')),
 created_at timestamptz not null default now()
);
create table if not exists public.mall_media (
 id uuid primary key default gen_random_uuid(),
 seller_id uuid not null references public.mall_sellers(id) on delete cascade,
 unit_id uuid references public.mall_units(id),
 product_id uuid references public.mall_products(id) on delete cascade,
 kind text not null check(kind in ('storefront','interior','product')),
 storage_path text not null,
 status text not null default 'pending' check(status in ('pending','approved','rejected')),
 created_at timestamptz not null default now(),
 check((kind = 'product' and product_id is not null) or (kind <> 'product' and unit_id is not null))
);
create index if not exists mall_units_market_idx on public.mall_units(market_id);
create index if not exists mall_products_unit_idx on public.mall_products(unit_id);
create index if not exists mall_media_unit_idx on public.mall_media(unit_id);
alter table public.mall_markets enable row level security;
alter table public.mall_sellers enable row level security;
alter table public.mall_units enable row level security;
alter table public.mall_products enable row level security;
alter table public.mall_media enable row level security;
create policy "Public markets" on public.mall_markets for select to anon,authenticated using(true);
create policy "Public units" on public.mall_units for select to anon,authenticated using(true);
create policy "Seller reads own profile" on public.mall_sellers for select to authenticated using(user_id=(select auth.uid()));
create policy "Seller creates own pending profile" on public.mall_sellers for insert to authenticated with check(user_id=(select auth.uid()) and status='pending');
create policy "Seller reads own products" on public.mall_products for select to authenticated using(seller_id in (select id from public.mall_sellers where user_id=(select auth.uid())));
create policy "Public published products" on public.mall_products for select to anon,authenticated using(status='published');
create policy "Seller creates draft products" on public.mall_products for insert to authenticated with check(status='draft' and seller_id in (select id from public.mall_sellers where user_id=(select auth.uid()) and status='approved') and exists(select 1 from public.mall_units where id=unit_id and seller_id=mall_products.seller_id and status='occupied'));
create policy "Seller reads own media" on public.mall_media for select to authenticated using(seller_id in (select id from public.mall_sellers where user_id=(select auth.uid())));
create policy "Public approved media" on public.mall_media for select to anon,authenticated using(status='approved');
insert into public.mall_markets(id,name) values
('jewelry','جواهرات'),('fashion','پوشاک'),('electronics','الکترونیک'),('home','مبلمان و خانه'),('auto','خودرو'),('shoes','کفش و کیف'),('beauty','زیبایی و عطر'),('sports','ورزش')
on conflict(id) do nothing;
insert into public.mall_units(market_id,unit_number)
select m.id,n from public.mall_markets m cross join generate_series(1,20) as n
on conflict(market_id,unit_number) do nothing;
-- Intentionally no public write policies for assignment, approvals or media uploads.
-- These require an authenticated admin backend and private storage bucket.
