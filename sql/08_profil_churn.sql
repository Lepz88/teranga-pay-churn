-- Creation d'une vue
CREATE OR REPLACE VIEW analytics.v_statut_agents AS
WITH derniere_activite AS (
    SELECT a.id_agent,
           a.code_agent,
           r.region,
           a.milieu,
           a.type_point,
           a.date_recrutement,
           MAX(t.date_jour) AS derniere_transaction
    FROM analytics.dim_agent a
    JOIN analytics.dim_region r ON r.id_region = a.id_region
    LEFT JOIN analytics.fact_transactions t
           ON t.id_agent = a.id_agent
          AND t.statut = 'Reussie'
    GROUP BY a.id_agent, a.code_agent, r.region, a.milieu, a.type_point, a.date_recrutement
)
SELECT *,
       DATE '2026-09-30' - derniere_transaction AS jours_inactivite,
       CASE
           WHEN derniere_transaction IS NULL                   THEN '4. Jamais activé'
           WHEN DATE '2026-09-30' - derniere_transaction <= 14 THEN '1. Actif'
           WHEN DATE '2026-09-30' - derniere_transaction <= 30 THEN '2. À risque'
           ELSE                                                     '3. Churn'
       END AS statut
FROM derniere_activite;

SELECT * FROM analytics.v_statut_agents LIMIT 10;

-- le taux de churn par milieu (urbain ou rural)
SELECT milieu,
       COUNT(*)                                                   AS nb_agents_actives,
       SUM(CASE WHEN statut = '3. Churn' THEN 1 ELSE 0 END)       AS nb_churn,
       ROUND(100.0 * AVG(CASE WHEN statut = '3. Churn' THEN 1 ELSE 0 END), 1)
                                                                  AS taux_churn_pct
FROM analytics.v_statut_agents
WHERE statut <> '4. Jamais activé'
GROUP BY milieu
ORDER BY taux_churn_pct DESC;

-- taux de churn par type_point
SELECT type_point,
       COUNT(*)                                                   AS nb_agents_actives,
       SUM(CASE WHEN statut = '3. Churn' THEN 1 ELSE 0 END)       AS nb_churn,
       ROUND(100.0 * AVG(CASE WHEN statut = '3. Churn' THEN 1 ELSE 0 END), 1)
                                                                  AS taux_churn_pct
FROM analytics.v_statut_agents
WHERE statut <> '4. Jamais activé'
GROUP BY type_point
ORDER BY taux_churn_pct DESC;

-- taux de churn par region
SELECT region,
       COUNT(*)                                                   AS nb_agents_actives,
       SUM(CASE WHEN statut = '3. Churn' THEN 1 ELSE 0 END)       AS nb_churn,
       ROUND(100.0 * AVG(CASE WHEN statut = '3. Churn' THEN 1 ELSE 0 END), 1)
                                                                  AS taux_churn_pct
FROM analytics.v_statut_agents
WHERE statut <> '4. Jamais activé'
GROUP BY region
ORDER BY taux_churn_pct DESC;