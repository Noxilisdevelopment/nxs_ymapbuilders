# 🛠️ nxs_ymapbuilder (v1.2)

Script FiveM Standalone permettant de poser des props directement en jeu, de les manipuler avec un **Gizmo 3D professionnel** (translation, rotation, duplication instantanée, snapping et viseur), de gérer des **projets sauvegardés**, et d'exporter un fichier **YMAP XML** pour **CodeWalker / OpenIV** ainsi qu'une **ressource FiveM prête à l'emploi** !

---

## 🚀 Fonctionnalités Majeures

1. **Manipulation Gizmo 3D & Caméra Libre** :
   - Caméra placée directement devant le prop (personnage automatiquement masqué pour zéro gêne visuelle).
   - Déplacement libre de la caméra (`ZQSD`, `A/E` pour monter/descendre, Clic Droit pour pivoter).
   - Plaqué automatiquement au sol dès le spawn (`SnapEntityToGroundProperly` avec boîte englobante et raycast).

2. **⚡ Duplication Rapide (MAJ Gauche)** :
   - Maintiens **MAJ Gauche** et tire une flèche : le prop d'origine reste en place et tu tires directement le clone !
   - Ou en plein déplacement, appuie sur **MAJ Gauche** pour déposer un clone à cet endroit précis.

3. **🎯 Prop Picker (Sélection au Viseur - Touche `[F]`)** :
   - Vise n'importe quel prop dans le monde avec ta caméra et appuie sur **`[F]`** : le Gizmo 3D s'attache immédiatement dessus sans avoir à le chercher dans la liste !

4. **📐 Snapping Grille & Angles (Touche `[X]`)** :
   - Aligne parfaitement tes constructions : bloque les déplacements par paliers de `0.5m` et les rotations par crans nets de `45°` (configurables dans `config.lua`).

5. **↩️ Historique Annuler / Rétablir (Undo / Redo)** :
   - Raccourcis **`Ctrl + Z`** (Annuler) et **`Ctrl + Y`** (Rétablir), ainsi que deux boutons dédiés dans le header de l'UI.
   - Fonctionne sur la création, la duplication, le déplacement et la suppression de props.

6. **💾 Gestionnaire de Projets (Onglet "Projets")** :
   - Retrouve tous tes mappings sauvegardés dans l'interface.
   - Bouton **"Charger le projet"** : fait réapparaître instantanément tous les props du projet pour continuer à mapper là où tu t'étais arrêté !
   - Bouton **"Supprimer"** pour nettoyer tes anciennes sauvegardes.

7. **📦 Export Complet & Ressource FiveM Autonome** :
   - Calcul exact des **Quaternions inversés Rage Engine** $(-qx, -qy, -qz, qw)$ garantissant une orientation 100% identique dans **CodeWalker**.
   - Calcul automatique des **Bounding Boxes** et de la portée de streaming (`<streamingExtents>` et `<entitiesExtents>`).
   - Génère dans `nxs_ymapbuilder/exports/` :
     - `<nom>.ymap.xml` (prêt pour OpenIV / CodeWalker).
     - `<nom>_client.lua` (script de spawn direct).
     - `<nom>_save.json` (sauvegarde de projet réutilisable).
     - `<nom>_pack/` : dossier d'une ressource FiveM complète et autonome avec son `fxmanifest.lua` et son `client.lua`, prête à glisser dans votre dossier `resources/` !

---

## 🎮 Raccourcis en Mode Gizmo 3D

| Touche | Action |
|---|---|
| **`[ESPACE]`** | **Basculer en Mode Caméra Libre (Freecam)** |
| **Clic Gauche** | Manipuler les flèches / cercles Gizmo |
| **`[ALT + Déplacer]`** | **Dupliquer le prop instantanément** |
| **`[F]`** | **Prop Picker** (Cibler un prop au viseur) |
| **`[X]`** | **Basculer le Snapping Grille / Angles** |
| **`[W]`** | Mode Translation (Flèches X, Y, Z) |
| **`[R]`** | Mode Rotation (Cercles Roll, Pitch, Yaw) |
| **`[Q]`** | Alterner Espace (Local / Monde) |
| **`[G]`** | **Plaquer le prop au sol** |
| **`[ZQSD]`** | Déplacer / Voler avec la caméra |
| **`[A / E]`** | Monter / Descendre la caméra |
| **`[Souris (Freecam)]`** | **Orienter la vue à 360° librement** |
| **`[Molette Souris]`** | **Ajuster la vitesse de vol de la Freecam** |
| **`[MAJ / ALT]`** | Accélérer (Sprint) / Ralentir (Précision) |
| **`[Clic Droit]`** | Pivoter temporairement la vue caméra |
| **`[ENTRÉE]`** | **Valider la position et réouvrir le menu** |
| **`[EFFACER / SUPPR / RETOUR]`** | **Effacer / Annuler le prop et réouvrir le menu** |
| **`[ÉCHAP]`** | **Quitter l'Éditeur** |

---

## ⌨️ Commandes & Contrôles du Panel

- **Ouvrir le Panel** : Appuyez sur **`[ÉCHAP]`** (ou tapez `/ymap`).
- **Fermer le Panel** : Appuyez sur **`[ÉCHAP]`** ou le bouton `[X]`.
- **Désactiver le Mode Builder** : Bouton rouge Power dans le header du panel, ou commande `/ymap exit` (restaure le menu pause GTA normal).
- Permission dans `config.lua` : `'none'` (accès libre), ou groupe ACE (`'group.admin'`).
