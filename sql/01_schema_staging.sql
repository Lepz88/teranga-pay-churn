-- =====================================================================
-- 01_schema_staging.sql
-- Zone de "staging" : on charge les CSV BRUTS tels quels, sans contrainte,
-- pour pouvoir y repérer et corriger les anomalies avant l'analyse.
-- =====================================================================
DROP SCHEMA IF EXISTS staging CASCADE;
CREATE SCHEMA staging;

CREATE TABLE staging.regions (
    id_region           INT,
    region              TEXT,
    indice_eloignement  NUMERIC
);

CREATE TABLE staging.evenements (
    evenement       TEXT,
    date_evenement  DATE,
    jours_avant     INT,
    jours_apres     INT,
    multiplicateur  NUMERIC,
    region_ciblee   TEXT
);

CREATE TABLE staging.agents (
    id_agent          INT,
    code_agent        TEXT,
    nom_gerant        TEXT,
    nom_point         TEXT,
    genre_gerant      TEXT,
    region            TEXT,
    milieu            TEXT,
    type_point        TEXT,
    date_recrutement  DATE
);

CREATE TABLE staging.clients (
    id_client         INT,
    code_client       TEXT,
    genre             TEXT,
    tranche_age       TEXT,
    region            TEXT,
    date_inscription  DATE
);

CREATE TABLE staging.ruptures_liquidite (
    id_incident    INT,
    id_agent       INT,
    date_incident  DATE,
    type_rupture   TEXT,
    duree_heures   NUMERIC
);

CREATE TABLE staging.transactions (
    id_transaction         BIGINT,
    date_heure             TIMESTAMP,
    id_agent               INT,
    id_client              INT,
    type_transaction       TEXT,
    montant_fcfa           NUMERIC,   -- peut être vide ou négatif (anomalies)
    commission_agent_fcfa  NUMERIC,
    statut                 TEXT
);
