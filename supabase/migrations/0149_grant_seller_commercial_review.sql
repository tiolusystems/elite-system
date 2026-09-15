-- ORD-01 F2B seller flow: grants only the actions required to prepare and
-- confirm the seller's own commercial proposal. Approval remains separate.
insert into public.security_access_profile_permissions(profile_id, action_key)
select profile.id, permission.action_key
  from public.security_access_profiles profile
  join (values
    ('pedidos.price_reference.resolve'),
    ('pedidos.payment_terms.manage'),
    ('pedidos.commercial_context.manage'),
    ('pedidos.practiced_price.record'),
    ('pedidos.commercial_review.preview'),
    ('pedidos.commercial_review.confirm')
  ) permission(action_key) on true
 where profile.profile_key = 'comercial_vendedor'
on conflict (profile_id, action_key) do nothing;

comment on table public.security_access_profile_permissions is
  'IAM-01A materialized least-privilege permissions. Migration 0149 grants F2B seller proposal actions without discount, credit, price-list, admin, PCP, stock, finance, quality or security authority.';
