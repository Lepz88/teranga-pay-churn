# Dictionnaire de données : Teranga Pay (données simulées)

Date de référence de l'analyse : **30/09/2026**. Période des transactions : **01/10/2025 → 30/09/2026**.

## Définitions métier

| Statut agent | Règle (jours depuis la dernière transaction réussie) |
|---|---|
| Actif | ≤ 14 jours |
| À risque | 15 à 30 jours |
| Churn | > 30 jours |
| Jamais activé | aucune transaction depuis le recrutement |

## analytics.dim_agent
| Colonne | Type | Description |
|---|---|---|
| id_agent | INT (PK) | Identifiant technique |
| code_agent | VARCHAR | Code métier (TP-AG-00001) |
| nom_gerant / nom_point | VARCHAR | Noms fictifs |
| genre_gerant | CHAR(1) | H / F |
| id_region | INT (FK) | → dim_region |
| milieu | VARCHAR | Urbain / Rural |
| type_point | VARCHAR | Boutique, Kiosque, Multiservices, Station-service |
| date_recrutement | DATE | Entrée dans le réseau |

## analytics.dim_client
id_client (PK), code_client, genre, tranche_age, id_region (FK), date_inscription. Les clients sont **pseudonymisés**.

## analytics.fact_transactions
| Colonne | Description |
|---|---|
| id_transaction (PK) | Identifiant |
| date_heure / date_jour | Horodatage / date (FK dim_date) |
| id_agent, id_client | FK |
| type_transaction | Depot, Retrait, Transfert, Paiement facture, Achat credit |
| montant_fcfa | Montant en FCFA (> 0 après nettoyage) |
| commission_agent_fcfa | Commission **fictive** (0,5 % dépôts/retraits, 0,3 % autres) |
| statut | Reussie / Echouee |

## analytics.fact_ruptures_liquidite
id_incident (PK), id_agent (FK), date_incident (FK), type_rupture (Rupture cash / Rupture e-money), duree_heures.

## analytics.rejets_transactions
Traçabilité du nettoyage : id_transaction, motif (Doublon, Montant manquant, Montant négatif ou nul), ligne_brute (JSON).

## Hypothèses de simulation (à assumer en entretien)
- La répartition des agents par région et la part urbaine sont des **hypothèses**, pas des statistiques officielles.
- Les dates des fêtes (Korité, Tabaski, Tamkharit, Magal, Gamou) sont **approximatives** (calendrier lunaire) et doivent être vérifiées.
- Facteurs qui augmentent la probabilité de churn dans le simulateur : fréquence des ruptures de liquidité, milieu rural, kiosque, faible activité, ancienneté < 6 mois.
- Un agent qui part réduit progressivement son activité sur environ 45 jours.

## Anomalies injectées volontairement
Régions mal orthographiées (« THIES », « St Louis »…), doublons de transactions, montants manquants, montants négatifs, types en majuscules.
