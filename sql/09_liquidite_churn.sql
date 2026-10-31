-- =====================================================================
-- 09_liquidite_churn.sql
-- Sprint 2, étape 2.3 : les ruptures de liquidité font-elles partir les agents ?
-- Hypothèse : zone éloignée -> plus de ruptures de cash -> plus de churn
-- Prérequis : la vue analytics.v_statut_agents (étape 2.2)
-- =====================================================================


-- ---------------------------------------------------------------------
-- PARTIE A : MAILLON 1
-- Les zones éloignées ont-elles plus de ruptures de cash ?
-- On compte les ruptures PAR MOIS D'ACTIVITÉ (et non au total) pour ne pas
-- avantager les agents partis tôt, qui ont eu moins de temps pour en subir.
-- ---------------------------------------------------------------------
WITH exposition AS (
    -- nombre de mois pendant lesquels chaque agent a été actif
    SELECT s.id_agent,
           s.region,
           s.milieu,
           GREATEST((s.derniere_transaction - GREATEST(s.date_recrutement, DATE '2025-10-01')) / 30.4, 1)
               AS mois_actifs
    FROM analytics.v_statut_agents s
    WHERE s.statut <> '4. Jamais activé'
),
ruptures AS (
    -- nombre de ruptures par agent
    SELECT id_agent, COUNT(*) AS nb_ruptures
    FROM analytics.fact_ruptures_liquidite
    GROUP BY id_agent
)
SELECT CASE
           WHEN r.indice_eloignement < 0.30 THEN '1. Proche'
           WHEN r.indice_eloignement < 0.60 THEN '2. Intermédiaire'
           ELSE                                  '3. Éloignée'
       END                                                             AS zone,
       e.milieu,
       COUNT(*)                                                        AS nb_agents,
       ROUND(SUM(COALESCE(ru.nb_ruptures, 0)) / SUM(e.mois_actifs), 2) AS ruptures_par_agent_par_mois
FROM exposition e
JOIN analytics.dim_region r ON r.region = e.region
LEFT JOIN ruptures ru USING (id_agent)
GROUP BY 1, 2
ORDER BY 1, 2;


-- ---------------------------------------------------------------------
-- PARTIE B : MAILLON 2
-- Les agents qui ont beaucoup de ruptures partent-ils plus ?
-- On classe les agents selon leur fréquence de ruptures par mois,
-- puis on calcule le taux de churn de chaque classe.
-- ---------------------------------------------------------------------
WITH exposition AS (
    SELECT s.id_agent,
           s.statut,
           GREATEST((s.derniere_transaction - GREATEST(s.date_recrutement, DATE '2025-10-01')) / 30.4, 1)
               AS mois_actifs
    FROM analytics.v_statut_agents s
    WHERE s.statut <> '4. Jamais activé'
),
ruptures AS (
    SELECT id_agent, COUNT(*) AS nb_ruptures
    FROM analytics.fact_ruptures_liquidite
    GROUP BY id_agent
),
frequence AS (
    SELECT e.id_agent,
           e.statut,
           COALESCE(ru.nb_ruptures, 0) / e.mois_actifs AS ruptures_par_mois
    FROM exposition e
    LEFT JOIN ruptures ru USING (id_agent)
)
SELECT CASE
           WHEN ruptures_par_mois < 0.5 THEN '1. Moins de 0,5 / mois'
           WHEN ruptures_par_mois < 1   THEN '2. 0,5 à 1 / mois'
           WHEN ruptures_par_mois < 2   THEN '3. 1 à 2 / mois'
           ELSE                              '4. 2 ou plus / mois'
       END                                                                      AS frequence_ruptures,
       COUNT(*)                                                                 AS nb_agents,
       SUM(CASE WHEN statut = '3. Churn' THEN 1 ELSE 0 END)                     AS nb_churn,
       ROUND(100.0 * AVG(CASE WHEN statut = '3. Churn' THEN 1 ELSE 0 END), 1)   AS taux_churn_pct
FROM frequence
GROUP BY 1
ORDER BY 1;