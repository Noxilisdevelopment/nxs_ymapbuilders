placedObjects = {}
local isUIOpen = false
local highlightedEntity = nil

-- Historique Annuler / Rétablir (Undo / Redo)
local undoHistory = {}
local redoHistory = {}

function pushUndo(action)
    table.insert(undoHistory, action)
    redoHistory = {} -- Réinitialiser redo lors d'une nouvelle action
    if #undoHistory > 50 then
        table.remove(undoHistory, 1)
    end
end

function GetPlacedObjects()
    return placedObjects
end

function GetPlacedObjectByEntity(ent)
    for i = 1, #placedObjects do
        if placedObjects[i].handle == ent then
            return placedObjects[i], i
        end
    end
    return nil, nil
end

function DeletePlacedPropByHandle(ent)
    for i = #placedObjects, 1, -1 do
        if placedObjects[i].handle == ent then
            local data = placedObjects[i]
            if DoesEntityExist(ent) then
                DeleteEntity(ent)
            end
            table.remove(placedObjects, i)
            for j = 1, #placedObjects do placedObjects[j].id = j end
            pushUndo({ type = 'DELETE', id = i, data = data })
            if isUIOpen then
                SendNUIMessage({ action = 'updatePlaced', placedEntities = getUIPlacedEntities() })
            end
            return true, data
        end
    end
    if DoesEntityExist(ent) then
        DeleteEntity(ent)
    end
    return false, nil
end

function UpdatePlacedObjectTransform(ent)
    for i = 1, #placedObjects do
        if placedObjects[i].handle == ent then
            local c = GetEntityCoords(ent)
            local r = GetEntityRotation(ent, 2)
            local qx, qy, qz, qw = GetEntityQuaternion(ent)
            placedObjects[i].coords = { x = c.x, y = c.y, z = c.z }
            placedObjects[i].rot = { x = r.x, y = r.y, z = r.z }
            placedObjects[i].quat = { x = qx, y = qy, z = qz, w = qw }
            return placedObjects[i]
        end
    end
    return nil
end

-- Préparation des données pour l'UI (optimisé O(N) sans appels redondants de natives)
local function getUIPlacedEntities()
    local count = #placedObjects
    local list = table.create(count, 0)
    for i = 1, count do
        local ent = placedObjects[i]
        list[i] = {
            id = i,
            model = ent.model,
            coords = ent.coords,
            rot = ent.rot
        }
    end
    return list
end

-- Fonction Annuler (Undo)
local function performUndo()
    if #undoHistory == 0 then
        lib.notify({ title = 'Historique', description = 'Rien à annuler.', type = 'inform' })
        return
    end

    local action = table.remove(undoHistory)
    if action.type == 'ADD' or action.type == 'DUPLICATE' then
        local targetHandle = action.handle
        for i = #placedObjects, 1, -1 do
            if placedObjects[i].handle == targetHandle then
                if DoesEntityExist(targetHandle) then
                    DeleteEntity(targetHandle)
                end
                table.remove(placedObjects, i)
                break
            end
        end
        for i = 1, #placedObjects do placedObjects[i].id = i end
        table.insert(redoHistory, action)
        PlaySoundFrontend(-1, "CANCEL", "HUD_FRONTEND_DEFAULT_SOUNDSET", true)
        lib.notify({ title = 'Historique', description = ('Annulé : %s'):format(action.model), type = 'inform' })

    elseif action.type == 'DELETE' then
        local ent = action.data
        local hash = type(ent.model) == 'number' and ent.model or joaat(ent.model)
        RequestModel(hash)
        while not HasModelLoaded(hash) do Wait(0) end
        local obj = CreateObject(hash, ent.coords.x, ent.coords.y, ent.coords.z, false, false, false)
        SetEntityRotation(obj, ent.rot.x, ent.rot.y, ent.rot.z, 2, true)
        FreezeEntityPosition(obj, true)
        SetEntityCollision(obj, true, true)
        SetModelAsNoLongerNeeded(hash)

        local qx, qy, qz, qw = GetEntityQuaternion(obj)
        ent.handle = obj
        ent.quat = { x = qx, y = qy, z = qz, w = qw }
        table.insert(placedObjects, action.id or (#placedObjects + 1), ent)
        for i = 1, #placedObjects do placedObjects[i].id = i end

        table.insert(redoHistory, { type = 'RECREATE', handle = obj, model = ent.model, id = action.id, data = ent })
        PlaySoundFrontend(-1, "SELECT", "HUD_FRONTEND_DEFAULT_SOUNDSET", true)
        lib.notify({ title = 'Historique', description = ('Restauré : %s'):format(ent.model), type = 'success' })

    elseif action.type == 'MOVE' then
        if DoesEntityExist(action.handle) then
            SetEntityCoords(action.handle, action.oldCoords.x, action.oldCoords.y, action.oldCoords.z, false, false, false, false)
            SetEntityRotation(action.handle, action.oldRot.x, action.oldRot.y, action.oldRot.z, 2, true)
        end
        for i = 1, #placedObjects do
            if placedObjects[i].handle == action.handle then
                placedObjects[i].coords = action.oldCoords
                placedObjects[i].rot = action.oldRot
                placedObjects[i].quat = action.oldQuat
                break
            end
        end
        table.insert(redoHistory, action)
        lib.notify({ title = 'Historique', description = 'Déplacement annulé.', type = 'inform' })
    end

    if isUIOpen then
        SendNUIMessage({ action = 'updatePlaced', placedEntities = getUIPlacedEntities() })
    end
end

-- Fonction Rétablir (Redo)
local function performRedo()
    if #redoHistory == 0 then
        lib.notify({ title = 'Historique', description = 'Rien à rétablir.', type = 'inform' })
        return
    end

    local action = table.remove(redoHistory)
    if action.type == 'ADD' or action.type == 'DUPLICATE' then
        local hash = type(action.model) == 'number' and action.model or joaat(action.model)
        RequestModel(hash)
        while not HasModelLoaded(hash) do Wait(0) end
        local obj = CreateObject(hash, action.coords.x, action.coords.y, action.coords.z, false, false, false)
        SetEntityRotation(obj, action.rot.x, action.rot.y, action.rot.z, 2, true)
        FreezeEntityPosition(obj, true)
        SetEntityCollision(obj, true, true)
        SetModelAsNoLongerNeeded(hash)

        local qx, qy, qz, qw = GetEntityQuaternion(obj)
        action.handle = obj
        local id = #placedObjects + 1
        placedObjects[id] = {
            id = id,
            model = action.model,
            handle = obj,
            coords = action.coords,
            rot = action.rot,
            quat = { x = qx, y = qy, z = qz, w = qw },
            lodDist = Config.DefaultLodDist,
            flags = Config.DefaultFlags
        }
        table.insert(undoHistory, action)
        PlaySoundFrontend(-1, "SELECT", "HUD_FRONTEND_DEFAULT_SOUNDSET", true)
        lib.notify({ title = 'Historique', description = ('Rétabli : %s'):format(action.model), type = 'success' })

    elseif action.type == 'DELETE' or action.type == 'RECREATE' then
        if DoesEntityExist(action.handle) then
            DeleteEntity(action.handle)
        end
        for i = #placedObjects, 1, -1 do
            if placedObjects[i].handle == action.handle then
                table.remove(placedObjects, i)
                break
            end
        end
        for i = 1, #placedObjects do placedObjects[i].id = i end
        table.insert(undoHistory, action)
        lib.notify({ title = 'Historique', description = 'Suppression rétablie.', type = 'inform' })

    elseif action.type == 'MOVE' then
        if DoesEntityExist(action.handle) then
            SetEntityCoords(action.handle, action.newCoords.x, action.newCoords.y, action.newCoords.z, false, false, false, false)
            SetEntityRotation(action.handle, action.newRot.x, action.newRot.y, action.newRot.z, 2, true)
        end
        for i = 1, #placedObjects do
            if placedObjects[i].handle == action.handle then
                placedObjects[i].coords = action.newCoords
                placedObjects[i].rot = action.newRot
                placedObjects[i].quat = action.newQuat
                break
            end
        end
        table.insert(undoHistory, action)
        lib.notify({ title = 'Historique', description = 'Déplacement rétabli.', type = 'success' })
    end

    if isUIOpen then
        SendNUIMessage({ action = 'updatePlaced', placedEntities = getUIPlacedEntities() })
    end
end

-- Raccourcis clavier globaux pour Undo / Redo
lib.addKeybind({
    name = '_ymapUndo',
    description = 'Annuler la dernière action (Undo)',
    defaultKey = 'Z',
    onPressed = function()
        if IsDisabledControlPressed(0, 36) or IsControlPressed(0, 36) or IsDisabledControlPressed(0, 21) or IsControlPressed(0, 21) then
            performUndo()
        end
    end
})

lib.addKeybind({
    name = '_ymapRedo',
    description = 'Rétablir la dernière action (Redo)',
    defaultKey = 'Y',
    onPressed = function()
        if IsDisabledControlPressed(0, 36) or IsControlPressed(0, 36) or IsDisabledControlPressed(0, 21) or IsControlPressed(0, 21) then
            performRedo()
        end
    end
})

-- Marqueur 3D sur l'objet sélectionné dans la liste (veille 1000ms si inactif)
CreateThread(function()
    while true do
        if isUIOpen and highlightedEntity and DoesEntityExist(highlightedEntity) then
            local coords = GetEntityCoords(highlightedEntity)
            DrawMarker(
                0, -- Flèche vers le bas
                coords.x, coords.y, coords.z + 1.2,
                0.0, 0.0, 0.0,
                0.0, 180.0, 0.0,
                0.4, 0.4, 0.4,
                0, 180, 255, 200,
                true, true, 2, false, nil, nil, false
            )
            Wait(0)
        else
            Wait(1000)
        end
    end
end)

-- Ouverture de l'UI
function openMainUI()
    isUIOpen = true
    SetNuiFocus(true, true)
    SendNUIMessage({
        action = 'openUI',
        categories = Config.Categories,
        placedEntities = getUIPlacedEntities()
    })
end

RegisterNetEvent('nxs_ymapbuilder:client:openUI', function()
    openMainUI()
end)

-- Enregistrement direct des clones dupliqués au Gizmo avec MAJ
RegisterNetEvent('nxs_ymapbuilder:client:onGizmoDuplicate', function(data)
    if not data then return end
    local id = #placedObjects + 1
    data.id = id
    placedObjects[id] = data

    pushUndo({
        type = 'DUPLICATE',
        handle = data.handle,
        model = data.model,
        coords = data.coords,
        rot = data.rot,
        quat = data.quat
    })
end)

-- Événement Prop Picker : prop ciblé avec F
RegisterNetEvent('nxs_ymapbuilder:client:onPropTargeted', function(entityHit)
    for i = 1, #placedObjects do
        if placedObjects[i].handle == entityHit then
            highlightedEntity = entityHit
            break
        end
    end
end)

-- Spawn direct et manipulation au Gizmo 3D (avec les flèches X, Y, Z)
local function spawnAndGizmoProp(modelName, initialRot)
    isUIOpen = false
    SetNuiFocus(false, false)
    highlightedEntity = nil

    local modelHash = type(modelName) == 'number' and modelName or joaat(modelName)

    RequestModel(modelHash)
    local startWait = GetGameTimer()
    while not HasModelLoaded(modelHash) do
        Wait(0)
        if (GetGameTimer() - startWait) > 5000 then
            lib.notify({
                title = 'Erreur Prop',
                description = ('Le modèle "%s" n\'a pas pu être chargé.'):format(tostring(modelName)),
                type = 'error'
            })
            openMainUI()
            return
        end
    end

    local playerPed = PlayerPedId()
    local pCoords = GetEntityCoords(playerPed)
    local forward = GetEntityForwardVector(playerPed)
    local spawnCoords = pCoords + (forward * 2.5)

    local obj = CreateObject(modelHash, spawnCoords.x, spawnCoords.y, spawnCoords.z, false, false, false)
    SetModelAsNoLongerNeeded(modelHash) -- Libération immédiate de la mémoire de streaming GTA V

    if initialRot then
        SetEntityRotation(obj, initialRot.x, initialRot.y, initialRot.z, 2, true)
    else
        SetEntityHeading(obj, GetEntityHeading(playerPed))
    end

    -- Plaquer d'office parfaitement au sol avec détection de boîte englobante et raycast
    SnapEntityToGroundProperly(obj)
    FreezeEntityPosition(obj, true)
    SetEntityCollision(obj, true, true)

    local initialCoords = GetEntityCoords(obj)
    local initialRot = GetEntityRotation(obj, 2)
    local qx, qy, qz, qw = GetEntityQuaternion(obj)
    local id = #placedObjects + 1

    placedObjects[id] = {
        id = id,
        model = modelName,
        handle = obj,
        coords = { x = initialCoords.x, y = initialCoords.y, z = initialCoords.z },
        rot = { x = initialRot.x, y = initialRot.y, z = initialRot.z },
        quat = { x = qx, y = qy, z = qz, w = qw },
        lodDist = Config.DefaultLodDist,
        flags = Config.DefaultFlags
    }

    pushUndo({
        type = 'ADD',
        handle = obj,
        model = modelName,
        coords = { x = initialCoords.x, y = initialCoords.y, z = initialCoords.z },
        rot = { x = initialRot.x, y = initialRot.y, z = initialRot.z },
        quat = { x = qx, y = qy, z = qz, w = qw }
    })

    PlaySoundFrontend(-1, "SELECT", "HUD_FRONTEND_DEFAULT_SOUNDSET", true)
    lib.notify({
        title = 'YMAP Builder',
        description = ('Prop "%s" posé (#%d)'):format(modelName, id),
        type = 'success'
    })

    -- Lancement de la Caméra Libre / Éditeur Gizmo 3D
    CreateThread(function()
        exports.nxs_ymapbuilder:useGizmo(obj, modelName)
        if DoesEntityExist(obj) then
            UpdatePlacedObjectTransform(obj)
        end
    end)
end

-- Callbacks NUI
RegisterNUICallback('closeUI', function(_, cb)
    isUIOpen = false
    SetNuiFocus(false, false)
    highlightedEntity = nil
    cb('ok')
end)

RegisterNUICallback('undo', function(_, cb)
    performUndo()
    cb({ success = true, placedEntities = getUIPlacedEntities() })
end)

RegisterNUICallback('redo', function(_, cb)
    performRedo()
    cb({ success = true, placedEntities = getUIPlacedEntities() })
end)

RegisterNUICallback('startPlacement', function(data, cb)
    spawnAndGizmoProp(data.model)
    cb({ success = true })
end)

RegisterNUICallback('highlightProp', function(data, cb)
    local id = tonumber(data.id)
    if placedObjects[id] and DoesEntityExist(placedObjects[id].handle) then
        highlightedEntity = placedObjects[id].handle
    else
        highlightedEntity = nil
    end
    cb('ok')
end)

RegisterNUICallback('teleportToProp', function(data, cb)
    local id = tonumber(data.id)
    if placedObjects[id] and DoesEntityExist(placedObjects[id].handle) then
        local coords = GetEntityCoords(placedObjects[id].handle)
        SetEntityCoords(PlayerPedId(), coords.x, coords.y - 1.5, coords.z, false, false, false, false)
        lib.notify({
            title = 'Téléportation',
            description = 'Téléporté au prop #' .. id,
            type = 'inform'
        })
    end
    cb('ok')
end)

RegisterNUICallback('editPropGizmo', function(data, cb)
    local id = tonumber(data.id)
    local entData = placedObjects[id]
    if not entData or not DoesEntityExist(entData.handle) then
        cb({ success = false, message = 'Entité introuvable' })
        return
    end

    isUIOpen = false
    SetNuiFocus(false, false)
    highlightedEntity = nil

    CreateThread(function()
        exports.nxs_ymapbuilder:useGizmo(entData.handle, entData.model)
        if DoesEntityExist(entData.handle) then
            UpdatePlacedObjectTransform(entData.handle)
        end
    end)

    cb({ success = true })
end)

-- Clic direct dans le monde 3D quand le menu est ouvert pour sélectionner un prop déjà posé
RegisterNUICallback('clickWorldProp', function(data, cb)
    local screenX = tonumber(data.x)
    local screenY = tonumber(data.y)
    if not screenX or not screenY then
        cb({ success = false })
        return
    end

    local pickedHandle, pickedData = nil, nil
    if PickPlacedPropAtCoords then
        pickedHandle, pickedData = PickPlacedPropAtCoords(nil, screenX, screenY)
    elseif exports.nxs_ymapbuilder and exports.nxs_ymapbuilder.PickPlacedPropUnderMouse then
        pickedHandle, pickedData = exports.nxs_ymapbuilder:PickPlacedPropUnderMouse(nil, screenX, screenY)
    end

    if pickedHandle and DoesEntityExist(pickedHandle) then
        isUIOpen = false
        SetNuiFocus(false, false)
        highlightedEntity = nil
        SendNUIMessage({ action = 'forceClose' })

        PlaySoundFrontend(-1, "SELECT", "HUD_FRONTEND_DEFAULT_SOUNDSET", true)
        lib.notify({
            title = 'Prop Sélectionné',
            description = ('Prop "%s" sélectionné.'):format(tostring(pickedData and pickedData.model or 'prop')),
            type = 'success'
        })

        CreateThread(function()
            Wait(50)
            exports.nxs_ymapbuilder:useGizmo(pickedHandle, pickedData and pickedData.model)
            if DoesEntityExist(pickedHandle) then
                UpdatePlacedObjectTransform(pickedHandle)
            end
        end)

        cb({ success = true, found = true })
    else
        cb({ success = true, found = false })
    end
end)

RegisterNUICallback('duplicateProp', function(data, cb)
    local id = tonumber(data.id)
    local entData = placedObjects[id]
    if not entData then
        cb({ success = false })
        return
    end

    spawnAndGizmoProp(entData.model, entData.rot)
    cb({ success = true })
end)

RegisterNUICallback('deleteProp', function(data, cb)
    local id = tonumber(data.id)
    if placedObjects[id] then
        local entData = placedObjects[id]
        if DoesEntityExist(entData.handle) then
            DeleteEntity(entData.handle)
        end
        table.remove(placedObjects, id)
        for i = 1, #placedObjects do
            placedObjects[i].id = i
        end
        pushUndo({ type = 'DELETE', id = id, data = entData })
        highlightedEntity = nil
        lib.notify({
            title = 'YMAP Builder',
            description = 'Prop supprimé.',
            type = 'inform'
        })
    end
    cb({ success = true, placedEntities = getUIPlacedEntities() })
end)

RegisterNUICallback('clearAllProps', function(_, cb)
    for i = 1, #placedObjects do
        local ent = placedObjects[i]
        if DoesEntityExist(ent.handle) then
            DeleteEntity(ent.handle)
        end
    end
    placedObjects = {}
    undoHistory = {}
    redoHistory = {}
    highlightedEntity = nil
    lib.notify({
        title = 'YMAP Builder',
        description = 'Tous les props ont été supprimés.',
        type = 'warning'
    })
    cb({ success = true, placedEntities = {} })
end)

-- Quitter le Mode Builder (rétablir le menu pause de GTA V)
RegisterNUICallback('exitBuilder', function(_, cb)
    isBuilderActive = false
    isUIOpen = false
    SetNuiFocus(false, false)
    highlightedEntity = nil
    lib.notify({
        title = 'YMAP Builder',
        description = 'Mode Builder désactivé (Menu pause normal rétabli). Tapez /ymap pour réactiver.',
        type = 'inform'
    })
    cb('ok')
end)

RegisterNetEvent('nxs_ymapbuilder:client:toggleBuilderMode', function(enabled)
    isBuilderActive = enabled
    if not enabled then
        if isUIOpen then
            isUIOpen = false
            SetNuiFocus(false, false)
            SendNUIMessage({ action = 'forceClose' })
        end
        lib.notify({
            title = 'YMAP Builder',
            description = 'Mode Builder désactivé.',
            type = 'inform'
        })
    else
        lib.notify({
            title = 'YMAP Builder',
            description = 'Mode Builder activé ([Échap] pour ouvrir le panel).',
            type = 'success'
        })
    end
end)

-- Callbacks Projets
RegisterNUICallback('getProjects', function(_, cb)
    lib.callback('nxs_ymapbuilder:server:getSavedProjects', false, function(projects)
        cb({ success = true, projects = projects or {} })
    end)
end)

RegisterNUICallback('loadProject', function(data, cb)
    local projectName = data.name
    if not projectName then return cb({ success = false, message = 'Nom de projet manquant' }) end

    lib.callback('nxs_ymapbuilder:server:loadProject', false, function(res)
        if not res or not res.success or not res.entities then
            lib.notify({ title = 'Projet', description = res and res.message or 'Impossible de charger ce projet.', type = 'error' })
            return cb({ success = false })
        end

        -- Nettoyer les props actuels
        for i = 1, #placedObjects do
            if DoesEntityExist(placedObjects[i].handle) then
                DeleteEntity(placedObjects[i].handle)
            end
        end
        placedObjects = {}
        undoHistory = {}
        redoHistory = {}

        -- Instancier les entités du projet chargé
        local loadedCount = 0
        for i, ent in ipairs(res.entities) do
            local hash = type(ent.model) == 'number' and ent.model or joaat(ent.model)
            RequestModel(hash)
            local w = GetGameTimer()
            while not HasModelLoaded(hash) and (GetGameTimer() - w) < 3000 do Wait(0) end

            local obj = CreateObject(hash, ent.coords.x, ent.coords.y, ent.coords.z, false, false, false)
            if ent.rot then
                SetEntityRotation(obj, ent.rot.x, ent.rot.y, ent.rot.z, 2, true)
            end
            FreezeEntityPosition(obj, true)
            SetEntityCollision(obj, true, true)
            SetModelAsNoLongerNeeded(hash)

            local qx, qy, qz, qw = GetEntityQuaternion(obj)
            placedObjects[#placedObjects + 1] = {
                id = #placedObjects + 1,
                model = ent.model,
                handle = obj,
                coords = ent.coords,
                rot = ent.rot or { x = 0, y = 0, z = 0 },
                quat = ent.quat or { x = qx, y = qy, z = qz, w = qw },
                lodDist = ent.lodDist or Config.DefaultLodDist,
                flags = ent.flags or Config.DefaultFlags
            }
            loadedCount = loadedCount + 1
        end

        PlaySoundFrontend(-1, "SELECT", "HUD_FRONTEND_DEFAULT_SOUNDSET", true)
        lib.notify({
            title = 'Projet Chargé',
            description = ('Projet "%s" chargé avec succès (%d props).'):format(res.name, loadedCount),
            type = 'success'
        })

        cb({ success = true, placedEntities = getUIPlacedEntities() })
    end, projectName)
end)

RegisterNUICallback('deleteProject', function(data, cb)
    local projectName = data.name
    lib.callback('nxs_ymapbuilder:server:deleteProject', false, function(res)
        cb(res)
    end, projectName)
end)

RegisterNUICallback('exportYmap', function(data, cb)
    local count = #placedObjects
    local entitiesToExport = table.create(count, 0)
    for i = 1, count do
        local ent = placedObjects[i]
        if DoesEntityExist(ent.handle) then
            local c = GetEntityCoords(ent.handle)
            local r = GetEntityRotation(ent.handle, 2)
            local qx, qy, qz, qw = GetEntityQuaternion(ent.handle)
            ent.coords = { x = c.x, y = c.y, z = c.z }
            ent.rot = { x = r.x, y = r.y, z = r.z }
            ent.quat = { x = qx, y = qy, z = qz, w = qw }
        end
        entitiesToExport[i] = {
            model = ent.model,
            coords = ent.coords,
            rot = ent.rot,
            quat = ent.quat,
            lodDist = ent.lodDist or Config.DefaultLodDist,
            flags = ent.flags or Config.DefaultFlags
        }
    end

    lib.callback('nxs_ymapbuilder:server:exportYmap', false, function(result)
        cb(result)
    end, {
        name = data.name or 'mapping',
        entities = entitiesToExport
    })
end)

-- Nettoyage si la ressource s'arrête
AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end
    for i = 1, #placedObjects do
        local ent = placedObjects[i]
        if DoesEntityExist(ent.handle) then
            DeleteEntity(ent.handle)
        end
    end
    local playerPed = PlayerPedId()
    SetEntityVisible(playerPed, true, false)
    FreezeEntityPosition(playerPed, false)
end)
