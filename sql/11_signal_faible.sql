-- =====================================================================
-- 11_signal_faible.sql
-- Sprint 2, étape 2.5 : peut-on repérer un agent AVANT qu'il ne parte ?
-- Idée : un agent qui va partir RALENTIT d'abord son activité.
-- On compare son activité RÉCENTE (30 derniers jours) à son activité
-- HABITUELLE (moyenne mensuelle des 3 mois précédents).
-- Prérequis : la vue analytics.v_statut_agents (fichier 08)
-- =====================================================================


-- ---------------------------------------------------------------------
-- PARTIE A : comprendre LAG sur un exemple (l'agent TP-AG-00002)
-- LAG(colonne) OVER (PARTITION BY ... ORDER BY ...) va chercher la valeur
-- de la ligne PRÉCÉDENTE, ici le mois précédent du même agent.
-- ---------------------------------------------------------------------
WITH activite_mensuelle AS (
    SELECT id_agent,
           DATE_TRUNC('month', date_jour)::DATE AS mois,
           COUNT(*)                             AS nb_transactions
    FROM analytics.fact_transactions
    WHERE statut = 'Reussie'
    GROUP BY id_agent, DATE_TRUNC('month', date_jour)
)
SELECT a.code_agent,
       TO_CHAR(m.mois, 'YYYY-MM')                                         AS mois,
       m.nb_transactions,
       LAG(m.nb_transactions) OVER (PARTITION BY m.id_agent ORDER BY m.mois) AS mois_precedent,
       m.nb_transactions
         - LAG(m.nb_transactions) OVER (PARTITION BY m.id_agent ORDER BY m.mois) AS evolution
FROM activite_mensuelle m
JOIN analytics.dim_agent a ON a.id_agent = m.id_agent
WHERE a.code_agent = 'TP-AG-00002'
ORDER BY m.mois;


-- ---------------------------------------------------------------------
-- PARTIE B : le signal marche-t-il ? (test sur le passé = "backtest")
-- On se place au 30/06/2026 et on calcule le signal pour les agents
-- encore actifs ce jour-là. Puis on regarde lesquels étaient partis au 30/09/2026.
-- Si le signal est bon, les agents "en forte baisse" doivent partir beaucoup plus.
-- FILTER (WHERE ...) permet de compter seulement les lignes d'une période.
-- ---------------------------------------------------------------------
WITH signal_au_30_juin AS (
    SELECT t.id_agent,
           COUNT(*) FILTER (WHERE t.date_jour >  DATE '2026-06-30' - 30
                              AND t.date_jour <= DATE '2026-06-30')           AS tx_30_derniers_jours,
           COUNT(*) FILTER (WHERE t.date_jour >  DATE '2026-06-30' - 120
                              AND t.date_jour <= DATE '2026-06-30' - 30) / 3.0 AS tx_par_mois_habituel
    FROM analytics.fact_transactions t
    JOIN analytics.dim_agent a ON a.id_agent = t.id_agent
    WHERE t.statut = 'Reussie'
      AND t.date_jour <= DATE '2026-06-30'                 -- on ne regarde PAS le futur
      AND a.date_recrutement <= DATE '2026-06-30' - 120    -- au moins 4 mois d'historique
    GROUP BY t.id_agent
    HAVING MAX(t.date_jour) > DATE '2026-06-30' - 14       -- encore actif au 30/06
)
SELECT CASE
           WHEN tx_30_derniers_jours / NULLIF(tx_par_mois_habituel, 0) < 0.5 THEN '1. Forte baisse (moins de 50 %)'
           WHEN tx_30_derniers_jours / NULLIF(tx_par_mois_habituel, 0) < 0.8 THEN '2. Baisse modérée (50 à 80 %)'
           ELSE                                                                 '3. Stable ou en hausse'
       END                                                                     AS signal_au_30_juin,
       COUNT(*)                                                                AS nb_agents,
       SUM(CASE WHEN v.statut = '3. Churn' THEN 1 ELSE 0 END)                  AS partis_au_30_sept,
       ROUND(100.0 * AVG(CASE WHEN v.statut = '3. Churn' THEN 1 ELSE 0 END), 1) AS taux_depart_pct
FROM signal_au_30_juin s
JOIN analytics.v_statut_agents v ON v.id_agent = s.id_agent
GROUP BY 1
ORDER BY 1;


-- ---------------------------------------------------------------------
-- PARTIE C : la liste d'agents à appeler (au 30/09/2026)
-- Même signal, calculé aujourd'hui, pour les agents encore actifs.
-- On ajoute les ruptures de liquidité des 90 derniers jours pour prioriser.
-- ---------------------------------------------------------------------
WITH signal_actuel AS (
    SELECT t.id_agent,
           COUNT(*) FILTER (WHERE t.date_jour >  DATE '2026-09-30' - 30)              AS tx_30_derniers_jours,
           COUNT(*) FILTER (WHERE t.date_jour >  DATE '2026-09-30' - 120
                              AND t.date_jour <= DATE '2026-09-30' - 30) / 3.0        AS tx_par_mois_habituel
    FROM analytics.fact_transactions t
    JOIN analytics.dim_agent a ON a.id_agent = t.id_agent
    WHERE t.statut = 'Reussie'
      AND a.date_recrutement <= DATE '2026-09-30' - 120
    GROUP BY t.id_agent
    HAVING MAX(t.date_jour) > DATE '2026-09-30' - 14
),
ratio AS (
    -- activité récente en % de l'activité habituelle (arrondie une seule fois ici)
    SELECT id_agent,
           tx_30_derniers_jours,
           ROUND(tx_par_mois_habituel, 1)                                             AS tx_par_mois_habituel,
           ROUND(100.0 * tx_30_derniers_jours / NULLIF(tx_par_mois_habituel, 0))      AS activite_vs_habitude_pct
    FROM signal_actuel
),
ruptures_recentes AS (
    SELECT id_agent, COUNT(*) AS ruptures_90_jours
    FROM analytics.fact_ruptures_liquidite
    WHERE date_incident > DATE '2026-09-30' - 90
    GROUP BY id_agent
)
SELECT v.code_agent,
       v.region,
       v.milieu,
       v.type_point,
       ra.tx_30_derniers_jours,
       ra.tx_par_mois_habituel,
       ra.activite_vs_habitude_pct,
       COALESCE(ru.ruptures_90_jours, 0)                         AS ruptures_90_jours,
       CASE WHEN ra.activite_vs_habitude_pct < 50 THEN '1. Appeler cette semaine'
            ELSE                                        '2. Surveiller'
       END                                                       AS priorite
FROM ratio ra
JOIN analytics.v_statut_agents v ON v.id_agent = ra.id_agent
LEFT JOIN ruptures_recentes ru   ON ru.id_agent = ra.id_agent
WHERE ra.activite_vs_habitude_pct < 80
ORDER BY priorite, ruptures_90_jours DESC, ra.activite_vs_habitude_pct;
