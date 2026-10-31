-- =====================================================================
-- 05_validation_churn.sql  (fin du Sprint 1)
-- Date de référence FIXE : 30/09/2026 (et non CURRENT_DATE) pour que les
-- résultats restent identiques quel que soit le jour d'exécution.
-- =====================================================================

-- ---------------------------------------------------------------------
-- A. Version "Sprint 1" : LEFT JOIN + IS NULL
--    Agents de Dakar sans aucune transaction réussie sur les 30 derniers jours
-- ---------------------------------------------------------------------
SELECT a.code_agent, a.nom_point, a.milieu, a.type_point
FROM analytics.dim_agent a
JOIN analytics.dim_region r ON r.id_region = a.id_region
LEFT JOIN analytics.fact_transactions t
       ON t.id_agent = a.id_agent
      AND t.statut = 'Reussie'
      AND t.date_jour > DATE '2026-09-30' - 30
WHERE r.region = 'Dakar'
  AND t.id_transaction IS NULL
ORDER BY a.code_agent;

-- ---------------------------------------------------------------------
-- B. Segmentation complète des agents (CTE + CASE WHEN)
--    Actif (<= 14 j) | À risque (15-30 j) | Churn (> 30 j) | Jamais activé
-- ---------------------------------------------------------------------
WITH params AS (
    SELECT DATE '2026-09-30' AS date_ref
),
activite AS (
    SELECT a.id_agent,
           r.region,
           a.milieu,
           a.type_point,
           MIN(t.date_jour)    AS premiere_tx,
           MAX(t.date_jour)    AS derniere_tx,
           SUM(t.montant_fcfa) AS volume_total
    FROM analytics.dim_agent a
    JOIN analytics.dim_region r ON r.id_region = a.id_region
    LEFT JOIN analytics.fact_transactions t
           ON t.id_agent = a.id_agent AND t.statut = 'Reussie'
    GROUP BY a.id_agent, r.region, a.milieu, a.type_point
),
segments AS (
    SELECT ac.*,
           CASE
               WHEN derniere_tx IS NULL               THEN '4. Jamais activé'
               WHEN p.date_ref - derniere_tx <= 14    THEN '1. Actif'
               WHEN p.date_ref - derniere_tx <= 30    THEN '2. À risque'
               ELSE                                        '3. Churn'
           END AS statut,
           -- volume mensuel moyen pendant la période d'activité de l'agent
           volume_total / GREATEST((derniere_tx - premiere_tx) / 30.4, 1) AS volume_mensuel_moyen
    FROM activite ac
    CROSS JOIN params p
)
SELECT statut,
       COUNT(*)                                            AS nb_agents,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1)  AS pct_agents,
       ROUND(SUM(volume_mensuel_moyen) / 1e6, 1)           AS volume_mensuel_cumule_mfcfa
FROM segments
GROUP BY statut
ORDER BY statut;

-- ---------------------------------------------------------------------
-- C. Premier indice : taux de churn selon la FRÉQUENCE des ruptures de liquidité
--    ⚠️ On raisonne en ruptures PAR MOIS d'activité, pas en nombre total :
--    un agent parti tôt a mécaniquement moins de ruptures (biais d'exposition).
--    (à approfondir au Sprint 2)
-- ---------------------------------------------------------------------
WITH activite AS (
    SELECT a.id_agent,
           MAX(t.date_jour) AS derniere_tx,
           GREATEST((MAX(t.date_jour) - GREATEST(a.date_recrutement, DATE '2025-10-01')) / 30.4, 1)
               AS mois_actifs
    FROM analytics.dim_agent a
    JOIN analytics.fact_transactions t ON t.id_agent = a.id_agent AND t.statut = 'Reussie'
    GROUP BY a.id_agent, a.date_recrutement
),
ruptures AS (
    SELECT id_agent, COUNT(*) AS nb_ruptures
    FROM analytics.fact_ruptures_liquidite
    GROUP BY id_agent
),
frequence AS (
    SELECT ac.id_agent,
           ac.derniere_tx,
           COALESCE(r.nb_ruptures, 0) / ac.mois_actifs AS ruptures_par_mois
    FROM activite ac
    LEFT JOIN ruptures r USING (id_agent)
)
SELECT CASE
           WHEN ruptures_par_mois < 0.5 THEN '1. Moins de 0,5 / mois'
           WHEN ruptures_par_mois < 1   THEN '2. 0,5 à 1 / mois'
           WHEN ruptures_par_mois < 2   THEN '3. 1 à 2 / mois'
           ELSE                              '4. 2 ou plus / mois'
       END AS frequence_ruptures,
       COUNT(*) AS nb_agents,
       ROUND(100.0 * AVG(CASE WHEN DATE '2026-09-30' - derniere_tx > 30 THEN 1 ELSE 0 END), 1)
           AS taux_churn_pct
FROM frequence
GROUP BY 1
ORDER BY 1;
