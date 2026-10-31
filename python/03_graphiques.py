"""
03_graphiques.py
================
Sprint 3 : graphiques des résultats de l'analyse du churn (Teranga Pay, données simulées).

Étape 3.1 : se connecter à PostgreSQL et lire un résultat SQL dans un tableau pandas.
Étape 3.2 : graphique 1, le volume mensuel et le pic de la Tabaski.
Étape 3.3 : graphique 2, le taux de churn rural contre urbain.
Étape 3.4 : graphique 3, le taux de churn selon la fréquence des ruptures de cash.
Étape 3.5 : graphique 4, l'impact du churn en FCFA.
(Les autres graphiques seront ajoutés étape par étape.)

Utilisation :  python python/03_graphiques.py
"""

import os
import sys
from getpass import getpass
from pathlib import Path

# Messages d'erreur PostgreSQL en anglais (évite le UnicodeDecodeError sous Windows)
os.environ["LC_MESSAGES"] = "C"
os.environ["LANG"] = "C"

import matplotlib
matplotlib.use("Agg")            # enregistre les images sans ouvrir de fenêtre
import matplotlib.pyplot as plt
import pandas as pd
import psycopg2

# Affichage des emojis dans le terminal Windows
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

# ---------------------------------------------------------------------------
# 1. PARAMÈTRES
# ---------------------------------------------------------------------------
RACINE = Path(__file__).resolve().parent.parent
DOSSIER_IMAGES = RACINE / "docs" / "img"          # où seront enregistrés les graphiques
DOSSIER_IMAGES.mkdir(parents=True, exist_ok=True)

CONFIG = {
    "host": os.getenv("PGHOST", "localhost"),
    "port": os.getenv("PGPORT", "5432"),
    "user": os.getenv("PGUSER", "postgres"),
    "dbname": os.getenv("PGDATABASE", "mobile_money_sn"),
    "password": os.getenv("PGPASSWORD") or getpass("Mot de passe PostgreSQL : "),
}


# ---------------------------------------------------------------------------
# 2. FONCTION UTILITAIRE : exécuter une requête SQL et récupérer un tableau pandas
# ---------------------------------------------------------------------------
def lire_sql(requete):
    """Exécute une requête SQL et renvoie le résultat sous forme de DataFrame pandas."""
    with psycopg2.connect(**CONFIG) as conn, conn.cursor() as cur:
        cur.execute(requete)
        colonnes = [c[0] for c in cur.description]   # noms des colonnes
        lignes = cur.fetchall()                       # toutes les lignes du résultat
    df = pd.DataFrame(lignes, columns=colonnes)
    # PostgreSQL renvoie les nombres décimaux au format "Decimal" :
    # on les convertit en nombres classiques (float) pour pouvoir tracer les graphiques
    for col in df.columns:
        if len(df) and type(df[col].iloc[0]).__name__ == "Decimal":
            df[col] = df[col].astype(float)
    return df


# ---------------------------------------------------------------------------
# 3. STYLE COMMUN À TOUS LES GRAPHIQUES
# ---------------------------------------------------------------------------
BLEU = "#2E6DB4"        # couleur principale
ORANGE = "#E8833A"      # couleur pour mettre en valeur
GRIS = "#9AA5B1"        # couleur neutre

plt.rcParams.update({
    "font.size": 11,
    "axes.spines.top": False,      # on enlève les bordures inutiles
    "axes.spines.right": False,
    "axes.titleweight": "bold",
    "axes.titlesize": 13,
})


def enregistrer(fig, nom_fichier):
    """Enregistre le graphique en image PNG dans docs/img/."""
    chemin = DOSSIER_IMAGES / nom_fichier
    fig.savefig(chemin, dpi=150, bbox_inches="tight")
    plt.close(fig)
    print(f"   🖼️  {nom_fichier} enregistré")


# ---------------------------------------------------------------------------
# 4. GRAPHIQUE 1 : volume mensuel et pic de la Tabaski (Insight 1)
# ---------------------------------------------------------------------------
def graphique_1_volume_mensuel():
    # a) Les données : même requête que dans sql/06_exploration.sql
    df = lire_sql("""
        SELECT d.annee_mois,
               ROUND(SUM(t.montant_fcfa) / 1e6) AS volume_mfcfa
        FROM analytics.fact_transactions t
        JOIN analytics.dim_date d ON d.date_jour = t.date_jour
        WHERE t.statut = 'Reussie'
        GROUP BY d.annee_mois
        ORDER BY d.annee_mois;
    """)

    # b) Les couleurs : le mois de la Tabaski en orange, les autres en bleu
    couleurs = [ORANGE if mois == "2026-05" else BLEU for mois in df["annee_mois"]]

    # c) Le graphique en barres
    fig, ax = plt.subplots(figsize=(10, 5))
    ax.bar(df["annee_mois"], df["volume_mfcfa"], color=couleurs)

    # d) Les textes : titre, axes, annotation
    ax.set_title("Volume mensuel des transactions : pic en mai 2026 (Tabaski)", pad=15)
    ax.set_ylabel("Volume (millions de FCFA)")
    ax.set_xlabel("")
    ax.tick_params(axis="x", rotation=45)
    pic = df.loc[df["annee_mois"] == "2026-05", "volume_mfcfa"].iloc[0]
    ax.set_ylim(0, pic * 1.15)          # un peu d'espace au-dessus de la plus haute barre
    ax.annotate(f"Tabaski : {pic:,.0f} M FCFA".replace(",", " "),
                xy=("2026-05", pic), xytext=(0, 8), textcoords="offset points",
                ha="center", color=ORANGE, fontweight="bold")
    ax.text(1.0, -0.22, "Données simulées · Teranga Pay", transform=ax.transAxes,
            ha="right", fontsize=8, color=GRIS)

    enregistrer(fig, "01_volume_mensuel_tabaski.png")


# ---------------------------------------------------------------------------
# 5. GRAPHIQUE 2 : taux de churn rural contre urbain (Insight 2)
# ---------------------------------------------------------------------------
def graphique_2_churn_milieu():
    # a) Les données : même requête que dans sql/08_profil_churn.sql
    df = lire_sql("""
        SELECT milieu,
               COUNT(*) AS nb_agents_actives,
               ROUND(100.0 * AVG(CASE WHEN statut = '3. Churn' THEN 1 ELSE 0 END), 1) AS taux_churn_pct
        FROM analytics.v_statut_agents
        WHERE statut <> '4. Jamais activé'
        GROUP BY milieu
        ORDER BY taux_churn_pct DESC;
    """)

    # b) Les couleurs : le milieu le plus touché en orange
    couleurs = [ORANGE if m == "Rural" else BLEU for m in df["milieu"]]

    # c) Le graphique en barres (le nombre d'agents est ajouté sous le nom du milieu)
    etiquettes = [f"{m}\n({n} agents)" for m, n in zip(df["milieu"], df["nb_agents_actives"])]
    fig, ax = plt.subplots(figsize=(6, 5))
    barres = ax.bar(etiquettes, df["taux_churn_pct"], color=couleurs, width=0.55)

    # d) Les textes : la valeur au-dessus de chaque barre
    for barre, taux in zip(barres, df["taux_churn_pct"]):
        x = barre.get_x() + barre.get_width() / 2
        ax.text(x, taux + 1, f"{taux:.1f} %".replace(".", ","), ha="center",
                fontweight="bold", fontsize=13)

    rapport = df["taux_churn_pct"].max() / df["taux_churn_pct"].min()
    ax.set_title(f"En milieu rural, les agents partent {rapport:.1f} fois plus".replace(".", ","), pad=15)
    ax.set_ylabel("Taux de churn (%)")
    ax.set_ylim(0, df["taux_churn_pct"].max() * 1.2)
    ax.text(1.0, -0.18, "Données simulées · Teranga Pay", transform=ax.transAxes,
            ha="right", fontsize=8, color=GRIS)

    enregistrer(fig, "02_churn_rural_urbain.png")


# ---------------------------------------------------------------------------
# 6. GRAPHIQUE 3 : churn selon la fréquence des ruptures de cash (Insight 3)
# ---------------------------------------------------------------------------
def graphique_3_churn_ruptures():
    # a) Les données : même requête que la partie B de sql/09_liquidite_churn.sql
    df = lire_sql("""
        WITH exposition AS (
            SELECT s.id_agent, s.statut,
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
            SELECT e.id_agent, e.statut,
                   COALESCE(r.nb_ruptures, 0) / e.mois_actifs AS ruptures_par_mois
            FROM exposition e
            LEFT JOIN ruptures r USING (id_agent)
        )
        SELECT CASE
                   WHEN ruptures_par_mois < 0.5 THEN '1. Moins de 0,5'
                   WHEN ruptures_par_mois < 1   THEN '2. De 0,5 à 1'
                   WHEN ruptures_par_mois < 2   THEN '3. De 1 à 2'
                   ELSE                              '4. 2 ou plus'
               END                                                                    AS frequence,
               COUNT(*)                                                               AS nb_agents,
               ROUND(100.0 * AVG(CASE WHEN statut = '3. Churn' THEN 1 ELSE 0 END), 1) AS taux_churn_pct
        FROM frequence
        GROUP BY 1
        ORDER BY 1;
    """)

    # On enlève le numéro "1. ", "2. "... qui servait seulement à trier en SQL
    df["frequence"] = df["frequence"].str[3:]

    # b) Les couleurs : la dernière classe (la plus à risque) en orange
    couleurs = [BLEU] * (len(df) - 1) + [ORANGE]

    # c) Le graphique en barres
    etiquettes = [f"{f}\n({n} agents)" for f, n in zip(df["frequence"], df["nb_agents"])]
    fig, ax = plt.subplots(figsize=(8, 5))
    barres = ax.bar(etiquettes, df["taux_churn_pct"], color=couleurs, width=0.6)

    # d) Les textes
    for barre, taux in zip(barres, df["taux_churn_pct"]):
        x = barre.get_x() + barre.get_width() / 2
        ax.text(x, taux + 1, f"{taux:.1f} %".replace(".", ","), ha="center",
                fontweight="bold", fontsize=12)

    rapport = df["taux_churn_pct"].iloc[-1] / df["taux_churn_pct"].iloc[0]
    ax.set_title(f"Plus un agent manque de cash, plus il part : ×{rapport:.1f}".replace(".", ","), pad=15)
    ax.set_xlabel("Ruptures de cash par mois d'activité")
    ax.set_ylabel("Taux de churn (%)")
    ax.set_ylim(0, df["taux_churn_pct"].max() * 1.2)
    ax.text(1.0, -0.25, "Données simulées · Teranga Pay", transform=ax.transAxes,
            ha="right", fontsize=8, color=GRIS)

    enregistrer(fig, "03_churn_ruptures_cash.png")


# ---------------------------------------------------------------------------
# 7. GRAPHIQUE 4 : l'impact du churn en FCFA (Insight 6)
# ---------------------------------------------------------------------------
def graphique_4_impact_fcfa():
    # a) Les données : volume perdu par mois, selon la fréquence des ruptures
    #    (même logique que la partie B de sql/12_impact_fcfa.sql)
    perdu = lire_sql("""
        WITH exposition AS (
            SELECT id_agent,
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
                    THEN 'Manque de cash fréquent'
                    ELSE 'Autres causes'
               END                                                    AS groupe,
               ROUND(SUM(vo.volume_total / e.mois_actifs) / 1e6, 1)   AS volume_mfcfa
        FROM exposition e
        JOIN volume vo       ON vo.id_agent = e.id_agent
        LEFT JOIN ruptures r ON r.id_agent  = e.id_agent
        GROUP BY 1
        ORDER BY 1 DESC;
    """)
    # Volume total du réseau sur les 30 derniers jours (point de comparaison)
    total = lire_sql("""
        SELECT ROUND(SUM(montant_fcfa) / 1e6, 1) AS volume_mfcfa
        FROM analytics.fact_transactions
        WHERE statut = 'Reussie' AND date_jour > DATE '2026-09-30' - 30;
    """)["volume_mfcfa"].iloc[0]

    cash = perdu.loc[perdu["groupe"] == "Manque de cash fréquent", "volume_mfcfa"].iloc[0]
    autres = perdu.loc[perdu["groupe"] == "Autres causes", "volume_mfcfa"].iloc[0]
    total_perdu = cash + autres

    # c) Le graphique : 2 barres horizontales, positionnées à la main
    #    y = 1 (en haut) : ce que le réseau fait aujourd'hui (gris)
    #    y = 0 (en bas)  : ce qu'il a perdu, en 2 morceaux empilés (orange + bleu)
    fig, ax = plt.subplots(figsize=(10, 4))
    ax.barh(1, total, color=GRIS, height=0.6)
    ax.barh(0, cash, color=ORANGE, height=0.6, label="Agents en manque de cash fréquent (1 rupture par mois ou plus)")
    ax.barh(0, autres, left=cash, color=BLEU, height=0.6, label="Agents partis pour d'autres causes")
    # left=cash : le morceau bleu commence là où finit le morceau orange (on empile)

    # d) Les textes
    ax.set_yticks([1, 0], ["Volume actuel\ndu réseau", "Volume perdu\n(agents partis)"])
    ax.text(total / 2, 1, f"{total:.0f} M FCFA par mois", ha="center", va="center",
            color="white", fontweight="bold")
    ax.text(cash / 2, 0, f"{cash:.0f} M", ha="center", va="center", color="white", fontweight="bold")
    ax.text(cash + autres / 2, 0, f"{autres:.0f} M", ha="center", va="center", color="white", fontweight="bold")
    part = f"{100 * total_perdu / total:.1f}".replace(".", ",")
    ax.text(total_perdu + 12, 0, f"= {total_perdu:.0f} M FCFA par mois perdus, soit {part} % du volume actuel",
            va="center", fontsize=10)

    pct_cash = 100 * cash / total_perdu
    ax.set_title(f"Le churn fait perdre {total_perdu:.0f} M FCFA par mois, "
                 f"dont {pct_cash:.0f} % liés au manque de cash", pad=15)
    ax.set_xlabel("Millions de FCFA par mois")
    ax.set_xlim(0, total * 1.05)
    ax.set_ylim(-0.6, 1.5)
    ax.spines["left"].set_visible(False)
    ax.tick_params(axis="y", length=0)
    ax.legend(loc="upper center", bbox_to_anchor=(0.5, -0.28), ncol=2, frameon=False, fontsize=9)
    ax.text(1.0, -0.45, "Données simulées · Teranga Pay", transform=ax.transAxes,
            ha="right", fontsize=8, color=GRIS)

    enregistrer(fig, "04_impact_fcfa.png")


# ---------------------------------------------------------------------------
# 8. PROGRAMME PRINCIPAL : on génère tous les graphiques
# ---------------------------------------------------------------------------
if __name__ == "__main__":
    print("\n📊 Génération des graphiques...")
    graphique_1_volume_mensuel()
    graphique_2_churn_milieu()
    graphique_3_churn_ruptures()
    graphique_4_impact_fcfa()
    print(f"\n✅ Terminé ! Ouvre le dossier : {DOSSIER_IMAGES}")