-- =====================================================================
-- 04_controles_qualite.sql
-- Vérifications après chargement. À relancer à chaque régénération.
-- =====================================================================

-- 1. Comparaison des volumes staging -> analytics
SELECT 'agents' AS table_, (SELECT COUNT(*) FROM staging.agents) AS staging,
       (SELECT COUNT(*) FROM analytics.dim_agent) AS analytics
UNION ALL
SELECT 'clients', (SELECT COUNT(*) FROM staging.clients), (SELECT COUNT(*) FROM analytics.dim_client)
UNION ALL
SELECT 'transactions', (SELECT COUNT(*) FROM staging.transactions), (SELECT COUNT(*) FROM analytics.fact_transactions)
UNION ALL
SELECT 'ruptures', (SELECT COUNT(*) FROM staging.ruptures_liquidite), (SELECT COUNT(*) FROM analytics.fact_ruptures_liquidite);

-- 2. Lignes rejetées par motif (doit expliquer l'écart du contrôle 1)
SELECT motif, COUNT(*) AS nb_lignes
FROM analytics.rejets_transactions
GROUP BY motif
ORDER BY nb_lignes DESC;

-- 3. Régions corrigées : valeurs brutes -> région retenue
SELECT s.region AS region_brute, r.region AS region_corrigee, COUNT(*) AS nb_agents
FROM staging.agents s
JOIN analytics.dim_agent a USING (id_agent)
JOIN analytics.dim_region r USING (id_region)
WHERE s.region <> r.region
GROUP BY 1, 2
ORDER BY 2;

-- 4. Types de transaction après normalisation (aucun NULL attendu)
SELECT type_transaction, COUNT(*) AS nb
FROM analytics.fact_transactions
GROUP BY 1
ORDER BY 2 DESC;

-- 5. Période couverte
SELECT MIN(date_jour) AS premiere_date, MAX(date_jour) AS derniere_date
FROM analytics.fact_transactions;

-- 6. Doublons "contradictoires" : copies d'une même transaction qui diffèrent
--    (traités au nettoyage en gardant la version valide)
SELECT COUNT(*) AS nb_doublons_contradictoires
FROM (SELECT id_transaction
        FROM staging.transactions
       GROUP BY id_transaction
      HAVING COUNT(*) > 1
         AND COUNT(DISTINCT (montant_fcfa, type_transaction)) > 1) d;