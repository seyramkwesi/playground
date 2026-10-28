-- Cedi Ledger: team accounts schema for Supabase
-- Run once in the Supabase SQL editor (or via the Supabase connector).
-- Every table is protected by row-level security: people only ever see
-- the businesses (workspaces) they are members of.

-- ============ Tables ============

create table if not exists public.workspaces (
  id          uuid primary key default gen_random_uuid(),
  name        text not null check (char_length(name) between 1 and 120),
  created_by  uuid references auth.users(id) on delete set null default auth.uid(),
  created_at  timestamptz not null default now()
);

create table if not exists public.members (
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  user_id      uuid not null references auth.users(id) on delete cascade,
  role         text not null default 'member' check (role in ('owner','admin','member')),
  email        text,
  display_name text,
  joined_at    timestamptz not null default now(),
  primary key (workspace_id, user_id)
);

create table if not exists public.invites (
  token        text primary key default replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', ''),
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  role         text not null default 'member' check (role in ('admin','member')),
  note         text,
  created_by   uuid references auth.users(id) on delete set null default auth.uid(),
  created_at   timestamptz not null default now(),
  expires_at   timestamptz not null default now() + interval '7 days',
  used_by      uuid references auth.users(id) on delete set null,
  used_at      timestamptz
);

-- Invoices, receipts, expenses and the business profile, stored as JSON
-- documents so the app's data model stays the same as the offline version.
create table if not exists public.records (
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  id           text not null check (char_length(id) between 1 and 80),
  kind         text not null check (kind in ('invoice','receipt','expense','settings')),
  data         jsonb not null,
  updated_at   timestamptz not null default now(),
  updated_by   uuid references auth.users(id) on delete set null default auth.uid(),
  primary key (workspace_id, id)
);
create index if not exists records_ws_kind on public.records (workspace_id, kind);
create index if not exists members_user on public.members (user_id);

-- ============ Helpers (security definer avoids RLS recursion) ============

create or replace function public.is_member(ws uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from members where workspace_id = ws and user_id = auth.uid());
$$;

create or replace function public.member_role(ws uuid)
returns text language sql stable security definer set search_path = public as $$
  select role from members where workspace_id = ws and user_id = auth.uid();
$$;

create or replace function public.is_manager(ws uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce(public.member_role(ws) in ('owner','admin'), false);
$$;

-- Stamp who changed a record and when
create or replace function public.touch_record()
returns trigger language plpgsql as $$
begin
  new.updated_at := now();
  new.updated_by := auth.uid();
  return new;
end $$;
drop trigger if exists records_touch on public.records;
create trigger records_touch before insert or update on public.records
  for each row execute function public.touch_record();

-- ============ Row-level security ============

alter table public.workspaces enable row level security;
alter table public.members    enable row level security;
alter table public.invites    enable row level security;
alter table public.records    enable row level security;

-- workspaces: members read; owners/admins rename; only the owner deletes.
-- New workspaces are created through create_workspace() below.
drop policy if exists ws_select on public.workspaces;
create policy ws_select on public.workspaces for select using (public.is_member(id));
drop policy if exists ws_update on public.workspaces;
create policy ws_update on public.workspaces for update using (public.is_manager(id)) with check (public.is_manager(id));
drop policy if exists ws_delete on public.workspaces;
create policy ws_delete on public.workspaces for delete using (public.member_role(id) = 'owner');

-- members: everyone on the team sees the team list.
-- Owners/admins change roles or remove people (never the owner);
-- anyone except the owner can leave.
drop policy if exists mem_select on public.members;
create policy mem_select on public.members for select using (public.is_member(workspace_id));
drop policy if exists mem_update on public.members;
create policy mem_update on public.members for update
  using (public.is_manager(workspace_id) and role <> 'owner')
  with check (public.is_manager(workspace_id) and role in ('admin','member'));
drop policy if exists mem_delete on public.members;
create policy mem_delete on public.members for delete
  using (role <> 'owner' and (public.is_manager(workspace_id) or user_id = auth.uid()));

-- invites: only owners/admins create, see and revoke invite links.
drop policy if exists inv_select on public.invites;
create policy inv_select on public.invites for select using (public.is_manager(workspace_id));
drop policy if exists inv_insert on public.invites;
create policy inv_insert on public.invites for insert with check (public.is_manager(workspace_id));
drop policy if exists inv_delete on public.invites;
create policy inv_delete on public.invites for delete using (public.is_manager(workspace_id));

-- records: every member reads and adds/edits invoices, receipts and expenses.
-- Only owners/admins delete records or change the business profile.
drop policy if exists rec_select on public.records;
create policy rec_select on public.records for select using (public.is_member(workspace_id));
drop policy if exists rec_insert on public.records;
create policy rec_insert on public.records for insert
  with check (public.is_member(workspace_id) and (kind <> 'settings' or public.is_manager(workspace_id)));
drop policy if exists rec_update on public.records;
create policy rec_update on public.records for update
  using (public.is_member(workspace_id) and (kind <> 'settings' or public.is_manager(workspace_id)))
  with check (public.is_member(workspace_id) and (kind <> 'settings' or public.is_manager(workspace_id)));
drop policy if exists rec_delete on public.records;
create policy rec_delete on public.records for delete using (public.is_manager(workspace_id));

-- ============ Functions the app calls ============

-- Create a business and make the caller its owner.
create or replace function public.create_workspace(p_name text)
returns uuid language plpgsql security definer set search_path = public as $$
declare ws uuid; uid uuid := auth.uid();
begin
  if uid is null then raise exception 'Sign in first'; end if;
  insert into workspaces (name, created_by) values (trim(p_name), uid) returning id into ws;
  insert into members (workspace_id, user_id, role, email, display_name)
  values (ws, uid, 'owner', auth.jwt() ->> 'email',
          coalesce(auth.jwt() -> 'user_metadata' ->> 'full_name', auth.jwt() -> 'user_metadata' ->> 'name', split_part(auth.jwt() ->> 'email', '@', 1)));
  return ws;
end $$;

-- What an invite link is for, shown before someone accepts it.
create or replace function public.invite_info(p_token text)
returns table (workspace_name text, role text, invited_by text, expires_at timestamptz)
language sql stable security definer set search_path = public as $$
  select w.name, i.role, coalesce(m.display_name, m.email), i.expires_at
  from invites i
  join workspaces w on w.id = i.workspace_id
  left join members m on m.workspace_id = i.workspace_id and m.user_id = i.created_by
  where i.token = p_token and i.used_at is null and i.expires_at > now();
$$;

-- Join a business with an invite link (single use, expires after 7 days).
create or replace function public.accept_invite(p_token text)
returns uuid language plpgsql security definer set search_path = public as $$
declare inv invites; uid uuid := auth.uid();
begin
  if uid is null then raise exception 'Sign in first'; end if;
  select * into inv from invites where token = p_token for update;
  if not found then raise exception 'This invite link is not valid'; end if;
  if exists (select 1 from members where workspace_id = inv.workspace_id and user_id = uid) then
    return inv.workspace_id;
  end if;
  if inv.used_at is not null then raise exception 'This invite link has already been used'; end if;
  if inv.expires_at <= now() then raise exception 'This invite link has expired'; end if;
  insert into members (workspace_id, user_id, role, email, display_name)
  values (inv.workspace_id, uid, inv.role, auth.jwt() ->> 'email',
          coalesce(auth.jwt() -> 'user_metadata' ->> 'full_name', auth.jwt() -> 'user_metadata' ->> 'name', split_part(auth.jwt() ->> 'email', '@', 1)));
  update invites set used_by = uid, used_at = now() where token = p_token;
  return inv.workspace_id;
end $$;

-- Hand the business to another member (current owner becomes admin).
create or replace function public.transfer_ownership(p_workspace uuid, p_user uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if public.member_role(p_workspace) <> 'owner' then raise exception 'Only the owner can do this'; end if;
  if not exists (select 1 from members where workspace_id = p_workspace and user_id = p_user) then
    raise exception 'That person is not on this team';
  end if;
  update members set role = 'admin' where workspace_id = p_workspace and user_id = auth.uid();
  update members set role = 'owner' where workspace_id = p_workspace and user_id = p_user;
end $$;

-- Let people update their own display name on every team they belong to.
create or replace function public.set_display_name(p_name text)
returns void language sql security definer set search_path = public as $$
  update members set display_name = nullif(trim(left(p_name, 60)), '') where user_id = auth.uid();
$$;

revoke all on function public.create_workspace(text) from public, anon;
revoke all on function public.accept_invite(text) from public, anon;
revoke all on function public.transfer_ownership(uuid, uuid) from public, anon;
revoke all on function public.invite_info(text) from public, anon;
revoke all on function public.set_display_name(text) from public, anon;
grant execute on function public.create_workspace(text) to authenticated;
grant execute on function public.accept_invite(text) to authenticated;
grant execute on function public.transfer_ownership(uuid, uuid) to authenticated;
grant execute on function public.invite_info(text) to authenticated;
grant execute on function public.set_display_name(text) to authenticated;

-- ============ Live sync ============
do $$ begin
  begin alter publication supabase_realtime add table public.records; exception when duplicate_object then null; end;
  begin alter publication supabase_realtime add table public.members; exception when duplicate_object then null; end;
end $$;
