-- ═══════════════════════════════════════════════════════════════
-- RÉZO LA KOUR, PHASE 1 v2 : SQL ADDITIF (remplace phase1_additif.sql)
-- Ne modifie AUCUNE table existante. Crée uniquement des tables rlk_*.
-- À lancer quand vous le décidez, après une sauvegarde Supabase.
-- Peut être relancé sans risque (create if not exists / or replace).
-- Prérequis : table existante "profiles" avec colonne "role" ('admin').
-- Si vous avez déjà lancé l'ancien phase1_additif.sql : pas de problème,
-- ce fichier complète (colonnes ajoutées avec "add column if not exists").
-- ═══════════════════════════════════════════════════════════════

create or replace function public.rlk_est_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.profiles p where p.id = auth.uid() and p.role = 'admin');
$$;

-- PARAMÈTRES NUMÉRIQUES (valeur du FEY, rendement, quotas...) : lisibles par tous
create table if not exists public.rlk_params (
  cle text primary key, valeur numeric not null, note text);
insert into public.rlk_params (cle, valeur, note) values
  ('fey_eur', 5, 'Valeur d''un FEY en euros (prix unique)'),
  ('unites_par_kg', 4, 'Minimum de FEY par kg de fruits : 1 hôte + 1 équipe + 2 vente'),
  ('quota_mur_kg', 5, 'Quota minimal pour se déplacer : fruits mûrs'),
  ('quota_vert_kg', 10, 'Quota minimal : fruits verts (bananes, papayes, mangues)'),
  ('quota_cafe_kg', 3, 'Quota minimal : café'),
  ('quota_tisane_kg', 1, 'Quota minimal : tisanes et aromates'),
  ('seuil_atelier_fey', 20, 'Nous nous déplaçons à partir de ce nombre de FEY produits'),
  ('panye_fey', 4, 'Prix d''un panyé en FEY'),
  ('abo_mensuel_nb', 4, 'Abonnement mensuel : nombre de panyés'), ('abo_mensuel_eco', 1, 'Abonnement mensuel : économie en FEY'),
  ('abo_trim_nb', 12, 'Abonnement trimestriel : nombre de panyés'), ('abo_trim_eco', 2, 'Abonnement trimestriel : économie en FEY')
on conflict (cle) do nothing;

-- CONFIGURATION TEXTE (identité sur étiquettes : SIRET, adresse, téléphone...)
create table if not exists public.rlk_config (
  cle text primary key, valeur text not null default '');
insert into public.rlk_config (cle, valeur) values
  ('asso_nom','Rézo la Kour'),
  ('asso_adresse','199 chemin des Combavas, 97411 Saint-Paul'),
  ('asso_siret','105 375 034 00011'), ('asso_tel','0692 04 10 62'), ('asso_email','')
on conflict (cle) do update set valeur = excluded.valeur where public.rlk_config.valeur = '';

-- ÉQUIVALENCES SAK Y VO : combien de kg (ou unités) de chaque produit pour 1 FEY
create table if not exists public.rlk_prix (
  produit text primary key,
  qte_pour_fey numeric not null check (qte_pour_fey > 0),
  unite text not null default 'kg',
  maj timestamptz not null default now());

-- JARDINS (quartier uniquement, jamais d'adresse)
create table if not exists public.rlk_jardins (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  commune text not null, quartier text not null,
  surface_m2 integer, productions text,
  visible_carte boolean not null default false,
  created_at timestamptz not null default now(),
  unique (user_id, commune, quartier));
alter table public.rlk_jardins add column if not exists altitude_m integer;
alter table public.rlk_jardins add column if not exists accueil_ateliers boolean not null default false;
alter table public.rlk_jardins add column if not exists espace_ok boolean not null default false;

-- QUESTIONNAIRE (réponses structurées, exploitables en statistiques)
create table if not exists public.rlk_questionnaire (
  user_id uuid primary key references auth.users(id) on delete cascade,
  reponses jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now());

-- LOTS TRANSFORMÉS (traçabilité, numéro de lot, répartition en FEY, stock par canal)
create table if not exists public.rlk_lots (
  id uuid primary key default gen_random_uuid(),
  numero_lot text not null unique,
  date_transfo date not null default current_date,
  produit text not null, fruit text,
  kg_fruits numeric(8,2) not null default 0,
  type_unite text,                 -- libellé de l'unité (ex. Confiture 250 g)
  poids_net text,                  -- ex. 250 g, 0,5 L
  ingredients text, allergenes text, dlc date, dlc_type text default 'DDM',
  qte_produite integer not null check (qte_produite >= 0),
  fey_donateur integer not null default 0,
  fey_equipe integer not null default 0,
  fey_boutik integer not null default 0,
  donateur_id uuid references auth.users(id) on delete set null,
  donateur_libre text,
  participants uuid[] default '{}',
  qte_app integer not null default 0,     -- stock échanges (petite application)
  qte_yapla integer not null default 0,   -- stock boutique en ligne Yapla
  ca_previsionnel numeric(10,2) not null default 0,
  releve jsonb not null default '{}'::jsonb,   -- réception, nettoyage, températures...
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now());

-- PORTEFEUILLE DE FEY (crédits et débits, solde = somme)
create table if not exists public.rlk_fey (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  delta integer not null,
  motif text, lot_id uuid references public.rlk_lots(id) on delete set null,
  created_at timestamptz not null default now());

-- DÉCLARATIONS DE FRUITS (onglet DON) : copie lisible, la table "disponibilites" reste utilisée
-- STOCK PAR CANAL pour les produits de la boutique existante
create table if not exists public.rlk_stock (
  produit_id uuid not null, canal text not null check (canal in ('app','yapla')),
  quantite integer not null default 0, maj timestamptz not null default now(),
  primary key (produit_id, canal));

-- COMMANDES BOUTIK (lignes, mode de paiement, suivi prête / payée sur Yapla)
create table if not exists public.rlk_commandes (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  lignes jsonb not null, total_fey integer not null, total_eur numeric(8,2) not null,
  mode_paiement text not null check (mode_paiement in ('fey','yapla')),
  point_retrait text,
  statut text not null default 'en_attente' check (statut in ('en_attente','prete','payee','retiree','annulee')),
  payee_yapla boolean not null default false,
  created_at timestamptz not null default now());

-- AGENDA : ateliers et réservations
create table if not exists public.rlk_evenements (
  id uuid primary key default gen_random_uuid(),
  titre text not null, date_debut timestamptz not null, date_fin timestamptz,
  adresse text, quartier text, objet text, description text,
  fiches jsonb not null default '[]'::jsonb,   -- [{titre, url}]
  places integer, created_at timestamptz not null default now());
create table if not exists public.rlk_inscriptions (
  event_id uuid not null references public.rlk_evenements(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  nb_personnes integer not null default 1 check (nb_personnes between 1 and 10),
  created_at timestamptz not null default now(),
  primary key (event_id, user_id));

-- MESSAGERIE membre <-> équipe (un fil par membre)
create table if not exists public.rlk_messages (
  id uuid primary key default gen_random_uuid(),
  fil_user_id uuid not null references auth.users(id) on delete cascade,
  de_admin boolean not null default false,
  contenu text not null, lu boolean not null default false,
  created_at timestamptz not null default now());

-- ═══ SÉCURITÉ (RLS) ═══
alter table public.rlk_params enable row level security;
alter table public.rlk_config enable row level security;
alter table public.rlk_prix enable row level security;
alter table public.rlk_jardins enable row level security;
alter table public.rlk_questionnaire enable row level security;
alter table public.rlk_lots enable row level security;
alter table public.rlk_fey enable row level security;
alter table public.rlk_stock enable row level security;
alter table public.rlk_commandes enable row level security;
alter table public.rlk_evenements enable row level security;
alter table public.rlk_inscriptions enable row level security;
alter table public.rlk_messages enable row level security;

-- lecture publique : paramètres, config (hors secrets), équivalences
drop policy if exists p_params_r on public.rlk_params;
create policy p_params_r on public.rlk_params for select to anon, authenticated using (true);
drop policy if exists p_params_w on public.rlk_params;
create policy p_params_w on public.rlk_params for all to authenticated using (public.rlk_est_admin()) with check (public.rlk_est_admin());
drop policy if exists p_config_r on public.rlk_config;
create policy p_config_r on public.rlk_config for select to authenticated using (true);
drop policy if exists p_config_w on public.rlk_config;
create policy p_config_w on public.rlk_config for all to authenticated using (public.rlk_est_admin()) with check (public.rlk_est_admin());
drop policy if exists p_prix_r on public.rlk_prix;
create policy p_prix_r on public.rlk_prix for select to authenticated using (true);
drop policy if exists p_prix_w on public.rlk_prix;
create policy p_prix_w on public.rlk_prix for all to authenticated using (public.rlk_est_admin()) with check (public.rlk_est_admin());

drop policy if exists p_jardins on public.rlk_jardins;
create policy p_jardins on public.rlk_jardins for all to authenticated
  using (user_id = auth.uid() or public.rlk_est_admin()) with check (user_id = auth.uid());
drop policy if exists p_quest on public.rlk_questionnaire;
create policy p_quest on public.rlk_questionnaire for all to authenticated
  using (user_id = auth.uid() or public.rlk_est_admin()) with check (user_id = auth.uid());

drop policy if exists p_lots_r on public.rlk_lots;
create policy p_lots_r on public.rlk_lots for select to authenticated using (public.rlk_est_admin() or donateur_id = auth.uid());
drop policy if exists p_lots_w on public.rlk_lots;
create policy p_lots_w on public.rlk_lots for all to authenticated using (public.rlk_est_admin()) with check (public.rlk_est_admin());

drop policy if exists p_fey_r on public.rlk_fey;
create policy p_fey_r on public.rlk_fey for select to authenticated using (user_id = auth.uid() or public.rlk_est_admin());
drop policy if exists p_fey_ins_admin on public.rlk_fey;
create policy p_fey_ins_admin on public.rlk_fey for insert to authenticated with check (public.rlk_est_admin());
-- un membre peut seulement DÉPENSER (delta négatif) pour lui-même, jamais se créditer
drop policy if exists p_fey_ins_user on public.rlk_fey;
create policy p_fey_ins_user on public.rlk_fey for insert to authenticated with check (user_id = auth.uid() and delta < 0);

drop policy if exists p_stock_r on public.rlk_stock;
create policy p_stock_r on public.rlk_stock for select to authenticated using (true);
drop policy if exists p_stock_w on public.rlk_stock;
create policy p_stock_w on public.rlk_stock for all to authenticated using (public.rlk_est_admin()) with check (public.rlk_est_admin());

drop policy if exists p_cmd_r on public.rlk_commandes;
create policy p_cmd_r on public.rlk_commandes for select to authenticated using (user_id = auth.uid() or public.rlk_est_admin());
drop policy if exists p_cmd_i on public.rlk_commandes;
create policy p_cmd_i on public.rlk_commandes for insert to authenticated with check (user_id = auth.uid() and statut = 'en_attente');
drop policy if exists p_cmd_u on public.rlk_commandes;
create policy p_cmd_u on public.rlk_commandes for update to authenticated using (public.rlk_est_admin()) with check (public.rlk_est_admin());

drop policy if exists p_ev_w on public.rlk_evenements;
create policy p_ev_w on public.rlk_evenements for all to authenticated using (public.rlk_est_admin()) with check (public.rlk_est_admin());
drop policy if exists p_ins_r on public.rlk_inscriptions;
create policy p_ins_r on public.rlk_inscriptions for select to authenticated using (user_id = auth.uid() or public.rlk_est_admin());
drop policy if exists p_ins_i on public.rlk_inscriptions;
create policy p_ins_i on public.rlk_inscriptions for insert to authenticated with check (user_id = auth.uid());
drop policy if exists p_ins_d on public.rlk_inscriptions;
create policy p_ins_d on public.rlk_inscriptions for delete to authenticated using (user_id = auth.uid() or public.rlk_est_admin());

drop policy if exists p_msg_r on public.rlk_messages;
create policy p_msg_r on public.rlk_messages for select to authenticated using (fil_user_id = auth.uid() or public.rlk_est_admin());
drop policy if exists p_msg_i on public.rlk_messages;
create policy p_msg_i on public.rlk_messages for insert to authenticated
  with check ((fil_user_id = auth.uid() and de_admin = false) or (public.rlk_est_admin() and de_admin = true));
drop policy if exists p_msg_u on public.rlk_messages;
create policy p_msg_u on public.rlk_messages for update to authenticated
  using (fil_user_id = auth.uid() or public.rlk_est_admin()) with check (fil_user_id = auth.uid() or public.rlk_est_admin());

-- ═══ FONCTIONS PUBLIQUES (sans données personnelles) ═══
-- Carte : quartier + nombre de jardins consentants
create or replace function public.rlk_carte_publique()
returns table (commune text, quartier text, nb_jardins bigint)
language sql stable security definer set search_path = public as $$
  select commune, quartier, count(*) from public.rlk_jardins where visible_carte = true group by commune, quartier;
$$;
-- Agenda : l'adresse exacte n'est visible que par les inscrits et les admins
create or replace function public.rlk_evenements_liste()
returns table (id uuid, titre text, date_debut timestamptz, date_fin timestamptz, adresse text, quartier text,
               objet text, description text, fiches jsonb, places integer, inscrits bigint, moi_inscrit boolean)
language sql stable security definer set search_path = public as $$
  select e.id, e.titre, e.date_debut, e.date_fin,
    case when public.rlk_est_admin() or exists (select 1 from public.rlk_inscriptions i where i.event_id = e.id and i.user_id = auth.uid())
         then e.adresse else null end,
    e.quartier, e.objet, e.description, e.fiches, e.places,
    coalesce((select sum(nb_personnes) from public.rlk_inscriptions i where i.event_id = e.id), 0),
    exists (select 1 from public.rlk_inscriptions i where i.event_id = e.id and i.user_id = auth.uid())
  from public.rlk_evenements e where e.date_debut >= now() - interval '1 day' order by e.date_debut;
$$;
-- Solde de FEY
create or replace function public.rlk_mon_solde() returns bigint
language sql stable security definer set search_path = public as $$
  select coalesce(sum(delta),0) from public.rlk_fey where user_id = auth.uid();
$$;
revoke all on function public.rlk_carte_publique() from public;
revoke all on function public.rlk_evenements_liste() from public;
grant execute on function public.rlk_carte_publique() to anon, authenticated;
grant execute on function public.rlk_evenements_liste() to anon, authenticated;
grant execute on function public.rlk_mon_solde() to authenticated;


-- ═══════════════════════════════════════════════════════════════
-- v2.1 : règle des parts, articles de la boutique, abonnements, compteurs
-- ═══════════════════════════════════════════════════════════════
-- Quotas abaissés (seulement si vous n'aviez pas déjà changé les valeurs de départ)
update public.rlk_params set valeur = 5 where cle = 'quota_mur_kg' and valeur = 10;
update public.rlk_params set valeur = 10 where cle = 'quota_vert_kg' and valeur = 20;

-- LA RÈGLE DES PARTS : valeur de chaque catégorie de produit
create table if not exists public.rlk_classes (
  code text primary key, libelle text not null,
  credit_par_kg numeric not null, transforme_par_kg numeric not null, ordre integer not null default 0);
insert into public.rlk_classes (code, libelle, credit_par_kg, transforme_par_kg, ordre) values
  ('usuel', 'Usuels : fruits mûrs', 1, 4, 1),
  ('basique', 'Basiques : fruits verts, racines, légumes', 0.5, 1, 2),
  ('rare', 'Rares : champignons, gingembre, safran', 2, 8, 3),
  ('cher', 'Chers : combavas, citron galet', 4, 20, 4),
  ('exception', 'Exception : vanille', 10, 40, 5)
on conflict (code) do nothing;
alter table public.rlk_classes enable row level security;
drop policy if exists p_classes_r on public.rlk_classes;
create policy p_classes_r on public.rlk_classes for select to anon, authenticated using (true);
drop policy if exists p_classes_w on public.rlk_classes;
create policy p_classes_w on public.rlk_classes for all to authenticated using (public.rlk_est_admin()) with check (public.rlk_est_admin());

-- ARTICLES DE LA BOUTIK : prix en FEY, photo, descriptif (la table "produits" existante n'est pas modifiée)
create table if not exists public.rlk_articles (
  produit_id uuid primary key,
  prix_fey numeric not null default 1 check (prix_fey >= 0),
  descriptif text, photo text,
  maj timestamptz not null default now());
alter table public.rlk_articles enable row level security;
drop policy if exists p_art_r on public.rlk_articles;
create policy p_art_r on public.rlk_articles for select to authenticated using (true);
drop policy if exists p_art_w on public.rlk_articles;
create policy p_art_w on public.rlk_articles for all to authenticated using (public.rlk_est_admin()) with check (public.rlk_est_admin());

-- ABONNEMENTS AU PANYÉ
create table if not exists public.rlk_abonnements (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  formule text not null check (formule in ('mensuel','trimestriel')),
  nb_panyes integer not null, total_fey integer not null,
  statut text not null default 'actif' check (statut in ('actif','termine')),
  created_at timestamptz not null default now());
alter table public.rlk_abonnements enable row level security;
drop policy if exists p_abo_r on public.rlk_abonnements;
create policy p_abo_r on public.rlk_abonnements for select to authenticated using (user_id = auth.uid() or public.rlk_est_admin());
drop policy if exists p_abo_i on public.rlk_abonnements;
create policy p_abo_i on public.rlk_abonnements for insert to authenticated with check (user_id = auth.uid() and statut = 'actif');
drop policy if exists p_abo_u on public.rlk_abonnements;
create policy p_abo_u on public.rlk_abonnements for update to authenticated using (public.rlk_est_admin()) with check (public.rlk_est_admin());

-- COMPTEURS D'ACCUEIL : kg récoltés, kg disponibles cette semaine, nombre de jardins (kour), nombre d'adhérents
-- (plpgsql : ne bloque pas l'installation si une colonne de "disponibilites" diffère)
drop function if exists public.rlk_compteurs();
create or replace function public.rlk_compteurs()
returns table (kg_recoltes numeric, kg_dispo_semaine numeric, nb_kour bigint, nb_adherents bigint)
language plpgsql stable security definer set search_path = public as $$
declare r numeric := 0; d numeric := 0; k bigint := 0; a bigint := 0;
begin
  begin select coalesce(sum(kg_fruits), 0) into r from public.rlk_lots; exception when others then r := 0; end;
  begin
    execute 'select coalesce(sum(quantite), 0) from public.disponibilites where unite = ''kg'' and created_at >= date_trunc(''week'', now())' into d;
  exception when others then d := 0; end;
  begin select count(*) into k from public.rlk_jardins; exception when others then k := 0; end;
  begin select count(*) into a from public.profiles; exception when others then a := 0; end;
  return query select r, d, k, a;
end; $$;
revoke all on function public.rlk_compteurs() from public;
grant execute on function public.rlk_compteurs() to anon, authenticated;
