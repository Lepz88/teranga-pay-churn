-- =====================================================================
-- 06_exploration.sql
-- Première exploration des données (Sprint 1, étape 4)
-- =====================================================================

-- 1. Aperçu de la table des agents
SELECT *
FROM analytics.dim_agent
LIMIT 10;

-- 2. Nombre d'agents par région
SELECT r.region,
       COUNT(*) AS nb_agents
FROM analytics.dim_agent a
JOIN analytics.dim_region r ON r.id_region = a.id_region
GROUP BY r.region
ORDER BY nb_agents DESC;

-- 3. Volume de transactions réussies par mois
--    -> Pic en mai 2026 (Tabaski)
SELECT d.annee_mois,
       COUNT(*)                         AS nb_transactions,
       ROUND(SUM(t.montant_fcfa) / 1e6) AS volume_millions_fcfa
FROM analytics.fact_transactions t
JOIN analytics.dim_date d ON d.date_jour = t.date_jour
WHERE t.statut = 'Reussie'
GROUP BY d.annee_mois
ORDER BY d.annee_mois;

-- 4. Effet Tabaski : période de la fête vs reste de l'année (moyennes par jour)
--    -> 49,2 M FCFA/jour contre 29,6 (×1,7) ; transferts 36,5 % contre 23,9 %
SELECT CASE WHEN d.evenement = 'Tabaski' THEN 'Période Tabaski'
            ELSE 'Reste de l''année' END                         AS periode,
       ROUND(COUNT(*)::numeric / COUNT(DISTINCT t.date_jour))     AS transactions_par_jour,
       ROUND(SUM(t.montant_fcfa) / COUNT(DISTINCT t.date_jour) / 1e6, 1)
                                                                  AS volume_mfcfa_par_jour,
       ROUND(100.0 * AVG((t.type_transaction = 'Transfert')::int), 1)
                                                                  AS pct_transferts
FROM analytics.fact_transactions t
JOIN analytics.dim_date d ON d.date_jour = t.date_jour
WHERE t.statut = 'Reussie'
GROUP BY 1;