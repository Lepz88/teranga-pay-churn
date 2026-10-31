# 📓 Journal de bord du projet

> Une entrée par étape : ce que j'ai fait, ce qui a bloqué, comment j'ai résolu, ce que j'ai appris.
> 💡 Réécris chaque entrée avec tes propres mots.

---

## Sprint 1 : Données & base (26/10/2026)

### Étape 1 : Environnement
- **Fait :** installation des librairies (pandas, numpy, psycopg2), vérification de PostgreSQL 18 (port 5432, utilisateur postgres).
- **Appris :** _à compléter_

### Étape 2 : Génération des données
- **Fait :** génération de 800 agents, 12 000 clients, 581 007 transactions brutes et 8 775 ruptures de liquidité sur 12 mois (oct. 2025 à sept. 2026).
- **Appris :** les variables `cache_` pilotent la simulation mais ne sont pas exportées, pour que l'analyse parte uniquement des données observables, comme dans une vraie entreprise.

### Étape 3 : Chargement dans PostgreSQL
- **Fait :** chargement automatique (staging → nettoyage → modèle en étoile `analytics`, 7 tables).
- **Problème 1 :** `UnicodeDecodeError` à la connexion.
  - **Cause :** PostgreSQL renvoyait un message d'erreur en français (avec accents) que psycopg2 ne savait pas décoder sous Windows. La vraie erreur était un mot de passe incorrect.
  - **Solution :** gestion de l'erreur dans le script, avec un message clair.
- **Problème 2 :** un écart de quelques transactions entre deux machines (575 955 contre 575 953).
  - **Cause :** 16 doublons avaient des copies contradictoires (une copie avec un montant valide, l'autre sans), et le dédoublonnage en gardait une au hasard.
  - **Solution :** règle déterministe (on garde la version valide) et contrôle qualité ajouté. Résultat stable : **575 962 transactions propres**.
- **Nettoyage :** 2 890 doublons, 1 435 montants manquants et 720 montants négatifs écartés et tracés dans `rejets_transactions`. 22 régions mal saisies corrigées.

### Étape 4 : Exploration
- **Fait :** 4 requêtes d'exploration (`sql/06_exploration.sql`).
- **Insight 1 (Tabaski) :** volume quotidien de 49,2 M FCFA pendant la Tabaski contre 29,6 M FCFA le reste de l'année (×1,7) ; part des transferts de 23,9 % à 36,5 % ; montant moyen de 19 200 à 22 200 FCFA en mai.
- **Appris :** une hypothèse se prouve avec une requête ; il faut comparer à base égale (moyenne par jour) et toujours donner les unités.

---

## Sprint 2 : Analyse du churn (26/10/2026)

### Étape 2.1 : Segmentation des agents
- **Fait :** statut de chaque agent selon sa dernière transaction réussie (`sql/07_segmentation_churn.sql`).
- **Résultat :** 548 actifs (68,5 %), 12 à risque (1,5 %), 208 churn (26,0 %), 32 jamais activés (4,0 %).
- **Appris :** CTE (`WITH`), `CASE WHEN` (l'ordre des conditions compte), première fonction de fenêtre (`SUM(COUNT(*)) OVER ()`). « Jamais activé » et « Churn » sont deux problèmes différents.

### Étape 2.2 : Qui part le plus ?
- **Fait :** vue `analytics.v_statut_agents` + taux de churn par milieu, type de point, région et zone (`sql/08_profil_churn.sql`).
- **Résultat :** rural 39,9 % contre urbain 17,1 % (×2,3). Dakar 12,0 % (le plus faible), Matam 47,1 % (le plus élevé, mais seulement 17 agents). Zone proche 19,7 %, intermédiaire 35,5 %, éloignée 35,9 %.
- **Erreurs corrigées :** j'ai d'abord conclu que « plus il y a d'agents, moins il y a de churn » : c'est faux (corrélation n'est pas causalité, contre-exemple Diourbel/Ziguinchor).
- **Appris :** se méfier des petits effectifs, WHERE vs HAVING, `GROUP BY 1`.

### Étape 2.3 : Liquidité et churn
- **Fait :** test de l'hypothèse « zone éloignée → plus de ruptures → plus de départs » en deux maillons (`sql/09_liquidite_churn.sql`).
- **Résultat :** maillon 1 confirmé (2,47 ruptures/mois en rural éloigné contre 0,40 en urbain proche, ×6,2 ; même près de Dakar, rural ×3,4). Maillon 2 confirmé (churn de 13,3 % à 54,5 %, ×4,1).
- **Erreur corrigée :** j'avais calculé ×6,85 au lieu de ×6,2 : toujours refaire les calculs.
- **Appris :** compter par mois d'activité pour comparer à base égale ; une forte association n'est pas une preuve absolue de cause.

## Sprint 2 (suite) : 27/10/2026

### Étape 2.4 : Cohortes de recrutement
- **Fait :** churn par cohorte trimestrielle (`DATE_TRUNC`), puis comparaison à exposition égale sur les 6 premiers mois (`sql/10_cohortes_recrutement.sql`).
- **Résultat :** pas de tendance claire par cohorte (20 à 39 %, petits groupes). À exposition égale : nouveaux agents 20,7 % contre 13,1 % (×1,6), sur 58 nouveaux agents seulement.
- **Appris :** une hypothèse non confirmée est aussi un résultat ; biais de censure (la cohorte 2026-T3 à 0 % n'a pas eu le temps de partir) ; classer les facteurs par importance (liquidité ×4,1 > ancienneté ×1,6).

### Étape 2.5 : Signal faible
- **Fait :** fonction de fenêtre `LAG`, `COUNT(*) FILTER`, backtest au 30/06/2026, liste d'agents à appeler (`sql/11_signal_faible.sql`).
- **Résultat :** l'agent TP-AG-00002 a perdu 62 % de son activité le mois avant son départ. Backtest : forte baisse → 80 % de départs contre 6,3 % (×12,7, 10 agents) ; baisse modérée ×2,8. Liste au 30/09 : 9 agents à appeler, 64 à surveiller. Le signal repère environ 1 départ sur 3.
- **Erreurs corrigées :** NULL ne veut pas dire 0 (LAG vide car les données commencent en octobre 2025) ; le tri de la liste se lit dans le ORDER BY, pas dans le milieu ou le type de point ; une action doit découler des données (pas « changer le type de point », mais réapprovisionner un agent qui a 16 ruptures).
- **Appris :** variation en % = (nouvelle − ancienne) ÷ ancienne (voir `docs/fiche_calculs.md`).

### Étape 2.6 : Impact en FCFA
- **Fait :** volume mensuel par statut, part liée à la liquidité, volume en jeu (`sql/12_impact_fcfa.sql`).
- **Résultat :** 164,2 M FCFA perdus par mois (20,5 % du volume actuel de 800,1 M FCFA) ; 60 % de cette perte vient d'agents avec au moins 1 rupture par mois ; agents partis deux fois plus petits (0,79 M contre 1,58 M) ; 78,1 M FCFA par mois en jeu chez les 73 agents signalés.
- **Erreurs corrigées :** confusion entre le nombre d'agents et la taille de chaque agent ; pour récupérer le plus d'argent, choisir le groupe qui perd le plus ET dont on connaît la cause.

### ✅ Partie SQL terminée.

---

## Sprint 3 : Graphiques Python (28/10/2026)
- **Échauffement :** révision de l'étape 2.6 (164 M FCFA perdus par mois, 20 % du volume, 60 % liés au cash, agents partis plus petits). 4 réponses justes, avec de petites précisions.
- **Fait :** script `python/03_graphiques.py` qui se connecte à PostgreSQL, relance les requêtes du Sprint 2 et génère 4 graphiques dans `docs/img/` (volume mensuel, churn rural/urbain, churn selon les ruptures, impact en FCFA). Graphiques ajoutés au README.
- **Problèmes rencontrés :** « Python was not found » → utiliser `py` ; image absente → l'ancien script n'avait pas été remplacé.
- **Appris :** une recette en 4 étapes (données, couleurs, graphique, textes) ; un titre qui donne la conclusion ; une seule couleur pour le message ; toujours l'effectif à côté d'un taux ; une gradation convainc plus que deux chiffres.
- **Prochaine étape :** dashboard Power BI.