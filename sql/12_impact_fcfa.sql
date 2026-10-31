-- =====================================================================
-- 12_impact_fcfa.sql
-- Sprint 2, étape 2.6 : combien le churn coûte-t-il au réseau ?
-- Idée : pour chaque agent, on calcule son VOLUME MENSUEL MOYEN pendant sa
-- période d'activité. Pour un agent parti, c'est le volume que le réseau
-- a perdu chaque mois.
-- Prérequis : la vue analytics.v_statut_agents (fichier 08)
-- =====================================================================


-- ---------------------------------------------------------------------
-- PARTIE A : volume mensuel par statut d'agent
-- ---------------------------------------------------------------------
WITH volume_agent AS (
    SELECT v.id_agent,
           v.statut,
           SUM(t.montant_fcfa)                    AS volume_total,
           SUM(t.commission_agent_fcfa)           AS commissions_totales,
           GREATEST((MAX(t.date_jour) - GREATEST(v.date_recrutement, DATE '2025-10-01')) / 30.4, 1)
                                                  AS mois_actifs
    FROM analytics.v_statut_agents v
    JOIN analytics.fact_transactions t
      ON t.id_agent = v.id_agent AND t.statut = 'Reussie'
    GROUP BY v.id_agent, v.statut, v.date_recrutement
)
SELECT statut,
       COUNT(*)                                                  AS nb_agents,
       ROUND(SUM(volume_total / mois_actifs) / 1e6, 1)           AS volume_mensuel_mfcfa,
       ROUND(AVG(volume_total / mois_actifs) / 1e6, 2)           AS volume_mensuel_moyen_par_agent_mfcfa,
       ROUND(SUM(commissions_totales / mois_actifs) / 1e6, 2)    AS commissions_mensuelles_mfcfa
FROM volume_agent
GROUP BY statut
ORDER BY statut;

-- Point de comparaison : volume total du réseau sur les 30 derniers jours
SELECT ROUND(SUM(montant_fcfa) / 1e6, 1) AS volume_30_derniers_jours_mfcfa
FROM analytics.fact_transactions
WHERE statut = 'Reussie'
  AND date_jour > DATE '2026-09-30' - 30;


-- ---------------------------------------------------------------------
-- PARTIE B : quelle part du volume perdu est liée à la liquidité ?
-- On sépare les agents partis selon leur fréquence de ruptures (seuil : 1 par mois).
-- ---------------------------------------------------------------------
WITH exposition AS (
    SELECT id_agent,
           statut,
           GREATEST((derniere_transaction - GREATEST(date_recrutement, DATE '2025-10-01')) / 30.4, 1)
               AS mois_actifs
    FROM analytics.v_statut_agents
    WHERE statut = '3. Churn'
),
ruptures AS (
    SELECT id_agent, COUNT(*) AS nb_ruptures
    FROM analytics.fact_ruptures_liquidite
    GROUP BY id_agent
),
volume AS (
    SELECT id_agent, SUM(montant_fcfa) AS volume_total
    FROM analytics.fact_transactions
    WHERE statut = 'Reussie'
    GROUP BY id_agent
)
SELECT CASE WHEN COALESCE(r.nb_ruptures, 0) / e.mois_actifs >= 1
            THEN '1. Au moins 1 rupture par mois'
            ELSE '2. Moins de 1 rupture par mois'
       END                                                         AS groupe,
       COUNT(*)                                                    AS nb_agents_partis,
       ROUND(SUM(vo.volume_total / e.mois_actifs) / 1e6, 1)        AS volume_mensuel_perdu_mfcfa,
       ROUND(100.0 * SUM(vo.volume_total / e.mois_actifs)
             / SUM(SUM(vo.volume_total / e.mois_actifs)) OVER (), 1) AS part_du_volume_perdu_pct
FROM exposition e
JOIN volume vo       ON vo.id_agent = e.id_agent
LEFT JOIN ruptures r ON r.id_agent  = e.id_agent
GROUP BY 1
ORDER BY 1;


-- ---------------------------------------------------------------------
-- PARTIE C : volume en jeu chez les agents à appeler / surveiller (étape 2.5)
-- On prend leur volume mensuel HABITUEL (moyenne des 3 mois précédents).
-- ---------------------------------------------------------------------
WITH signal_actuel AS (
    SELECT t.id_agent,
           COUNT(*) FILTER (WHERE t.date_jour >  DATE '2026-09-30' - 30)                     AS tx_30_derniers_jours,
           COUNT(*) FILTER (WHERE t.date_jour >  DATE '2026-09-30' - 120
                              AND t.date_jour <= DATE '2026-09-30' - 30) / 3.0               AS tx_par_mois_habituel,
           SUM(t.montant_fcfa) FILTER (WHERE t.date_jour >  DATE '2026-09-30' - 120
                                         AND t.date_jour <= DATE '2026-09-30' - 30) / 3.0    AS volume_mensuel_habituel
    FROM analytics.fact_transactions t
    JOIN analytics.dim_agent a ON a.id_agent = t.id_agent
    WHERE t.statut = 'Reussie'
      AND a.date_recrutement <= DATE '2026-09-30' - 120
    GROUP BY t.id_agent
    HAVING MAX(t.date_jour) > DATE '2026-09-30' - 14
),
ratio AS (
    SELECT id_agent,
           volume_mensuel_habituel,
           ROUND(100.0 * tx_30_derniers_jours / NULLIF(tx_par_mois_habituel, 0)) AS activite_vs_habitude_pct
    FROM signal_actuel
)
SELECT CASE WHEN activite_vs_habitude_pct < 50 THEN '1. Appeler cette semaine'
            ELSE                                    '2. Surveiller'
       END                                                  AS priorite,
       COUNT(*)                                             AS nb_agents,
       ROUND(SUM(volume_mensuel_habituel) / 1e6, 1)         AS volume_mensuel_en_jeu_mfcfa
FROM ratio
WHERE activite_vs_habitude_pct < 80
GROUP BY 1
ORDER BY 1;
