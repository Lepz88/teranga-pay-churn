-- =====================================================================
-- 02_schema_analytics.sql
-- Modèle en étoile utilisé pour l'analyse et Power BI.
--   Dimensions : dim_region, dim_date, dim_agent, dim_client
--   Faits      : fact_transactions, fact_ruptures_liquidite
-- =====================================================================
DROP SCHEMA IF EXISTS analytics CASCADE;
CREATE SCHEMA analytics;

CREATE TABLE analytics.dim_region (
    id_region           INT PRIMARY KEY,
    region              VARCHAR(30) NOT NULL UNIQUE,
    indice_eloignement  NUMERIC(3,2)
);

CREATE TABLE analytics.dim_date (
    date_jour        DATE PRIMARY KEY,
    annee            INT,
    mois             INT,
    nom_mois         VARCHAR(12),
    annee_mois       CHAR(7),          -- ex : 2026-05
    jour_du_mois     INT,
    jour_semaine     INT,              -- 1 = lundi ... 7 = dimanche
    nom_jour         VARCHAR(10),
    est_weekend      BOOLEAN,
    est_fin_de_mois  BOOLEAN,          -- du 25 au 3 (période de salaires)
    evenement        VARCHAR(40)       -- fête / événement couvrant ce jour (sinon NULL)
);

CREATE TABLE analytics.dim_agent (
    id_agent          INT PRIMARY KEY,
    code_agent        VARCHAR(15) NOT NULL UNIQUE,
    nom_gerant        VARCHAR(100),
    nom_point         VARCHAR(100),
    genre_gerant      CHAR(1),
    id_region         INT NOT NULL REFERENCES analytics.dim_region(id_region),
    milieu            VARCHAR(10),
    type_point        VARCHAR(20),
    date_recrutement  DATE
);

CREATE TABLE analytics.dim_client (
    id_client         INT PRIMARY KEY,
    code_client       VARCHAR(15) NOT NULL UNIQUE,
    genre             CHAR(1),
    tranche_age       VARCHAR(5),
    id_region         INT REFERENCES analytics.dim_region(id_region),
    date_inscription  DATE
);

CREATE TABLE analytics.fact_transactions (
    id_transaction         BIGINT PRIMARY KEY,
    date_heure             TIMESTAMP NOT NULL,
    date_jour              DATE NOT NULL REFERENCES analytics.dim_date(date_jour),
    id_agent               INT NOT NULL REFERENCES analytics.dim_agent(id_agent),
    id_client              INT NOT NULL REFERENCES analytics.dim_client(id_client),
    type_transaction       VARCHAR(20) NOT NULL,
    montant_fcfa           INT NOT NULL CHECK (montant_fcfa > 0),
    commission_agent_fcfa  INT,
    statut                 VARCHAR(10)
);

CREATE TABLE analytics.fact_ruptures_liquidite (
    id_incident    INT PRIMARY KEY,
    id_agent       INT NOT NULL REFERENCES analytics.dim_agent(id_agent),
    date_incident  DATE NOT NULL REFERENCES analytics.dim_date(date_jour),
    type_rupture   VARCHAR(20),
    duree_heures   NUMERIC(5,1)
);

-- Table de traçabilité : lignes écartées au nettoyage, avec le motif
CREATE TABLE analytics.rejets_transactions (
    id_transaction  BIGINT,
    motif           VARCHAR(50),
    ligne_brute     JSONB
);

-- Index utiles pour les requêtes de churn (filtre par agent + date)
CREATE INDEX idx_tx_agent_date  ON analytics.fact_transactions (id_agent, date_jour);
CREATE INDEX idx_tx_client_date ON analytics.fact_transactions (id_client, date_jour);
CREATE INDEX idx_rupt_agent     ON analytics.fact_ruptures_liquidite (id_agent, date_incident);
