-- RÉZO LA KOUR : SQL v2.2 (à lancer seul si phase1_v2_additif.sql v2.1 est déjà installé)
-- Additif et relançable sans risque. Sauvegarde conseillée (export CSV des tables sensibles).

-- ═══════════════════════════════════════════════════════════════
-- v2.2 : rôles des adhérents, liste des fruits éditable, photo des événements
-- (additif : nouvelles tables, une colonne ajoutée à rlk_evenements créée par ce même fichier)
-- ═══════════════════════════════════════════════════════════════

-- Rôles choisis à l'adhésion (plusieurs possibles) + suivi du paiement Yapla
create table if not exists public.rlk_profil_ext (
  user_id uuid primary key references auth.users(id) on delete cascade,
  roles text[] not null default '{}',
  statuts_lus boolean not null default false,
  yapla_declare boolean not null default false,
  yapla_declare_le timestamptz,
  paiement_confirme boolean not null default false,
  paiement_confirme_le timestamptz,
  created_at timestamptz not null default now());
alter table public.rlk_profil_ext enable row level security;
drop policy if exists p_ext_r on public.rlk_profil_ext;
create policy p_ext_r on public.rlk_profil_ext for select to authenticated using (user_id = auth.uid() or public.rlk_est_admin());
drop policy if exists p_ext_i on public.rlk_profil_ext;
create policy p_ext_i on public.rlk_profil_ext for insert to authenticated with check (user_id = auth.uid() and paiement_confirme = false);
drop policy if exists p_ext_u on public.rlk_profil_ext;
create policy p_ext_u on public.rlk_profil_ext for update to authenticated
  using (user_id = auth.uid() or public.rlk_est_admin())
  with check (public.rlk_est_admin() or (user_id = auth.uid() and paiement_confirme = false));

-- Liste des fruits, légumes et aromates : catégorie (valeur en FEY), unité, poids d'une unité
create table if not exists public.rlk_fruits (
  nom text primary key,
  etat text not null default 'mur' check (etat in ('mur','vert','rare','cher','exception','tisane')),
  unite text not null default 'kg' check (unite in ('kg','U','main','botte','bouquet')),
  qte_pour_fey numeric,
  kg_par_unite numeric not null default 1 check (kg_par_unite > 0),
  ordre integer not null default 0,
  maj timestamptz not null default now());
alter table public.rlk_fruits enable row level security;
drop policy if exists p_fruits_r on public.rlk_fruits;
create policy p_fruits_r on public.rlk_fruits for select to anon, authenticated using (true);
drop policy if exists p_fruits_w on public.rlk_fruits;
create policy p_fruits_w on public.rlk_fruits for all to authenticated using (public.rlk_est_admin()) with check (public.rlk_est_admin());

-- Photo des événements (image réduite, stockée en texte)
alter table public.rlk_evenements add column if not exists photo text;
drop function if exists public.rlk_evenements_liste();
create or replace function public.rlk_evenements_liste()
returns table (id uuid, titre text, date_debut timestamptz, date_fin timestamptz, adresse text, quartier text,
               objet text, description text, fiches jsonb, places integer, inscrits bigint, moi_inscrit boolean, photo text)
language sql stable security definer set search_path = public as $$
  select e.id, e.titre, e.date_debut, e.date_fin,
    case when public.rlk_est_admin() or exists (select 1 from public.rlk_inscriptions i where i.event_id = e.id and i.user_id = auth.uid())
         then e.adresse else null end,
    e.quartier, e.objet, e.description, e.fiches, e.places,
    coalesce((select sum(nb_personnes) from public.rlk_inscriptions i where i.event_id = e.id), 0),
    exists (select 1 from public.rlk_inscriptions i where i.event_id = e.id and i.user_id = auth.uid()),
    e.photo
  from public.rlk_evenements e where e.date_debut >= now() - interval '1 day' order by e.date_debut;
$$;
revoke all on function public.rlk_evenements_liste() from public;
grant execute on function public.rlk_evenements_liste() to anon, authenticated;

-- ═══════════════════════════════════════════════════════════════
-- v2.3 : journal permanent des trocs, blog Ladilafé
-- ═══════════════════════════════════════════════════════════════

-- Journal PERMANENT des trocs (jamais remis à zéro) : sert au suivi hebdomadaire et au rapport d'activité
create table if not exists public.rlk_trok (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  declare_par uuid references auth.users(id),
  produit text not null, etat text,
  quantite numeric not null check (quantite > 0), unite text not null default 'kg', kg numeric,
  semaine date not null,                      -- lundi de la semaine de déclaration
  created_at timestamptz not null default now());
create index if not exists rlk_trok_semaine_idx on public.rlk_trok (semaine);
create index if not exists rlk_trok_user_idx on public.rlk_trok (user_id, created_at desc);
alter table public.rlk_trok enable row level security;
drop policy if exists p_trok_r on public.rlk_trok;
create policy p_trok_r on public.rlk_trok for select to authenticated using (user_id = auth.uid() or public.rlk_est_admin());
drop policy if exists p_trok_i on public.rlk_trok;
create policy p_trok_i on public.rlk_trok for insert to authenticated with check (user_id = auth.uid() or public.rlk_est_admin());
drop policy if exists p_trok_d on public.rlk_trok;
create policy p_trok_d on public.rlk_trok for delete to authenticated using (public.rlk_est_admin());

-- Compteur hebdomadaire : semaine du lundi au dimanche, à l'heure de La Réunion
drop function if exists public.rlk_compteurs();
create or replace function public.rlk_compteurs()
returns table (kg_recoltes numeric, kg_dispo_semaine numeric, nb_kour bigint, nb_adherents bigint)
language plpgsql stable security definer set search_path = public as $$
declare r numeric := 0; d numeric := 0; k bigint := 0; a bigint := 0; lundi timestamptz;
begin
  lundi := date_trunc('week', now() at time zone 'Indian/Reunion') at time zone 'Indian/Reunion';
  begin select coalesce(sum(kg_fruits), 0) into r from public.rlk_lots; exception when others then r := 0; end;
  begin
    execute 'select coalesce(sum(quantite), 0) from public.disponibilites where unite = ''kg'' and created_at >= $1' into d using lundi;
  exception when others then d := 0; end;
  begin select count(*) into k from public.rlk_jardins; exception when others then k := 0; end;
  begin select count(*) into a from public.profiles; exception when others then a := 0; end;
  return query select r, d, k, a;
end; $$;
revoke all on function public.rlk_compteurs() from public;
grant execute on function public.rlk_compteurs() to anon, authenticated;

-- LADILAFÉ : blog (catégories, articles composés de blocs)
create table if not exists public.rlk_blog_cats (
  id uuid primary key default gen_random_uuid(),
  nom text not null unique, ordre integer not null default 0,
  created_at timestamptz not null default now());
insert into public.rlk_blog_cats (nom, ordre) values ('Nout zévénman', 1), ('Nout roset', 2), ('Nout Zarboutan', 3)
on conflict (nom) do nothing;
create table if not exists public.rlk_blog_posts (
  id uuid primary key default gen_random_uuid(),
  cat_id uuid references public.rlk_blog_cats(id) on delete set null,
  titre text not null, chapeau text, couverture text,
  blocs jsonb not null default '[]'::jsonb,   -- [{t:'h2'|'h3'|'p'|'img'|'lien'|'liste'|'cit', ...}]
  publie boolean not null default false,
  auteur uuid references auth.users(id),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now());
alter table public.rlk_blog_cats enable row level security;
alter table public.rlk_blog_posts enable row level security;
drop policy if exists p_bcat_r on public.rlk_blog_cats;
create policy p_bcat_r on public.rlk_blog_cats for select to anon, authenticated using (true);
drop policy if exists p_bcat_w on public.rlk_blog_cats;
create policy p_bcat_w on public.rlk_blog_cats for all to authenticated using (public.rlk_est_admin()) with check (public.rlk_est_admin());
drop policy if exists p_bpost_r on public.rlk_blog_posts;
create policy p_bpost_r on public.rlk_blog_posts for select to anon, authenticated using (publie or public.rlk_est_admin());
drop policy if exists p_bpost_w on public.rlk_blog_posts;
create policy p_bpost_w on public.rlk_blog_posts for all to authenticated using (public.rlk_est_admin()) with check (public.rlk_est_admin());

-- v2.3 : l'adhérent modifie ses propres rôles (la politique de mise à jour de rlk_profil_ext le lui interdit après confirmation)
create or replace function public.rlk_mes_roles(p_roles text[])
returns void language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'non connecté'; end if;
  insert into public.rlk_profil_ext (user_id, roles) values (auth.uid(), p_roles)
  on conflict (user_id) do update set roles = excluded.roles;
end $$;
revoke all on function public.rlk_mes_roles(text[]) from public;
grant execute on function public.rlk_mes_roles(text[]) to authenticated;
