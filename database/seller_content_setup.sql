-- World Virtual Mall: seller-owned media and product management
-- Review before running in world-virtual-mall only.
-- Files remain PRIVATE. Never expose secret/service-role keys.
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values ('mall-seller-videos','mall-seller-videos',false,104857600,array['video/mp4','video/webm','video/quicktime'])
on conflict (id) do nothing;
create or replace function public.mall_owns_unit(p_unit uuid,p_seller uuid)
returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.mall_units u join public.mall_sellers s on s.id=u.seller_id
 where u.id=p_unit and u.seller_id=p_seller and s.user_id=(select auth.uid())
 and s.status='approved' and u.status='occupied');
$$;
revoke all on function public.mall_owns_unit(uuid,uuid) from public,anon;
grant execute on function public.mall_owns_unit(uuid,uuid) to authenticated;
drop policy if exists "Owner inserts media" on public.mall_media;
create policy "Owner inserts media" on public.mall_media for insert to authenticated
with check(status='pending' and unit_id is not null and public.mall_owns_unit(unit_id,seller_id)
and (product_id is null and kind in ('storefront','interior') or
product_id is not null and kind='product' and exists(select 1 from public.mall_products p where p.id=product_id and p.seller_id=mall_media.seller_id and p.unit_id=mall_media.unit_id)));
drop policy if exists "Owner deletes media" on public.mall_media;
create policy "Owner deletes media" on public.mall_media for delete to authenticated
using(unit_id is not null and public.mall_owns_unit(unit_id,seller_id));
drop policy if exists "Owner updates products" on public.mall_products;
create policy "Owner updates products" on public.mall_products for update to authenticated
using(public.mall_owns_unit(unit_id,seller_id))
with check(public.mall_owns_unit(unit_id,seller_id) and status='draft');
drop policy if exists "Owner deletes products" on public.mall_products;
create policy "Owner deletes products" on public.mall_products for delete to authenticated
using(public.mall_owns_unit(unit_id,seller_id));
drop policy if exists "Seller uploads own videos" on storage.objects;
create policy "Seller uploads own videos" on storage.objects for insert to authenticated
with check(bucket_id='mall-seller-videos' and (storage.foldername(name))[1]=(select auth.uid())::text
and exists(select 1 from public.mall_units u join public.mall_sellers s on s.id=u.seller_id
where s.user_id=(select auth.uid()) and u.status='occupied' and s.status='approved'));
drop policy if exists "Seller reads own videos" on storage.objects;
create policy "Seller reads own videos" on storage.objects for select to authenticated
using(bucket_id='mall-seller-videos' and (storage.foldername(name))[1]=(select auth.uid())::text);
drop policy if exists "Seller deletes own videos" on storage.objects;
create policy "Seller deletes own videos" on storage.objects for delete to authenticated
using(bucket_id='mall-seller-videos' and (storage.foldername(name))[1]=(select auth.uid())::text);
grant select,insert,delete on public.mall_media to authenticated;
grant select,insert,update,delete on public.mall_products to authenticated;
