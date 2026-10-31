"""
02_charger_postgres.py
======================
Charge automatiquement les CSV de data/raw dans PostgreSQL :
  1. crée la base (si besoin)
  2. crée le schéma staging et y copie les CSV bruts (COPY = très rapide)
  3. crée le modèle en étoile (schéma analytics) et applique le nettoyage
  4. affiche les contrôles qualité

Utilisation :
    python python/02_charger_postgres.py
Paramètres de connexion (variables d'environnement, sinon valeurs par défaut) :
    PGHOST=localhost  PGPORT=5432  PGUSER=postgres  PGDATABASE=mobile_money_sn
    PGPASSWORD -> demandé au clavier s'il n'est pas défini
"""

import os
import sys
import time
from getpass import getpass
from pathlib import Path

# Force les messages d'erreur de PostgreSQL (côté client) en anglais, sans accents :
# sous Windows, les messages en français font planter psycopg2 (UnicodeDecodeError).
os.environ["LC_MESSAGES"] = "C"
os.environ["LANG"] = "C"
os.environ.setdefault("PGCLIENTENCODING", "UTF8")

import psycopg2
from psycopg2 import sql

# Évite les erreurs d'affichage des emojis dans le terminal Windows
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

RACINE = Path(__file__).resolve().parent.parent
DOSSIER_CSV = RACINE / "data" / "raw"
DOSSIER_SQL = RACINE / "sql"

CONFIG = {
    "host": os.getenv("PGHOST", "localhost"),
    "port": os.getenv("PGPORT", "5432"),
    "user": os.getenv("PGUSER", "postgres"),
    "password": os.getenv("PGPASSWORD") or getpass("Mot de passe PostgreSQL : "),
}
NOM_BASE = os.getenv("PGDATABASE", "mobile_money_sn")

# fichier CSV -> table staging (l'ordre n'a pas d'importance : pas de contraintes en staging)
FICHIERS = {
    "regions.csv": "staging.regions",
    "evenements.csv": "staging.evenements",
    "agents.csv": "staging.agents",
    "clients.csv": "staging.clients",
    "ruptures_liquidite.csv": "staging.ruptures_liquidite",
    "transactions.csv": "staging.transactions",
}


def connecter(dbname):
    """Connexion avec un message d'erreur compréhensible en cas d'échec."""
    try:
        return psycopg2.connect(dbname=dbname, connect_timeout=10, **CONFIG)
    except (psycopg2.OperationalError, UnicodeDecodeError) as e:
        print("\n❌ Connexion à PostgreSQL impossible.")
        if isinstance(e, UnicodeDecodeError):
            print("   (PostgreSQL a renvoyé un message en français que Python n'a pas pu lire.)")
        else:
            print(f"   Détail : {e}")
        print("   Vérifie dans l'ordre :")
        print("   1. Le mot de passe : celui que tu tapes pour te connecter au serveur dans pgAdmin.")
        print(f"   2. Le port (actuellement {CONFIG['port']}) : pgAdmin -> clic droit sur ton serveur")
        print("      -> Properties -> Connection -> Port. S'il est différent, lance par exemple :")
        print("      $env:PGPORT=\"5433\"   puis relance le script (PowerShell).")
        print(f"   3. L'utilisateur (actuellement '{CONFIG['user']}') : même écran, champ Username.")
        print("   4. Que le serveur PostgreSQL est bien démarré (pgAdmin arrive à s'y connecter).")
        sys.exit(1)


def creer_base_si_absente():
    conn = connecter("postgres")
    conn.autocommit = True
    with conn.cursor() as cur:
        cur.execute("SELECT 1 FROM pg_database WHERE datname = %s", (NOM_BASE,))
        if cur.fetchone() is None:
            cur.execute(sql.SQL("CREATE DATABASE {} ENCODING 'UTF8'").format(sql.Identifier(NOM_BASE)))
            print(f"🆕 Base '{NOM_BASE}' créée")
        else:
            print(f"ℹ️  Base '{NOM_BASE}' déjà existante (les schémas seront recréés)")
    conn.close()


def executer_fichier_sql(cur, nom_fichier):
    t0 = time.time()
    cur.execute((DOSSIER_SQL / nom_fichier).read_text(encoding="utf-8"))
    print(f"   ✔ {nom_fichier} ({time.time() - t0:.1f} s)")


def charger_csv(cur):
    for fichier, table in FICHIERS.items():
        chemin = DOSSIER_CSV / fichier
        if not chemin.exists():
            sys.exit(f"❌ Fichier introuvable : {chemin}\n   Lance d'abord python/01_generer_donnees.py")
        t0 = time.time()
        with open(chemin, encoding="utf-8") as f:
            cur.copy_expert(f"COPY {table} FROM STDIN WITH (FORMAT csv, HEADER true)", f)
        print(f"   ✔ {fichier:<24} -> {table:<28} {cur.rowcount:>9,} lignes ({time.time() - t0:.1f} s)")


def afficher_controles(cur):
    print("\n📋 Contrôle des volumes (staging -> analytics)")
    cur.execute((DOSSIER_SQL / "04_controles_qualite.sql").read_text(encoding="utf-8").split(";")[0])
    for table_, brut, propre in cur.fetchall():
        print(f"   {table_:<13} {brut:>9,} -> {propre:>9,}")
    print("\n🧹 Lignes rejetées au nettoyage")
    cur.execute("SELECT motif, COUNT(*) FROM analytics.rejets_transactions GROUP BY 1 ORDER BY 2 DESC")
    for motif, n in cur.fetchall():
        print(f"   {motif:<25} {n:>7,}")


def main():
    creer_base_si_absente()
    conn = connecter(NOM_BASE)
    try:
        with conn, conn.cursor() as cur:   # une seule transaction : tout ou rien
            print("\n1️⃣  Schéma staging")
            executer_fichier_sql(cur, "01_schema_staging.sql")
            print("\n2️⃣  Chargement des CSV bruts")
            charger_csv(cur)
            print("\n3️⃣  Modèle en étoile + nettoyage")
            executer_fichier_sql(cur, "02_schema_analytics.sql")
            executer_fichier_sql(cur, "03_nettoyage_chargement.sql")
            afficher_controles(cur)
    finally:
        conn.close()
    print(f"\n🎉 Terminé ! Ouvre pgAdmin -> base '{NOM_BASE}' -> schéma 'analytics'.")
    print("   Puis lance sql/05_validation_churn.sql dans le Query Tool.")


if __name__ == "__main__":
    main()