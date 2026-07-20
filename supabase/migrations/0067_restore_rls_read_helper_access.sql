-- Restore the internal helper required by authenticated SELECT policies.
-- The helper validates auth.uid() against an active user profile and does not
-- grant table access or authorize writes by itself.

revoke all on function public.current_actor_id() from public;
revoke execute on function public.current_actor_id() from anon;
grant execute on function public.current_actor_id() to authenticated;

comment on function public.current_actor_id() is
  'Internal RLS read helper. Executable only by authenticated API users; returns an active actor id or null.';
