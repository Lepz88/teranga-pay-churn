-- =====================================================================
-- 03_nettoyage_chargement.sql
-- Passage staging -> analytics avec nettoyage des anomalies.
-- Chaque règle est commentée : c'est ce que tu expliqueras en entretien.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Régions
-- ---------------------------------------------------------------------
INSERT INTO analytics.dim_region (id_region, region, indice_eloignement)
SELECT id_region, region, indice_eloignement
FROM staging.regions;

-- Fonction utilitaire : "clé" de région sans accents, espaces ni casse
-- ex : ' Dakar' -> DAKAR ; 'St Louis' -> SAINTLOUIS ; 'Thies' -> THIES
CREATE OR REPLACE FUNCTION analytics.cle_region(txt TEXT) RETURNS TEXT AS $$
    SELECT regexp_replace(
             regexp_replace(
               translate(upper(trim(txt)), 'ÉÈÊËÀÂÎÏÔÛÙÇ', 'EEEEAAIIOUUC'),
               '^ST[ -]', 'SAINT-'),
             '[^A-Z]', '', 'g');
$$ LANGUAGE SQL IMMUTABLE;

-- ---------------------------------------------------------------------
-- 2. Calendrier (dim_date) généré en SQL avec generate_series
-- ---------------------------------------------------------------------
INSERT INTO analytics.dim_date
SELECT
    d::DATE,
    EXTRACT(YEAR  FROM d)::INT,
    EXTRACT(MONTH FROM d)::INT,
    (ARRAY['Janvier','Février','Mars','Avril','Mai','Juin','Juillet',
           'Août','Septembre','Octobre','Novembre','Décembre'])[EXTRACT(MONTH FROM d)],
    TO_CHAR(d, 'YYYY-MM'),
    EXTRACT(DAY FROM d)::INT,
    EXTRACT(ISODOW FROM d)::INT,
    (ARRAY['Lundi','Mardi','Mercredi','Jeudi','Vendredi','Samedi','Dimanche'])[EXTRACT(ISODOW FROM d)],
    EXTRACT(ISODOW FROM d) IN (6, 7),
    EXTRACT(DAY FROM d) >= 25 OR EXTRACT(DAY FROM d) <= 3,
    (SELECT e.evenement
       FROM staging.evenements e
      WHERE d::DATE BETWEEN e.date_evenement - e.jours_avant AND e.date_evenement + e.jours_apres
      LIMIT 1)
FROM generate_series(DATE '2022-06-01', DATE '2026-12-31', INTERVAL '1 day') AS d;

-- ---------------------------------------------------------------------
-- 3. Agents : correction des régions mal saisies
-- ---------------------------------------------------------------------
INSERT INTO analytics.dim_agent
SELECT a.id_agent, a.code_agent, a.nom_gerant, a.nom_point, a.genre_gerant,
       r.id_region, a.milieu, a.type_point, a.date_recrutement
FROM staging.agents a
JOIN analytics.dim_region r
  ON analytics.cle_region(a.region) = analytics.cle_region(r.region);

-- ---------------------------------------------------------------------
-- 4. Clients
-- ---------------------------------------------------------------------
INSERT INTO analytics.dim_client
SELECT c.id_client, c.code_client, c.genre, c.tranche_age, r.id_region, c.date_inscription
FROM staging.clients c
LEFT JOIN analytics.dim_region r
  ON analytics.cle_region(c.region) = analytics.cle_region(r.region);

-- ---------------------------------------------------------------------
-- 5. Transactions
--   a) on retire les doublons (même id_transaction)
--   b) on normalise le type ('DEPOT' -> 'Depot')
--   c) on écarte les montants manquants ou <= 0 vers la table de rejets
-- ---------------------------------------------------------------------
-- Règle de dédoublonnage DÉTERMINISTE : si les copies d'un doublon diffèrent
-- (ex : une copie avec montant, l'autre sans), on garde la version VALIDE :
--   1) montant renseigné et positif d'abord
--   2) type correctement écrit (pas en majuscules) ensuite
-- Sans cette règle, PostgreSQL choisirait une copie au hasard et les
-- résultats changeraient d'une machine à l'autre.
CREATE TEMP TABLE tx_dedup AS
SELECT DISTINCT ON (id_transaction) *
FROM staging.transactions
ORDER BY id_transaction,
         (montant_fcfa IS NOT NULL AND montant_fcfa > 0) DESC,
         (type_transaction = upper(type_transaction)) ASC;

INSERT INTO analytics.rejets_transactions (id_transaction, motif, ligne_brute)
SELECT id_transaction,
       CASE WHEN montant_fcfa IS NULL THEN 'Montant manquant'
            ELSE 'Montant négatif ou nul' END,
       to_jsonb(t)
FROM tx_dedup t
WHERE montant_fcfa IS NULL OR montant_fcfa <= 0;

-- Doublons : une ligne de rejet par copie en trop d'un même id_transaction
INSERT INTO analytics.rejets_transactions (id_transaction, motif, ligne_brute)
SELECT id_transaction, 'Doublon', NULL
FROM (SELECT id_transaction, COUNT(*) - 1 AS n_extra
        FROM staging.transactions
       GROUP BY id_transaction
      HAVING COUNT(*) > 1) d,
     generate_series(1, d.n_extra);

INSERT INTO analytics.fact_transactions
SELECT t.id_transaction,
       t.date_heure,
       t.date_heure::DATE,
       t.id_agent,
       t.id_client,
       CASE upper(t.type_transaction)
            WHEN 'DEPOT'            THEN 'Depot'
            WHEN 'RETRAIT'          THEN 'Retrait'
            WHEN 'TRANSFERT'        THEN 'Transfert'
            WHEN 'PAIEMENT FACTURE' THEN 'Paiement facture'
            WHEN 'ACHAT CREDIT'     THEN 'Achat credit'
       END,
       t.montant_fcfa::INT,
       t.commission_agent_fcfa::INT,
       t.statut
FROM tx_dedup t
WHERE t.montant_fcfa > 0;

-- ---------------------------------------------------------------------
-- 6. Ruptures de liquidité
-- ---------------------------------------------------------------------
INSERT INTO analytics.fact_ruptures_liquidite
SELECT id_incident, id_agent, date_incident, type_rupture, duree_heures
FROM staging.ruptures_liquidite;

ANALYZE;