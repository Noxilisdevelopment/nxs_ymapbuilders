-- Permissions ACE automatiques pour les commandes du Gizmo 3D FiveM (Im3D)
CreateThread(function()
    local commands = {
        'command.+gizmoSelect', 'command.-gizmoSelect',
        'command.+gizmoTranslation', 'command.-gizmoTranslation',
        'command.+gizmoRotation', 'command.-gizmoRotation',
        'command.+gizmoLocal', 'command.-gizmoLocal',
        'command.+gizmoScale', 'command.-gizmoScale'
    }
    for _, cmd in ipairs(commands) do
        ExecuteCommand(('add_ace builtin.everyone %s allow'):format(cmd))
    end
end)

local function EulerToQuaternion(rotX, rotY, rotZ)
    local radX = math.rad(rotX) * 0.5
    local radY = math.rad(rotY) * 0.5
    local radZ = math.rad(rotZ) * 0.5

    local c1 = math.cos(radX)
    local s1 = math.sin(radX)
    local c2 = math.cos(radY)
    local s2 = math.sin(radY)
    local c3 = math.cos(radZ)
    local s3 = math.sin(radZ)

    -- Ordre intrinsèque GTA V (ZXY)
    local w = c1 * c2 * c3 - s1 * s2 * s3
    local x = s1 * c2 * c3 - c1 * s2 * s3
    local y = c1 * s2 * c3 + s1 * c2 * s3
    local z = c1 * c2 * s3 + s1 * s2 * c3

    local len = math.sqrt(x * x + y * y + z * z + w * w)
    if len > 0.000001 then
        x = x / len
        y = y / len
        z = z / len
        w = w / len
    else
        x, y, z, w = 0.0, 0.0, 0.0, 1.0
    end

    return x, y, z, w
end

local function sanitizeFileName(name)
    if not name or name == '' then return 'mapping_' .. os.time() end
    name = name:gsub('[^%w%-_]', '_')
    return name:lower()
end

-- Vérification des permissions
local function hasPermission(source)
    if Config.Permission == 'none' then
        return true
    end
    if IsPlayerAceAllowed(source, Config.Permission) then
        return true
    end
    return false
end

-- Commandes d'ouverture
local function openBuilder(source)
    if not hasPermission(source) then
        TriggerClientEvent('ox_lib:notify', source, {
            type = 'error',
            description = 'Vous n\'avez pas la permission d\'utiliser le YMAP Builder.'
        })
        return
    end
    TriggerClientEvent('nxs_ymapbuilder:client:openUI', source)
end

-- Autorisation globale des commandes Gizmo C++ de FiveM pour éviter tout refus de permission ACE
CreateThread(function()
    ExecuteCommand('add_ace builtin.everyone command.+gizmoSelect allow')
    ExecuteCommand('add_ace builtin.everyone command.-gizmoSelect allow')
    ExecuteCommand('add_ace builtin.everyone command.+gizmoTranslation allow')
    ExecuteCommand('add_ace builtin.everyone command.-gizmoTranslation allow')
    ExecuteCommand('add_ace builtin.everyone command.+gizmoRotation allow')
    ExecuteCommand('add_ace builtin.everyone command.-gizmoRotation allow')
    ExecuteCommand('add_ace builtin.everyone command.+gizmoLocal allow')
    ExecuteCommand('add_ace builtin.everyone command.-gizmoLocal allow')
end)

RegisterNetEvent('nxs_ymapbuilder:server:grantGizmoPermissions', function()
    local src = source
    if src and src > 0 then
        ExecuteCommand(('add_ace player.%s command.+gizmoSelect allow'):format(src))
        ExecuteCommand(('add_ace player.%s command.-gizmoSelect allow'):format(src))
        ExecuteCommand(('add_ace player.%s command.+gizmoTranslation allow'):format(src))
        ExecuteCommand(('add_ace player.%s command.-gizmoTranslation allow'):format(src))
        ExecuteCommand(('add_ace player.%s command.+gizmoRotation allow'):format(src))
        ExecuteCommand(('add_ace player.%s command.-gizmoRotation allow'):format(src))
        ExecuteCommand(('add_ace player.%s command.+gizmoLocal allow'):format(src))
        ExecuteCommand(('add_ace player.%s command.-gizmoLocal allow'):format(src))
    end
end)

RegisterCommand(Config.Command, function(source, args)
    if args and (args[1] == 'exit' or args[1] == 'off' or args[1] == 'stop') then
        TriggerClientEvent('nxs_ymapbuilder:client:toggleBuilderMode', source, false)
        return
    end
    openBuilder(source)
end, false)

if Config.AlternativeCommand and Config.AlternativeCommand ~= '' then
    RegisterCommand(Config.AlternativeCommand, function(source, args)
        if args and (args[1] == 'exit' or args[1] == 'off' or args[1] == 'stop') then
            TriggerClientEvent('nxs_ymapbuilder:client:toggleBuilderMode', source, false)
            return
        end
        openBuilder(source)
    end, false)
end

-- Callback pour exporter le YMAP
lib.callback.register('nxs_ymapbuilder:server:exportYmap', function(source, data)
    if not hasPermission(source) then
        return { success = false, message = 'Permission refusée' }
    end

    local mapName = sanitizeFileName(data.name)
    local entities = data.entities or {}

    if #entities == 0 then
        return { success = false, message = 'Aucun prop à exporter dans ce projet !' }
    end

    -- Calcul des limites AABB (Bounding Box)
    local minX, minY, minZ = 999999.0, 999999.0, 999999.0
    local maxX, maxY, maxZ = -999999.0, -999999.0, -999999.0

    for _, ent in ipairs(entities) do
        local x = tonumber(ent.coords.x) or 0.0
        local y = tonumber(ent.coords.y) or 0.0
        local z = tonumber(ent.coords.z) or 0.0

        if x < minX then minX = x end
        if y < minY then minY = y end
        if z < minZ then minZ = z end

        if x > maxX then maxX = x end
        if y > maxY then maxY = y end
        if z > maxZ then maxZ = z end
    end

    -- Marges de streaming et d'entités pour CodeWalker
    local margin = 30.0
    local streamMargin = 150.0

    local entitiesMin = { x = minX - margin, y = minY - margin, z = minZ - margin }
    local entitiesMax = { x = maxX + margin, y = maxY + margin, z = maxZ + margin }
    local streamingMin = { x = minX - streamMargin, y = minY - streamMargin, z = minZ - streamMargin }
    local streamingMax = { x = maxX + streamMargin, y = maxY + streamMargin, z = maxZ + streamMargin }

    -- Construction du XML
    local xmlItems = {}
    for i, ent in ipairs(entities) do
        local qx, qy, qz, qw
        if ent.quat and ent.quat.w then
            -- Dans les fichiers YMAP de GTA V (CEntityDef), le quaternion attendu par le jeu et CodeWalker
            -- est le conjugué/inverse du quaternion runtime de FiveM (-qx, -qy, -qz, qw)
            qx = -(tonumber(ent.quat.x) or 0.0)
            qy = -(tonumber(ent.quat.y) or 0.0)
            qz = -(tonumber(ent.quat.z) or 0.0)
            qw = (tonumber(ent.quat.w) or 1.0)
        else
            qx, qy, qz, qw = EulerToQuaternion(ent.rot.x, ent.rot.y, ent.rot.z)
        end

        local modelName = ent.model or 'unknown'
        local lodDist = tonumber(ent.lodDist) or Config.DefaultLodDist
        local flags = tonumber(ent.flags) or Config.DefaultFlags

        local itemXml = string.format([[    <Item type="CEntityDef">
      <archetypeName>%s</archetypeName>
      <flags value="%d"/>
      <guid value="%d"/>
      <position x="%.8f" y="%.8f" z="%.8f"/>
      <rotation x="%.8f" y="%.8f" z="%.8f" w="%.8f"/>
      <scaleXY value="1.00000000"/>
      <scaleZ value="1.00000000"/>
      <parentIndex value="-1"/>
      <lodDist value="%.6f"/>
      <childLodDist value="0.00000000"/>
      <lodLevel>LODTYPES_DEPTH_HD</lodLevel>
      <numChildren value="0"/>
      <priorityLevel>PRI_REQUIRED</priorityLevel>
      <extensions/>
      <ambientOcclusionMultiplier value="255"/>
      <artificialAmbientOcclusion value="255"/>
      <tintValue value="0"/>
    </Item>]],
            modelName,
            flags,
            i,
            ent.coords.x, ent.coords.y, ent.coords.z,
            qx, qy, qz, qw,
            lodDist
        )
        table.insert(xmlItems, itemXml)
    end

    local ymapXml = string.format([[<?xml version="1.0" encoding="UTF-8" standalone="no"?>
<CMapData>
  <name>%s</name>
  <parent/>
  <flags value="0"/>
  <contentFlags value="65"/>
  <streamingExtentsMin x="%.6f" y="%.6f" z="%.6f"/>
  <streamingExtentsMax x="%.6f" y="%.6f" z="%.6f"/>
  <entitiesExtentsMin x="%.6f" y="%.6f" z="%.6f"/>
  <entitiesExtentsMax x="%.6f" y="%.6f" z="%.6f"/>
  <entities>
%s
  </entities>
</CMapData>]],
        mapName,
        streamingMin.x, streamingMin.y, streamingMin.z,
        streamingMax.x, streamingMax.y, streamingMax.z,
        entitiesMin.x, entitiesMin.y, entitiesMin.z,
        entitiesMax.x, entitiesMax.y, entitiesMax.z,
        table.concat(xmlItems, "\n")
    )

    -- Construction d'un script Lua de spawn direct
    local luaItems = {}
    for _, ent in ipairs(entities) do
        table.insert(luaItems, string.format('    { model = `%s`, coords = vector3(%.3f, %.3f, %.3f), rot = vector3(%.2f, %.2f, %.2f) },',
            ent.model, ent.coords.x, ent.coords.y, ent.coords.z, ent.rot.x, ent.rot.y, ent.rot.z
        ))
    end

    local luaContent = string.format([[-- Mapping généré par nxs_ymapbuilder (%s)
-- Nombre d'objets: %d
local props = {
%s
}

CreateThread(function()
    for _, data in ipairs(props) do
        lib.requestModel(data.model)
        local obj = CreateObject(data.model, data.coords.x, data.coords.y, data.coords.z, false, false, false)
        SetEntityRotation(obj, data.rot.x, data.rot.y, data.rot.z, 2, true)
        FreezeEntityPosition(obj, true)
        SetModelAsNoLongerNeeded(data.model)
    end
end)]],
        mapName,
        #entities,
        table.concat(luaItems, "\n")
    )

    -- Sauvegarde JSON pour rechargement du projet
    local jsonContent = json.encode({
        name = mapName,
        createdAt = os.date('%Y-%m-%d %H:%M:%S'),
        entitiesCount = #entities,
        entities = entities
    }, { indent = true })

    -- Sauvegarde physique dans exports/
    local resName = GetCurrentResourceName()
    SaveResourceFile(resName, ('exports/%s.ymap.xml'):format(mapName), ymapXml, -1)
    SaveResourceFile(resName, ('exports/%s_client.lua'):format(mapName), luaContent, -1)
    SaveResourceFile(resName, ('exports/%s_save.json'):format(mapName), jsonContent, -1)

    -- Mise à jour de l'index des projets pour l'UI
    local indexRaw = LoadResourceFile(resName, 'exports/projects_index.json')
    local index = {}
    if indexRaw and indexRaw ~= '' then
        pcall(function() index = json.decode(indexRaw) or {} end)
    end

    local newEntry = {
        name = mapName,
        createdAt = os.date('%Y-%m-%d %H:%M'),
        entitiesCount = #entities
    }
    local found = false
    for idx, p in ipairs(index) do
        if p.name == mapName then
            index[idx] = newEntry
            found = true
            break
        end
    end
    if not found then
        table.insert(index, 1, newEntry)
    end
    SaveResourceFile(resName, 'exports/projects_index.json', json.encode(index, { indent = true }), -1)

    -- Exportation en ressource autonome FiveM si activé
    if Config.ExportAsResource then
        local packFolder = ('exports/%s_pack'):format(mapName)
        local fxmanifestContent = ([[fx_version 'cerulean'
game 'gta5'
lua54 'yes'

author 'nxs_ymapbuilder'
description 'Ressource de mapping générée automatiquement'
version '1.0.0'

this_is_a_map 'yes'

client_script 'client.lua'
]])
        SaveResourceFile(resName, packFolder .. '/fxmanifest.lua', fxmanifestContent, -1)
        SaveResourceFile(resName, packFolder .. '/client.lua', luaContent, -1)
        local readmeContent = ([[=== RESSOURCE MAPPING FIVEM : %s ===
Généré par nxs_ymapbuilder.

Installation :
1. Déplacez ce dossier '%s_pack' dans votre répertoire 'resources/' de votre serveur FiveM.
2. Ajoutez la ligne suivante dans votre server.cfg :
   ensure %s_pack
3. Redémarrez votre serveur ou tapez 'refresh' puis 'start %s_pack' dans la console !
]]):format(mapName, mapName, mapName, mapName)
        SaveResourceFile(resName, packFolder .. '/README.txt', readmeContent, -1)
    end

    print(('[nxs_ymapbuilder] Export réussi pour le projet "%s" (%d objets)'):format(mapName, #entities))

    return {
        success = true,
        fileName = mapName .. '.ymap.xml',
        totalEntities = #entities,
        xmlContent = ymapXml,
        luaContent = luaContent
    }
end)

-- Callback pour lister les projets sauvegardés
lib.callback.register('nxs_ymapbuilder:server:getSavedProjects', function(source)
    if not hasPermission(source) then return {} end
    local resName = GetCurrentResourceName()
    local raw = LoadResourceFile(resName, 'exports/projects_index.json')
    if raw and raw ~= '' then
        local ok, data = pcall(json.decode, raw)
        if ok and type(data) == 'table' then
            return data
        end
    end
    return {}
end)

-- Callback pour charger un projet existant
lib.callback.register('nxs_ymapbuilder:server:loadProject', function(source, mapName)
    if not hasPermission(source) then
        return { success = false, message = 'Permission refusée' }
    end
    local resName = GetCurrentResourceName()
    local safeName = sanitizeFileName(mapName)
    local raw = LoadResourceFile(resName, ('exports/%s_save.json'):format(safeName))
    if not raw or raw == '' then
        return { success = false, message = 'Fichier de sauvegarde introuvable.' }
    end
    local ok, data = pcall(json.decode, raw)
    if not ok or not data or not data.entities then
        return { success = false, message = 'Erreur lors de la lecture du fichier de sauvegarde.' }
    end
    return { success = true, name = safeName, entities = data.entities }
end)

-- Callback pour supprimer un projet de l'index
lib.callback.register('nxs_ymapbuilder:server:deleteProject', function(source, mapName)
    if not hasPermission(source) then
        return { success = false, message = 'Permission refusée' }
    end
    local resName = GetCurrentResourceName()
    local safeName = sanitizeFileName(mapName)
    local raw = LoadResourceFile(resName, 'exports/projects_index.json')
    local index = {}
    if raw and raw ~= '' then
        pcall(function() index = json.decode(raw) or {} end)
    end
    for i, p in ipairs(index) do
        if p.name == safeName then
            table.remove(index, i)
            break
        end
    end
    SaveResourceFile(resName, 'exports/projects_index.json', json.encode(index, { indent = true }), -1)
    return { success = true, projects = index }
end)
