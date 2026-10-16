Config = {}

-- Commande pour ouvrir l'éditeur de mapping
Config.Command = 'ymap'
-- Commande alternative
Config.AlternativeCommand = 'builder'

-- Permission nécessaire : 'none' pour autoriser tout le monde (dev/local), ou un groupe ACE comme 'group.admin', ou 'ace:command.ymap'
Config.Permission = 'none'

-- Distance maximale du raycast pour poser un prop
Config.MaxRaycastDistance = 60.0

-- Sensibilité des ajustements
Config.StepHeight = 0.05       -- Déplacement Z avec les touches
Config.StepRotation = 5.0      -- Degrés de rotation par cran
Config.StepFine = 0.01         -- Déplacement précis quand Shift ou Alt est pressé

-- Configuration de l'export YMAP
Config.DefaultLodDist = 200.0   -- Distance de LOD par défaut
Config.DefaultFlags = 1572864   -- Flags standard CodeWalker pour prop statique avec collision (ou 0 / 32)

-- Exporter également une ressource FiveM complète et prête à démarrer (fxmanifest.lua + client.lua)
Config.ExportAsResource = true

-- Configuration du Snapping (Grille & Angles)
Config.Snap = {
    DefaultEnabled = false,      -- Activer par défaut le snapping
    TranslationStep = 0.5,       -- Paliers de déplacement en mètres (0.25, 0.5, 1.0, 2.0)
    RotationStep = 45.0          -- Paliers de rotation en degrés (15.0, 45.0, 90.0)
}

-- [Prévu pour future mise à jour] Zones d'ambiance (Halloween, Noël, Brouillard, etc.)
Config.AmbianceZones = {
    Enabled = false,
    Zones = {}
}

-- Catégories et catalogue de props par défaut (vous pouvez en rajouter ou taper n'importe quel hash/nom dans l'UI)
Config.Categories = {
    {
        id = 'barriers',
        name = 'Barrières & Clôtures',
        icon = 'fa-solid fa-road-barrier',
        props = {
            { label = 'Barrière de police', model = 'prop_barrier_work05' },
            { label = 'Barrière béton (Jersey)', model = 'prop_barier_conc_05c' },
            { label = 'Barrière chantier', model = 'prop_barrier_work06a' },
            { label = 'Barrière plastique rouge', model = 'prop_barrier_wat_03b' },
            { label = 'Clôture métallique', model = 'prop_fnclink_02gate1' },
            { label = 'Poteau guide file', model = 'prop_barrier_work01a' },
            { label = 'Cône de circulation', model = 'prop_mp_cone_01' },
            { label = 'Grand plot orange', model = 'prop_roadcone02a' }
        }
    },
    {
        id = 'urban',
        name = 'Mobilier Urbain',
        icon = 'fa-solid fa-city',
        props = {
            { label = 'Banc public bois', model = 'prop_bench_01a' },
            { label = 'Banc moderne pierre', model = 'prop_bench_06' },
            { label = 'Poubelle municipale', model = 'prop_bin_01a' },
            { label = 'Grande benne à ordures', model = 'prop_dumpster_01a' },
            { label = 'Horodateur', model = 'prop_parknmeter_01' },
            { label = 'Borne incendie', model = 'prop_fire_hydrant_1' },
            { label = 'Cabine téléphonique', model = 'prop_phonebox_04' },
            { label = 'Arrêt de bus abri', model = 'prop_busstop_02' },
            { label = 'Boîte aux lettres US', model = 'prop_postbox_01a' }
        }
    },
    {
        id = 'furniture',
        name = 'Meubles & Intérieur',
        icon = 'fa-solid fa-couch',
        props = {
            { label = 'Canapé en cuir noir', model = 'v_res_mp_sofa' },
            { label = 'Fauteuil moderne', model = 'v_res_m_armchair' },
            { label = 'Table basse salon', model = 'v_res_coffeetable' },
            { label = 'Chaise de bureau', model = 'v_corp_offchair' },
            { label = 'Bureau informatique', model = 'v_med_cor_desk' },
            { label = 'Chaise pliante', model = 'prop_chair_08' },
            { label = 'Table en bois picnic', model = 'prop_picnictable_01' },
            { label = 'Étagère métallique', model = 'prop_shelves_02' },
            { label = 'Lit 2 places', model = 'v_res_msonbed_s' }
        }
    },
    {
        id = 'lights',
        name = 'Éclairage & Lampes',
        icon = 'fa-solid fa-lightbulb',
        props = {
            { label = 'Lampadaire urbain double', model = 'prop_streetlight_01' },
            { label = 'Lampadaire moderne', model = 'prop_streetlight_03b' },
            { label = 'Spot de chantier sur pied', model = 'prop_worklight_03b' },
            { label = 'Petit projecteur mural', model = 'prop_wall_light_05a' },
            { label = 'Lanterne de jardin', model = 'prop_garden_light_01' }
        }
    },
    {
        id = 'nature',
        name = 'Nature & Végétation',
        icon = 'fa-solid fa-tree',
        props = {
            { label = 'Grand Palmier', model = 'prop_tree_palm_01a' },
            { label = 'Palmier courbé', model = 'prop_tree_palm_02a' },
            { label = 'Chêne moyen', model = 'prop_tree_oak_01' },
            { label = 'Buisson rond taillé', model = 'prop_bush_med_01' },
            { label = 'Haie végétale', model = 'prop_hedge_01' },
            { label = 'Plante en pot terrasse', model = 'prop_pot_plant_01a' },
            { label = 'Grand pot de fleurs', model = 'prop_plant_palm_01a' },
            { label = 'Rocher décoratif', model = 'prop_rock_1_a' }
        }
    },
    {
        id = 'construction',
        name = 'Chantier & Industrie',
        icon = 'fa-solid fa-person-digging',
        props = {
            { label = 'Conteneur maritime bleu', model = 'prop_container_01a' },
            { label = 'Conteneur maritime rouge', model = 'prop_container_01c' },
            { label = 'Échafaudage', model = 'prop_scaffolding_01' },
            { label = 'Générateur de chantier', model = 'prop_generator_01a' },
            { label = 'Palette en bois vide', model = 'prop_pallet_01a' },
            { label = 'Palette avec sacs de ciment', model = 'prop_pallet_02a' },
            { label = 'Baril d\'huile en métal', model = 'prop_oil_barrel_01' },
            { label = 'Caisse de transport en bois', model = 'prop_box_wood02a' }
        }
    },
    {
        id = 'leisure',
        name = 'Loisirs & Événements',
        icon = 'fa-solid fa-champagne-glasses',
        props = {
            { label = 'Tente / Barnum blanc', model = 'prop_gazebo_02' },
            { label = 'Parasol de plage ouvert', model = 'prop_parasol_02' },
            { label = 'Transat bain de soleil', model = 'prop_chair_02' },
            { label = 'Barbecue de jardin', model = 'prop_bbq_3' },
            { label = 'Glacière portative', model = 'prop_coolbox_01' },
            { label = 'Table de DJ / Enceinte', model = 'prop_speaker_05' },
            { label = 'Structure d\'enceinte concert', model = 'prop_speaker_08' }
        }
    },
    {
        id = 'halloween',
        name = 'Halloween (Evo Props)',
        icon = 'fa-solid fa-ghost',
        props = {
            { label = 'Citrouille 1', model = 'evo_pumpkin1' },
            { label = 'Citrouille 2', model = 'evo_pumpkin2' },
            { label = 'Citrouille 3', model = 'evo_pumpkin3' },
            { label = 'Citrouille 4', model = 'evo_pumpkin4' },
            { label = 'Citrouille Découpée 2', model = 'evo_pumpkin_d2' },
            { label = 'Citrouille Découpée 3', model = 'evo_pumpkin_d3' },
            { label = 'Lanterne Halloween', model = 'evo_lantern' },
            { label = 'Squelette', model = 'evo_skeleton' },
            { label = 'Araignée géante', model = 'evo_spider' },
            { label = 'Chauve-souris', model = 'evo_bat' },
            { label = 'Bannière Halloween', model = 'evo_banner' },
            { label = 'Panneau Halloween', model = 'evo_halloween_sign' }
        }
    }
}
