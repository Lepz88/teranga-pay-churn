-- =====================================================================
-- 07_segmentation_churn.sql
-- Sprint 2, étape 2.1 : statut de chaque agent au 30/09/2026
-- Actif (<= 14 j) | À risque (15-30 j) | Churn (> 30 j) | Jamais activé
-- =====================================================================

-- MORCEAU A : dernière transaction réussie de chaque agent (800 lignes)
SELECT a.code_agent,
       a.nom_point,
       MAX(t.date_jour)                     AS derniere_transaction,
       DATE '2026-09-30' - MAX(t.date_jour) AS jours_inactivite
FROM analytics.dim_agent a
LEFT JOIN analytics.fact_transactions t
       ON t.id_agent = a.id_agent
      AND t.statut = 'Reussie'
GROUP BY a.code_agent, a.nom_point
ORDER BY a.code_agent;

-- MORCEAU B : répartition des agents par statut
-- Résultat : Actif 548 (68,5 %) | À risque 12 (1,5 %) | Churn 208 (26,0 %) | Jamais activé 32 (4,0 %)
WITH derniere_activite AS (
    SELECT a.id_agent,
           MAX(t.date_jour) AS derniere_transaction
    FROM analytics.dim_agent a
    LEFT JOIN analytics.fact_transactions t
           ON t.id_agent = a.id_agent
          AND t.statut = 'Reussie'
    GROUP BY a.id_agent
),
statuts AS (
    SELECT id_agent,
           CASE
               WHEN derniere_transaction IS NULL                   THEN '4. Jamais activé'
               WHEN DATE '2026-09-30' - derniere_transaction <= 14 THEN '1. Actif'
               WHEN DATE '2026-09-30' - derniere_transaction <= 30 THEN '2. À risque'
               ELSE                                                     '3. Churn'
           END AS statut
    FROM derniere_activite
)
SELECT statut,
       COUNT(*)                                           AS nb_agents,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS pct_agents
FROM statuts
GROUP BY statut
ORDER BY statut;