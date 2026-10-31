"""
01_generer_donnees.py
=====================
Génère un jeu de données SIMULÉ d'un réseau Mobile Money fictif au Sénégal
("Teranga Pay"). Aucune donnée réelle d'opérateur n'est utilisée.

Logique de simulation (à connaître pour l'entretien) :
  1. Chaque agent a des caractéristiques (région, milieu, type de point, ancienneté).
  2. Chaque agent subit des ruptures de liquidité ("float"), plus fréquentes
     dans les régions éloignées et en milieu rural.
  3. La probabilité de churn d'un agent DÉPEND de ces facteurs (modèle logistique).
     -> L'analyse devra retrouver ces facteurs : rien n'est "planté" à la main.
  4. Un agent qui va churner ralentit son activité les semaines précédentes
     (signal faible détectable).
  5. Les volumes suivent une saisonnalité locale (fins de mois, Korité, Tabaski,
     Magal de Touba, Gamou de Tivaouane...).
  6. Quelques anomalies volontaires sont injectées dans les fichiers bruts
     (doublons, régions mal orthographiées, montants manquants...) pour
     l'étape de nettoyage.

Reproductible : graine aléatoire fixe + date de référence fixe.
Utilisation :  python python/01_generer_donnees.py
"""

import sys
from pathlib import Path
import numpy as np
import pandas as pd

# ---------------------------------------------------------------------------
# 0. PARAMÈTRES GLOBAUX
# ---------------------------------------------------------------------------
# Évite les erreurs d'affichage des emojis dans le terminal Windows
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

SEED = 42
rng = np.random.default_rng(SEED)

DATE_DEBUT = pd.Timestamp("2025-10-01")
DATE_REFERENCE = pd.Timestamp("2026-09-30")   # "aujourd'hui" pour l'analyse
NB_AGENTS = 800
NB_CLIENTS = 12_000
TAUX_ANOMALIES = 0.005                         # 0,5 % de lignes "sales"

DOSSIER_SORTIE = Path(__file__).resolve().parent.parent / "data" / "raw"
DOSSIER_SORTIE.mkdir(parents=True, exist_ok=True)

# ---------------------------------------------------------------------------
# 1. RÉFÉRENTIEL DES 14 RÉGIONS
# poids_agents : répartition APPROXIMATIVE du réseau (hypothèse de simulation,
#                pas une statistique officielle)
# part_urbaine : probabilité qu'un agent soit en milieu urbain (hypothèse)
# eloignement  : 0 = proche de Dakar / bien desservi, 1 = très éloigné
#                (influence les ruptures de liquidité)
# ---------------------------------------------------------------------------
REGIONS = pd.DataFrame([
    # region,        poids, part_urbaine, eloignement
    ("Dakar",        0.30, 0.95, 0.00),
    ("Thiès",        0.13, 0.55, 0.15),
    ("Diourbel",     0.10, 0.45, 0.25),
    ("Kaolack",      0.07, 0.45, 0.35),
    ("Saint-Louis",  0.07, 0.50, 0.45),
    ("Louga",        0.06, 0.35, 0.35),
    ("Ziguinchor",   0.05, 0.45, 0.70),
    ("Fatick",       0.04, 0.25, 0.35),
    ("Kaffrine",     0.04, 0.25, 0.50),
    ("Kolda",        0.04, 0.30, 0.80),
    ("Tambacounda",  0.04, 0.30, 0.80),
    ("Matam",        0.03, 0.25, 0.85),
    ("Sédhiou",      0.02, 0.20, 0.85),
    ("Kédougou",     0.01, 0.25, 1.00),
], columns=["region", "poids_agents", "part_urbaine", "eloignement"])
REGIONS.insert(0, "id_region", range(1, len(REGIONS) + 1))

# ---------------------------------------------------------------------------
# 2. ÉVÉNEMENTS SAISONNIERS
# ⚠️ Dates APPROXIMATIVES (calendrier lunaire) : à vérifier avant publication.
# multiplicateur = effet sur le nombre de transactions
# region_ciblee  = effet renforcé dans une région (None = national)
# ---------------------------------------------------------------------------
EVENEMENTS = pd.DataFrame([
    # nom,                      date,         jours_avant, jours_apres, mult, region_ciblee
    ("Noël / Nouvel An",        "2025-12-31", 7, 1, 1.25, None),
    ("Korité",                  "2026-03-20", 5, 1, 1.45, None),
    ("Tabaski",                 "2026-05-27", 10, 2, 1.80, None),
    ("Tamkharit",               "2026-06-26", 3, 1, 1.15, None),
    ("Magal de Touba",          "2026-08-02", 6, 2, 1.30, "Diourbel"),
    ("Gamou de Tivaouane",      "2026-08-25", 4, 1, 1.20, "Thiès"),
    ("Rentrée scolaire",        "2025-10-06", 10, 3, 1.20, None),
], columns=["evenement", "date_evenement", "jours_avant", "jours_apres",
            "multiplicateur", "region_ciblee"])
EVENEMENTS["date_evenement"] = pd.to_datetime(EVENEMENTS["date_evenement"])

# ---------------------------------------------------------------------------
# 3. LISTES DE NOMS (pour les gérants d'agents uniquement ; clients anonymisés)
# ---------------------------------------------------------------------------
PRENOMS_H = ["Amadou", "Moussa", "Ibrahima", "Mamadou", "Cheikh", "Ousmane",
             "Abdoulaye", "Modou", "Serigne", "Babacar", "Aliou", "Pape", "Mor",
             "Lamine", "Souleymane", "Malick", "Assane", "Omar", "Samba", "Djibril"]
PRENOMS_F = ["Fatou", "Aminata", "Awa", "Mariama", "Aïssatou", "Khady", "Ndeye",
             "Coumba", "Astou", "Rokhaya", "Bineta", "Adama", "Seynabou",
             "Dieynaba", "Maimouna", "Sokhna", "Yacine", "Fatoumata",
             "Ramatoulaye", "Marème"]
NOMS = ["Diop", "Ndiaye", "Fall", "Sow", "Ba", "Diallo", "Gueye", "Sarr", "Faye",
        "Seck", "Mbaye", "Cissé", "Diouf", "Kane", "Thiam", "Sy", "Niang", "Ndao",
        "Mbengue", "Camara", "Touré", "Sène", "Diatta", "Badji", "Sané", "Coly",
        "Barry", "Baldé", "Dieng", "Wade", "Lô", "Samb", "Diagne", "Kandé"]
TYPES_POINT = ["Boutique", "Kiosque", "Multiservices", "Station-service"]
PREFIXE_POINT = {"Boutique": "Boutique", "Kiosque": "Kiosque",
                 "Multiservices": "Multiservices", "Station-service": "Station"}


def sigmoide(x):
    return 1 / (1 + np.exp(-x))


# ---------------------------------------------------------------------------
# 4. TABLE DES AGENTS
# ---------------------------------------------------------------------------
def generer_agents():
    idx_region = rng.choice(len(REGIONS), size=NB_AGENTS, p=REGIONS["poids_agents"])
    reg = REGIONS.iloc[idx_region].reset_index(drop=True)

    milieu = np.where(rng.random(NB_AGENTS) < reg["part_urbaine"], "Urbain", "Rural")
    # Les kiosques sont plus fréquents en ville, les boutiques partout
    type_point = np.where(
        milieu == "Urbain",
        rng.choice(TYPES_POINT, NB_AGENTS, p=[0.40, 0.30, 0.20, 0.10]),
        rng.choice(TYPES_POINT, NB_AGENTS, p=[0.60, 0.15, 0.20, 0.05]),
    )
    genre = rng.choice(["H", "F"], NB_AGENTS, p=[0.62, 0.38])
    prenom = np.where(genre == "H", rng.choice(PRENOMS_H, NB_AGENTS),
                      rng.choice(PRENOMS_F, NB_AGENTS))
    nom = rng.choice(NOMS, NB_AGENTS)

    # Recrutement : réseau en croissance -> plus de recrutements récents
    jours_max = (DATE_REFERENCE - pd.Timestamp("2023-01-01")).days - 45
    anciennete = (rng.beta(1.3, 1.0, NB_AGENTS) * jours_max).astype(int) + 45
    date_recrutement = DATE_REFERENCE - pd.to_timedelta(anciennete, unit="D")

    agents = pd.DataFrame({
        "id_agent": range(1, NB_AGENTS + 1),
        "code_agent": [f"TP-AG-{i:05d}" for i in range(1, NB_AGENTS + 1)],
        "nom_gerant": [f"{p} {n}" for p, n in zip(prenom, nom)],
        "nom_point": [f"{PREFIXE_POINT[t]} {n}" for t, n in zip(type_point, nom)],
        "genre_gerant": genre,
        "region": reg["region"],
        "milieu": milieu,
        "type_point": type_point,
        "date_recrutement": date_recrutement.normalize(),
    })

    # --- Variables CACHÉES (non exportées) qui pilotent la simulation --------
    # Activité de base (transactions / jour)
    base = rng.lognormal(mean=0.55, sigma=0.55, size=NB_AGENTS)
    base *= np.where(milieu == "Urbain", 1.35, 0.75)
    base *= pd.Series(type_point).map({"Boutique": 1.0, "Kiosque": 0.85,
                                       "Multiservices": 1.3,
                                       "Station-service": 1.1}).values
    agents["cache_activite"] = base

    # Taux de ruptures de liquidité (par mois)
    agents["cache_taux_ruptures"] = (0.3 + 2.2 * reg["eloignement"].values
                                + np.where(milieu == "Rural", 0.8, 0.0)) \
        * rng.gamma(2.0, 0.5, NB_AGENTS)

    # Jamais activés : ~4 % des agents recrutés n'ont aucune transaction
    agents["cache_jamais_active"] = rng.random(NB_AGENTS) < 0.04
    return agents


# ---------------------------------------------------------------------------
# 5. RUPTURES DE LIQUIDITÉ (incidents de float)
# ---------------------------------------------------------------------------
def generer_ruptures(agents):
    lignes = []
    for a in agents.itertuples():
        if a.cache_jamais_active:
            continue
        debut = max(a.date_recrutement, DATE_DEBUT)
        nb_mois = max((DATE_REFERENCE - debut).days / 30.4, 0)
        n = rng.poisson(a.cache_taux_ruptures * nb_mois)
        if n == 0:
            continue
        offsets = rng.integers(0, max((DATE_REFERENCE - debut).days, 1), n)
        for o in offsets:
            lignes.append((a.id_agent, debut + pd.Timedelta(days=int(o)),
                           rng.choice(["Rupture cash", "Rupture e-money"], p=[0.55, 0.45]),
                           round(float(rng.gamma(2.0, 4.0)), 1)))
    ruptures = pd.DataFrame(lignes, columns=["id_agent", "date_incident",
                                             "type_rupture", "duree_heures"])
    ruptures = ruptures.sort_values(["date_incident", "id_agent"]).reset_index(drop=True)
    ruptures.insert(0, "id_incident", range(1, len(ruptures) + 1))
    return ruptures


# ---------------------------------------------------------------------------
# 6. CHURN DES AGENTS (modèle logistique caché)
# ---------------------------------------------------------------------------
def simuler_churn_agents(agents, ruptures):
    nb_rupt = ruptures.groupby("id_agent").size().reindex(agents["id_agent"], fill_value=0).values
    debut = agents["date_recrutement"].clip(lower=DATE_DEBUT)
    mois_obs = ((DATE_REFERENCE - debut).dt.days / 30.4).clip(lower=1).values
    ruptures_par_mois = nb_rupt / mois_obs
    anciennete_mois = (DATE_REFERENCE - agents["date_recrutement"]).dt.days / 30.4

    score = (-2.4
             + 0.85 * ruptures_par_mois                       # liquidité
             + np.where(agents["milieu"] == "Rural", 0.45, 0)  # milieu
             + np.where(agents["type_point"] == "Kiosque", 0.55, 0)
             - 0.45 * np.log(agents["cache_activite"])              # faible activité = faible commission
             + np.where(anciennete_mois < 6, 0.6, 0)           # agents récents fragiles
             + rng.normal(0, 0.4, len(agents)))
    p_churn = sigmoide(score)
    churne = (rng.random(len(agents)) < p_churn) & ~agents["cache_jamais_active"].values

    # Date de dernière activité des churners : entre recrutement+30j et ref-16j
    # (ceux entre 16 et 30 jours apparaîtront "à risque" : churn pas encore confirmé)
    date_churn = []
    for a, c in zip(agents.itertuples(), churne):
        if not c:
            date_churn.append(pd.NaT)
            continue
        borne_min = max(a.date_recrutement + pd.Timedelta(days=30), DATE_DEBUT + pd.Timedelta(days=20))
        borne_max = DATE_REFERENCE - pd.Timedelta(days=16)
        if borne_min >= borne_max:
            date_churn.append(borne_max)
        else:
            date_churn.append(borne_min + pd.Timedelta(days=int(rng.integers(0, (borne_max - borne_min).days))))
    agents["cache_date_churn"] = pd.to_datetime(date_churn)

    # Une partie des agents encore actifs sont "en train de décrocher" (à risque)
    a_risque = (~churne) & (~agents["cache_jamais_active"].values) & (rng.random(len(agents)) < p_churn * 0.35)
    agents["cache_debut_declin"] = pd.NaT
    agents.loc[a_risque, "cache_debut_declin"] = DATE_REFERENCE - pd.to_timedelta(
        rng.integers(20, 60, a_risque.sum()), unit="D")
    return agents


# ---------------------------------------------------------------------------
# 7. CLIENTS (pseudonymisés : pas de nom, pas de téléphone)
# ---------------------------------------------------------------------------
def generer_clients():
    idx_region = rng.choice(len(REGIONS), size=NB_CLIENTS, p=REGIONS["poids_agents"])
    jours = (DATE_REFERENCE - pd.Timestamp("2022-06-01")).days
    insc = pd.Timestamp("2022-06-01") + pd.to_timedelta(
        (rng.beta(1.6, 1.0, NB_CLIENTS) * jours).astype(int), unit="D")
    clients = pd.DataFrame({
        "id_client": range(1, NB_CLIENTS + 1),
        "code_client": [f"TP-CL-{i:06d}" for i in range(1, NB_CLIENTS + 1)],
        "genre": rng.choice(["H", "F"], NB_CLIENTS, p=[0.55, 0.45]),
        "tranche_age": rng.choice(["18-24", "25-34", "35-44", "45-54", "55+"],
                                  NB_CLIENTS, p=[0.22, 0.34, 0.22, 0.13, 0.09]),
        "region": REGIONS["region"].values[idx_region],
        "date_inscription": insc.normalize(),
    })
    # Variables cachées : fidélité (poids d'usage) et date de fin d'activité
    clients["cache_poids"] = rng.lognormal(0, 1.0, NB_CLIENTS)
    churn_cli = rng.random(NB_CLIENTS) < sigmoide(-1.0 - 0.5 * np.log(clients["cache_poids"]))
    fin = DATE_DEBUT + pd.to_timedelta(rng.integers(30, (DATE_REFERENCE - DATE_DEBUT).days - 31,
                                                    NB_CLIENTS), unit="D")
    clients["cache_date_fin"] = np.where(churn_cli, fin, pd.Timestamp("2099-12-31"))
    clients["cache_date_fin"] = pd.to_datetime(clients["cache_date_fin"])
    return clients


# ---------------------------------------------------------------------------
# 8. TRANSACTIONS
# ---------------------------------------------------------------------------
def facteur_saisonnier(jours, region):
    """Multiplicateur d'activité pour chaque jour (vecteur), selon la région."""
    f = np.ones(len(jours))
    jdm = jours.day.values
    f *= np.where((jdm >= 25) | (jdm <= 3), 1.25, 1.0)     # fins de mois (salaires)
    f *= np.where(jours.dayofweek.values == 4, 1.08, 1.0)   # vendredi
    f *= np.where(jours.dayofweek.values == 6, 0.80, 1.0)   # dimanche
    for e in EVENEMENTS.itertuples():
        if e.region_ciblee is not None and e.region_ciblee != region:
            mult = 1 + (e.multiplicateur - 1) * 0.3          # effet atténué ailleurs
        else:
            mult = e.multiplicateur
        if e.region_ciblee == region:
            mult = 1 + (e.multiplicateur - 1) * 2.0          # effet renforcé localement
        fenetre = (jours >= e.date_evenement - pd.Timedelta(days=e.jours_avant)) & \
                  (jours <= e.date_evenement + pd.Timedelta(days=e.jours_apres))
        f *= np.where(fenetre, mult, 1.0)
    return f


TYPES_TX = ["Depot", "Retrait", "Transfert", "Paiement facture", "Achat credit"]
P_TYPES = [0.30, 0.31, 0.24, 0.08, 0.07]
# (moyenne log, écart-type log) des montants en FCFA par type
PARAM_MONTANT = {"Depot": (9.7, 0.9), "Retrait": (9.6, 0.9), "Transfert": (9.4, 1.0),
                 "Paiement facture": (9.5, 0.6), "Achat credit": (7.2, 0.7)}


def generer_transactions(agents, clients):
    tous_jours = pd.date_range(DATE_DEBUT, DATE_REFERENCE, freq="D")
    saison = {r: facteur_saisonnier(tous_jours, r) for r in REGIONS["region"]}
    morceaux = []

    for a in agents.itertuples():
        if a.cache_jamais_active:
            continue
        fin = a.cache_date_churn if pd.notna(a.cache_date_churn) else DATE_REFERENCE
        masque = (tous_jours >= a.date_recrutement) & (tous_jours <= fin)
        jours = tous_jours[masque]
        if len(jours) == 0:
            continue
        lam = a.cache_activite * saison[a.region][masque]
        # Démarrage progressif les 30 premiers jours après recrutement
        anc = (jours - a.date_recrutement).days.values
        lam = lam * np.clip(0.3 + anc / 40, 0.3, 1.0)
        # Déclin avant churn (signal faible) : -> activité / 4 sur 45 jours
        if pd.notna(a.cache_date_churn):
            reste = (a.cache_date_churn - jours).days.values
            lam = lam * np.where(reste < 45, 0.25 + 0.75 * reste / 45, 1.0)
        if pd.notna(a.cache_debut_declin):
            depuis = (jours - a.cache_debut_declin).days.values
            lam = lam * np.where(depuis > 0, np.clip(1 - depuis / 70, 0.15, 1.0), 1.0)

        n = rng.poisson(lam)
        if n.sum() == 0:
            continue
        dates = np.repeat(jours.values, n)
        morceaux.append(pd.DataFrame({"id_agent": a.id_agent, "region": a.region,
                                      "milieu": a.milieu, "date": dates}))

    tx = pd.concat(morceaux, ignore_index=True)
    N = len(tx)

    # Type de transaction (plus de transferts autour de la Tabaski)
    tx["type_transaction"] = rng.choice(TYPES_TX, N, p=P_TYPES)
    tabaski = EVENEMENTS.loc[EVENEMENTS.evenement == "Tabaski", "date_evenement"].iloc[0]
    proche_tabaski = (tx["date"] >= tabaski - pd.Timedelta(days=10)) & (tx["date"] <= tabaski)
    bascule = proche_tabaski & (rng.random(N) < 0.20)
    tx.loc[bascule, "type_transaction"] = "Transfert"

    # Montants (FCFA, arrondis à 100) ; plus faibles en rural ; plus élevés à la Tabaski
    mu = tx["type_transaction"].map({k: v[0] for k, v in PARAM_MONTANT.items()}).values
    sd = tx["type_transaction"].map({k: v[1] for k, v in PARAM_MONTANT.items()}).values
    mu = mu + np.where(tx["milieu"] == "Rural", -0.25, 0) + np.where(proche_tabaski, 0.35, 0)
    montant = np.exp(rng.normal(mu, sd))
    montant = np.clip(montant, 100, 1_500_000)
    tx["montant_fcfa"] = (np.round(montant / 100) * 100).astype(int)

    # Commission agent FICTIVE : 0,5 % sur dépôts / retraits, 0,3 % sinon
    taux = np.where(tx["type_transaction"].isin(["Depot", "Retrait"]), 0.005, 0.003)
    tx["commission_agent_fcfa"] = np.round(tx["montant_fcfa"] * taux).astype(int)

    # Heure : profil journalier (pics 9h-12h et 17h-20h)
    poids_h = np.array([0, 0, 0, 0, 0, 0, 1, 3, 6, 9, 10, 10, 8, 7, 7, 8, 9, 10, 10, 8, 5, 3, 1, 0], float)
    heure = rng.choice(24, N, p=poids_h / poids_h.sum())
    minute = rng.integers(0, 60, N)
    seconde = rng.integers(0, 60, N)
    tx["date_heure"] = tx["date"] + pd.to_timedelta(heure * 3600 + minute * 60 + seconde, unit="s")

    # Attribution des clients : client de la même région, actif à cette date
    tx["id_client"] = 0
    for region, grp in tx.groupby("region"):
        cl = clients[clients["region"] == region]
        insc, fin, poids = cl["date_inscription"].values, cl["cache_date_fin"].values, cl["cache_poids"].values
        ids = cl["id_client"].values
        for d, sous in grp.groupby("date"):
            actif = (insc <= d.to_datetime64()) & (fin >= d.to_datetime64())
            if not actif.any():
                actif[:] = True
            p = poids * actif
            tx.loc[sous.index, "id_client"] = rng.choice(ids, len(sous), p=p / p.sum())

    tx = tx.sort_values("date_heure").reset_index(drop=True)
    tx.insert(0, "id_transaction", range(1, len(tx) + 1))
    tx["statut"] = np.where(rng.random(len(tx)) < 0.015, "Echouee", "Reussie")
    return tx[["id_transaction", "date_heure", "id_agent", "id_client",
               "type_transaction", "montant_fcfa", "commission_agent_fcfa", "statut"]]


# ---------------------------------------------------------------------------
# 9. ANOMALIES VOLONTAIRES (pour l'étape de nettoyage)
# ---------------------------------------------------------------------------
def injecter_anomalies(agents_export, tx):
    journal = {}
    # a) Régions mal saisies dans la table agents
    variantes = {"Thiès": ["Thies", "THIES"], "Saint-Louis": ["St Louis", "Saint Louis"],
                 "Dakar": [" Dakar", "DAKAR"], "Sédhiou": ["Sedhiou"], "Kédougou": ["Kedougou"]}
    nb = 0
    for i in agents_export.sample(frac=0.06, random_state=SEED).index:
        r = agents_export.at[i, "region"]
        if r in variantes:
            agents_export.at[i, "region"] = rng.choice(variantes[r])
            nb += 1
    journal["agents_region_mal_saisie"] = nb

    n = int(len(tx) * TAUX_ANOMALIES)
    # b) Doublons exacts de transactions
    doublons = tx.sample(n, random_state=SEED)
    # c) Montants manquants
    idx_na = tx.sample(n // 2, random_state=SEED + 1).index
    tx["montant_fcfa"] = tx["montant_fcfa"].astype("Int64")
    tx.loc[idx_na, "montant_fcfa"] = pd.NA
    # d) Montants négatifs ou nuls
    idx_neg = tx.sample(n // 4, random_state=SEED + 2).index
    tx.loc[idx_neg, "montant_fcfa"] = -tx.loc[idx_neg, "montant_fcfa"].fillna(1000)
    # e) Types de transaction mal saisis
    idx_type = tx.sample(n // 4, random_state=SEED + 3).index
    tx.loc[idx_type, "type_transaction"] = tx.loc[idx_type, "type_transaction"].str.upper()
    tx = pd.concat([tx, doublons]).sort_values("date_heure").reset_index(drop=True)

    journal.update({"tx_doublons": len(doublons), "tx_montant_manquant": len(idx_na),
                    "tx_montant_negatif": len(idx_neg),
                    "tx_type_en_majuscules": len(idx_type)})
    return agents_export, tx, journal


# ---------------------------------------------------------------------------
# 10. PROGRAMME PRINCIPAL
# ---------------------------------------------------------------------------
def main():
    print("⏳ Génération des agents...")
    agents = generer_agents()
    ruptures = generer_ruptures(agents)
    agents = simuler_churn_agents(agents, ruptures)
    # Cohérence : un agent parti ne peut plus subir de rupture après son départ
    fin_activite = ruptures["id_agent"].map(agents.set_index("id_agent")["cache_date_churn"])
    ruptures = ruptures[fin_activite.isna() | (ruptures["date_incident"] <= fin_activite)]
    ruptures = ruptures.reset_index(drop=True)
    ruptures["id_incident"] = range(1, len(ruptures) + 1)
    print("⏳ Génération des clients...")
    clients = generer_clients()
    print("⏳ Génération des transactions (peut prendre 1 à 2 minutes)...")
    tx = generer_transactions(agents, clients)

    # On n'exporte JAMAIS les colonnes cachées (préfixe "cache_") :
    # l'analyste doit retrouver le churn à partir des seules données observables.
    agents_export = agents[[c for c in agents.columns if not c.startswith("cache_")]].copy()
    clients_export = clients[[c for c in clients.columns if not c.startswith("cache_")]].copy()
    agents_export, tx, journal = injecter_anomalies(agents_export, tx)

    REGIONS[["id_region", "region", "eloignement"]].rename(
        columns={"eloignement": "indice_eloignement"}).to_csv(
        DOSSIER_SORTIE / "regions.csv", index=False, encoding="utf-8")
    EVENEMENTS.drop(columns="region_ciblee").assign(
        region_ciblee=EVENEMENTS["region_ciblee"].fillna("National")).to_csv(
        DOSSIER_SORTIE / "evenements.csv", index=False, encoding="utf-8")
    agents_export.to_csv(DOSSIER_SORTIE / "agents.csv", index=False, encoding="utf-8")
    clients_export.to_csv(DOSSIER_SORTIE / "clients.csv", index=False, encoding="utf-8")
    ruptures.to_csv(DOSSIER_SORTIE / "ruptures_liquidite.csv", index=False, encoding="utf-8")
    tx.to_csv(DOSSIER_SORTIE / "transactions.csv", index=False, encoding="utf-8",
              date_format="%Y-%m-%d %H:%M:%S")

    print("\n✅ Fichiers générés dans", DOSSIER_SORTIE)
    print(f"   regions.csv            : {len(REGIONS):>9,} lignes")
    print(f"   evenements.csv         : {len(EVENEMENTS):>9,} lignes")
    print(f"   agents.csv             : {len(agents_export):>9,} lignes")
    print(f"   clients.csv            : {len(clients_export):>9,} lignes")
    print(f"   ruptures_liquidite.csv : {len(ruptures):>9,} lignes")
    print(f"   transactions.csv       : {len(tx):>9,} lignes")
    print("\n🧪 Anomalies injectées (à retrouver au nettoyage) :")
    for k, v in journal.items():
        print(f"   {k:<28}: {v:,}")


if __name__ == "__main__":
    main()
