-- =====================================================================
-- 10_cohortes_recrutement.sql
-- Sprint 2, étape 2.4 : les agents recrutés récemment partent-ils plus vite ?
-- Prérequis : la vue analytics.v_statut_agents (fichier 08)
-- =====================================================================


-- ---------------------------------------------------------------------
-- PARTIE A : churn par COHORTE de recrutement (trimestre)
-- Une cohorte = un groupe d'agents recrutés pendant la même période.
-- DATE_TRUNC('quarter', date) ramène une date au 1er jour de son trimestre
--   ex : 2024-05-17 -> 2024-04-01 (2e trimestre 2024)
-- ---------------------------------------------------------------------
SELECT TO_CHAR(DATE_TRUNC('quarter', date_recrutement), 'YYYY-"T"Q')        AS cohorte,
       COUNT(*)                                                             AS nb_agents_recrutes,
       SUM(CASE WHEN statut = '3. Churn' THEN 1 ELSE 0 END)                 AS nb_churn,
       ROUND(100.0 * AVG(CASE WHEN statut = '3. Churn' THEN 1 ELSE 0 END), 1) AS taux_churn_pct
FROM analytics.v_statut_agents
WHERE statut <> '4. Jamais activé'
GROUP BY 1
ORDER BY 1;


-- ---------------------------------------------------------------------
-- PARTIE B : comparaison À EXPOSITION ÉGALE
-- Problème de la partie A : on n'observe les départs qu'à partir du 01/10/2025,
-- et les cohortes n'ont pas toutes eu le même temps pour partir.
-- Solution : pour chaque agent, on regarde s'il est parti pendant ses
-- 6 PREMIERS MOIS d'observation :
--   - nouveaux agents (recrutés à partir du 01/10/2025) : 6 mois après leur recrutement
--   - agents déjà en place : 6 mois après le 01/10/2025
-- On garde seulement les agents recrutés avant le 01/04/2026 (6 mois de recul minimum).
-- ---------------------------------------------------------------------
WITH observation AS (
    SELECT id_agent,
           statut,
           derniere_transaction,
           CASE WHEN date_recrutement >= DATE '2025-10-01'
                THEN '1. Nouveaux agents (recrutés pendant la période)'
                ELSE '2. Agents déjà en place'
           END                                                    AS groupe,
           GREATEST(date_recrutement, DATE '2025-10-01')          AS debut_observation
    FROM analytics.v_statut_agents
    WHERE statut <> '4. Jamais activé'
      AND date_recrutement < DATE '2026-04-01'
)
SELECT groupe,
       COUNT(*)                                                             AS nb_agents,
       SUM(CASE WHEN statut = '3. Churn'
                 AND derniere_transaction < debut_observation + 183
                THEN 1 ELSE 0 END)                                          AS nb_partis_en_6_mois,
       ROUND(100.0 * AVG(CASE WHEN statut = '3. Churn'
                               AND derniere_transaction < debut_observation + 183
                              THEN 1 ELSE 0 END), 1)                        AS taux_churn_6_mois_pct
FROM observation
GROUP BY groupe
ORDER BY groupe;