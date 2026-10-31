-- =====================================================================
-- 08b_vue_dashboard.sql
-- Sprint 3, étape 4.2 : on enrichit la vue v_statut_agents pour Power BI.
-- Règle : les calculs complexes se font en SQL, Power BI ne fait qu'afficher.
-- Les 9 premières colonnes restent identiques (les requêtes 09 à 12 et les
-- mesures Power BI continuent de fonctionner). On AJOUTE 7 colonnes à la fin :
--   volume_mensuel_fcfa, commissions_mensuelles_fcfa, nb_ruptures,
--   ruptures_par_mois, classe_ruptures, activite_vs_habitude_pct, priorite_appel
-- ⚠️ À relancer après chaque relance de python/02_charger_postgres.py
-- =====================================================================
CREATE OR REPLACE VIEW analytics.v_statut_agents AS
WITH derniere_activite AS (
    -- (identique à l'étape 2.2) dernière transaction réussie de chaque agent
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
),
volumes AS (
    -- (étape 2.6) volume et commissions totaux de chaque agent
    SELECT id_agent,
           SUM(montant_fcfa)          AS volume_total,
           SUM(commission_agent_fcfa) AS commissions_totales
    FROM analytics.fact_transactions
    WHERE statut = 'Reussie'
    GROUP BY id_agent
),
ruptures AS (
    -- (étape 2.3) nombre de ruptures de cash de chaque agent
    SELECT id_agent, COUNT(*) AS nb_ruptures
    FROM analytics.fact_ruptures_liquidite
    GROUP BY id_agent
),
signal AS (
    -- (étape 2.5) activité des 30 derniers jours contre la moyenne des 3 mois précédents
    SELECT t.id_agent,
           ROUND(100.0
                 * COUNT(*) FILTER (WHERE t.date_jour > DATE '2026-09-30' - 30)
                 / NULLIF(COUNT(*) FILTER (WHERE t.date_jour >  DATE '2026-09-30' - 120
                                             AND t.date_jour <= DATE '2026-09-30' - 30) / 3.0, 0))
               AS activite_vs_habitude_pct
    FROM analytics.fact_transactions t
    JOIN analytics.dim_agent a ON a.id_agent = t.id_agent
    WHERE t.statut = 'Reussie'
      AND a.date_recrutement <= DATE '2026-09-30' - 120
    GROUP BY t.id_agent
    HAVING MAX(t.date_jour) > DATE '2026-09-30' - 14
),
base AS (
    SELECT d.*,
           DATE '2026-09-30' - d.derniere_transaction AS jours_inactivite,
           CASE
               WHEN d.derniere_transaction IS NULL                   THEN '4. Jamais activé'
               WHEN DATE '2026-09-30' - d.derniere_transaction <= 14 THEN '1. Actif'
               WHEN DATE '2026-09-30' - d.derniere_transaction <= 30 THEN '2. À risque'
               ELSE                                                       '3. Churn'
           END AS statut,
           -- nombre de mois d'activité observés (au moins 1), comme aux étapes 2.3 et 2.6
           GREATEST((d.derniere_transaction - GREATEST(d.date_recrutement, DATE '2025-10-01')) / 30.4, 1)
               AS mois_actifs
    FROM derniere_activite d
)
SELECT b.id_agent,
       b.code_agent,
       b.region,
       b.milieu,
       b.type_point,
       b.date_recrutement,
       b.derniere_transaction,
       b.jours_inactivite,
       b.statut,
       -- ↓↓↓ nouvelles colonnes ↓↓↓
       ROUND(v.volume_total / b.mois_actifs)                         AS volume_mensuel_fcfa,
       ROUND(v.commissions_totales / b.mois_actifs)                  AS commissions_mensuelles_fcfa,
       CASE WHEN b.statut <> '4. Jamais activé' THEN COALESCE(r.nb_ruptures, 0) END AS nb_ruptures,
       CASE WHEN b.statut <> '4. Jamais activé'
            THEN ROUND(COALESCE(r.nb_ruptures, 0) / b.mois_actifs, 2) END        AS ruptures_par_mois,
       CASE
           WHEN b.statut = '4. Jamais activé'                    THEN NULL
           WHEN COALESCE(r.nb_ruptures, 0) / b.mois_actifs < 0.5 THEN '1. Moins de 0,5'
           WHEN COALESCE(r.nb_ruptures, 0) / b.mois_actifs < 1   THEN '2. De 0,5 à 1'
           WHEN COALESCE(r.nb_ruptures, 0) / b.mois_actifs < 2   THEN '3. De 1 à 2'
           ELSE                                                       '4. 2 ou plus'
       END                                                           AS classe_ruptures,
       s.activite_vs_habitude_pct,
       CASE
           WHEN s.activite_vs_habitude_pct < 50 THEN '1. Appeler cette semaine'
           WHEN s.activite_vs_habitude_pct < 80 THEN '2. Surveiller'
       END                                                           AS priorite_appel
FROM base b
LEFT JOIN volumes  v ON v.id_agent = b.id_agent
LEFT JOIN ruptures r ON r.id_agent = b.id_agent
LEFT JOIN signal   s ON s.id_agent = b.id_agent;

-- Vérification (résultats attendus : Churn 208 agents / 164,2 M ; Appeler 9 ; Surveiller 64)
SELECT statut,
       COUNT(*)                                   AS nb_agents,
       ROUND(SUM(volume_mensuel_fcfa) / 1e6, 1)   AS volume_mensuel_mfcfa,
       COUNT(priorite_appel) FILTER (WHERE priorite_appel = '1. Appeler cette semaine') AS a_appeler,
       COUNT(priorite_appel) FILTER (WHERE priorite_appel = '2. Surveiller')            AS a_surveiller
FROM analytics.v_statut_agents
GROUP BY statut
ORDER BY statut;
