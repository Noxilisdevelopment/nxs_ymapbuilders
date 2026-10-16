-- Gizmo 3D pour nxs_ymapbuilder
-- Basé sur les natives FiveM DrawGizmo (0xEB2EDCA2) et ox_lib

local dataview = require 'gizmo.dataview'

local isCursorActive = false
local gizmoEnabled = false
local currentMode = 'Translate'
local isRelative = false
local currentEntity = nil
local currentModelName = nil
local currentCam = nil
local isGizmoSelectPressed = false
local gizmoCancelled = false
local isDeleteTriggered = false
local isCancelTriggered = false
local isValidateTriggered = false
local shouldReopenUI = false
local gizmoActivationTime = 0

local isSnapEnabled = Config.Snap and Config.Snap.DefaultEnabled or false
local snapTransStep = Config.Snap and Config.Snap.TranslationStep or 0.5
local snapRotStep = Config.Snap and Config.Snap.RotationStep or 45.0

local function roundToStep(val, step)
    return math.floor((val / step) + 0.5) * step
end

local function normalize(x, y, z)
    local length = math.sqrt(x * x + y * y + z * z)
    if length == 0 then
        return 0, 0, 0
    end
    return x / length, y / length, z / length
end

local function makeEntityMatrix(entity)
    local f, r, u, a = GetEntityMatrix(entity)
    local view = dataview.ArrayBuffer(60)

    view:SetFloat32(0, r[1])
        :SetFloat32(4, r[2])
        :SetFloat32(8, r[3])
        :SetFloat32(12, 0)
        :SetFloat32(16, f[1])
        :SetFloat32(20, f[2])
        :SetFloat32(24, f[3])
        :SetFloat32(28, 0)
        :SetFloat32(32, u[1])
        :SetFloat32(36, u[2])
        :SetFloat32(40, u[3])
        :SetFloat32(44, 0)
        :SetFloat32(48, a[1])
        :SetFloat32(52, a[2])
        :SetFloat32(56, a[3])
        :SetFloat32(60, 1)

    return view
end

local function applyEntityMatrix(entity, view)
    local x1, y1, z1 = view:GetFloat32(16), view:GetFloat32(20), view:GetFloat32(24)
    local x2, y2, z2 = view:GetFloat32(0), view:GetFloat32(4), view:GetFloat32(8)
    local x3, y3, z3 = view:GetFloat32(32), view:GetFloat32(36), view:GetFloat32(40)
    local tx, ty, tz = view:GetFloat32(48), view:GetFloat32(52), view:GetFloat32(56)

    if isSnapEnabled then
        tx = roundToStep(tx, snapTransStep)
        ty = roundToStep(ty, snapTransStep)
        tz = roundToStep(tz, snapTransStep)
    end

    x1, y1, z1 = normalize(x1, y1, z1)
    x2, y2, z2 = normalize(x2, y2, z2)
    x3, y3, z3 = normalize(x3, y3, z3)

    SetEntityMatrix(entity,
        x1, y1, z1,
        x2, y2, z2,
        x3, y3, z3,
        tx, ty, tz
    )
    SetEntityCoordsNoOffset(entity, tx, ty, tz, false, false, false)

    if isSnapEnabled and currentMode == 'Rotate' then
        local r = GetEntityRotation(entity, 2)
        SetEntityRotation(entity, roundToStep(r.x, snapRotStep), roundToStep(r.y, snapRotStep), roundToStep(r.z, snapRotStep), 2, true)
    end
end

local function GetCamDirections(cam)
    local rot = (cam and DoesCamExist(cam)) and GetCamRot(cam, 2) or GetGameplayCamRot(2)
    local tX = math.rad(rot.x)
    local tZ = math.rad(rot.z)
    local cosX = math.abs(math.cos(tX))
    
    local forward = vector3(-math.sin(tZ) * cosX, math.cos(tZ) * cosX, math.sin(tX))
    local right = vector3(math.cos(tZ), math.sin(tZ), 0.0)
    -- Produit vectoriel exact right x forward pour un vecteur Up orthonormal parfait
    local up = vector3(math.sin(tZ) * math.sin(tX), -math.cos(tZ) * math.sin(tX), cosX)
    
    return forward, right, up
end

local function GetCursorRay(cam, customX, customY)
    local mouseX = customX
    local mouseY = customY

    if not mouseX or not mouseY then
        EnableControlAction(0, 239, true)
        EnableControlAction(0, 240, true)

        mouseX = GetControlNormal(0, 239)
        if not mouseX or mouseX <= 0.0001 then
            mouseX = GetDisabledControlNormal(0, 239)
        end
        mouseY = GetControlNormal(0, 240)
        if not mouseY or mouseY <= 0.0001 then
            mouseY = GetDisabledControlNormal(0, 240)
        end
    end

    if not mouseX or mouseX <= 0.0001 then mouseX = 0.5 end
    if not mouseY or mouseY <= 0.0001 then mouseY = 0.5 end

    -- Utilisation de la native officielle de GTA V pour projeter le pixel écran en 3D
    local worldCoord, normalDir = GetWorldCoordFromScreenCoord(mouseX, mouseY)

    if not worldCoord or not normalDir or #(normalDir) == 0.0 then
        local camCoords = (cam and DoesCamExist(cam)) and GetCamCoord(cam) or GetGameplayCamCoord()
        local camForward, camRight, camUp = GetCamDirections(cam)
        local fov = (cam and DoesCamExist(cam)) and GetCamFov(cam) or GetGameplayCamFov()
        local aspect = GetAspectRatio(true)
        local tanFov = math.tan(math.rad(fov) / 2)

        local screenX = (mouseX - 0.5) * 2.0
        local screenY = (mouseY - 0.5) * 2.0

        local rawDir = camForward + (camRight * (screenX * tanFov * aspect)) + (camUp * (-screenY * tanFov))
        local len = #(rawDir)
        normalDir = len > 0 and (rawDir / len) or camForward
        worldCoord = camCoords
    end

    return worldCoord, normalDir
end

function PickPlacedPropUnderMouse(cam, customX, customY)
    local rayOrigin, rayDir = GetCursorRay(cam, customX, customY)
    local allPlaced = GetPlacedObjects and GetPlacedObjects() or (placedObjects or {})
    if not allPlaced or #allPlaced == 0 then return nil, nil end

    -- 1. Test physique direct StartShapeTestSweptSphere (flag 16 pour objets, puis 287 pour toutes entités)
    local dest = rayOrigin + (rayDir * 120.0)
    local ray = StartShapeTestSweptSphere(rayOrigin.x, rayOrigin.y, rayOrigin.z, dest.x, dest.y, dest.z, 0.15, 16, 0, 0)
    local _, hit, hitCoords, _, entityHit = GetShapeTestResult(ray)

    if not hit or entityHit == 0 or not DoesEntityExist(entityHit) then
        local rayAll = StartShapeTestSweptSphere(rayOrigin.x, rayOrigin.y, rayOrigin.z, dest.x, dest.y, dest.z, 0.2, 287, 0, 0)
        _, hit, hitCoords, _, entityHit = GetShapeTestResult(rayAll)
    end

    if hit and entityHit ~= 0 and DoesEntityExist(entityHit) then
        for i = 1, #allPlaced do
            if allPlaced[i] and allPlaced[i].handle == entityHit then
                return entityHit, allPlaced[i]
            end
        end
    end

    -- 2. Test géométrique 3D précis : intersection rayon - volume englobant de tous nos props posés
    local bestProp = nil
    local bestHandle = nil
    local minHitT = math.huge
    local minRayDist = math.huge

    for i = 1, #allPlaced do
        local p = allPlaced[i]
        if p and p.handle and DoesEntityExist(p.handle) then
            local pCoords = GetEntityCoords(p.handle)
            local model = GetEntityModel(p.handle)
            local minDim, maxDim = GetModelDimensions(model)
            
            -- Centre du volume englobant du prop
            local center = pCoords + ((minDim + maxDim) * 0.5)
            -- Rayon englobant avec marge généreuse pour faciliter le clic à la souris
            local propRadius = math.max(0.65, (#(maxDim - minDim) * 0.5) * 1.3)

            local v = center - rayOrigin
            local t = (v.x * rayDir.x) + (v.y * rayDir.y) + (v.z * rayDir.z)

            if t > 0.1 and t < 120.0 then
                local closestPointOnRay = rayOrigin + (rayDir * t)
                local distToRay = #(center - closestPointOnRay)

                -- Le rayon traverse la boîte/sphère englobante du prop
                if distToRay <= propRadius then
                    if t < minHitT then
                        minHitT = t
                        bestProp = p
                        bestHandle = p.handle
                    end
                elseif distToRay < minRayDist and minHitT == math.huge then
                    minRayDist = distToRay
                    if distToRay < 1.3 then
                        bestProp = p
                        bestHandle = p.handle
                    end
                end
            end
        end
    end

    if bestHandle then
        return bestHandle, bestProp
    end

    -- 3. Fallback : si un point d'impact sol/monde est détecté, prop le plus proche dans un rayon de 0.8m
    if hit and hitCoords and hitCoords.x ~= 0.0 then
        local nearest = nil
        local minDist = 0.8
        for i = 1, #allPlaced do
            local p = allPlaced[i]
            if p and p.handle and DoesEntityExist(p.handle) then
                local c = p.coords and vector3(p.coords.x, p.coords.y, p.coords.z) or GetEntityCoords(p.handle)
                local dist = #(c - hitCoords)
                if dist < minDist then
                    minDist = dist
                    nearest = p
                end
            end
        end
        if nearest then
            return nearest.handle, nearest
        end
    end

    return nil, nil
end

local function gizmoLoop(entity)
    if not gizmoEnabled then
        return
    end

    -- Réamorcer le mode curseur interne de FiveM (Im3D) pour déclencher SetControlBypasses
    for _ = 1, 20 do
        EnterCursorMode()
    end
    isCursorActive = true
    currentEntity = entity
    currentMode = 'Translate'

    CreateThread(function()
        ExecuteCommand('+gizmoTranslation')
        Wait(50)
        ExecuteCommand('-gizmoTranslation')
    end)
    print('^2[YMAP BUILDER - DEBUG]^7 Gizmo 3D démarré | Mode Translation activé (+gizmoTranslation)')

    if currentEntity and DoesEntityExist(currentEntity) then
        SetEntityDrawOutline(currentEntity, true)
        SetEntityDrawOutlineColor(0, 180, 255, 255)
    end
    
    local playerPed = PlayerPedId()
    FreezeEntityPosition(playerPed, true)
    SetEntityVisible(playerPed, false, false)

    local cam = CreateCam("DEFAULT_SCRIPTED_CAMERA", true)
    currentCam = cam
    local pRot = GetEntityRotation(playerPed, 2)
    local pForward = GetEntityForwardVector(playerPed)

    local camCoords
    if currentEntity and DoesEntityExist(currentEntity) then
        local eCoords = GetEntityCoords(currentEntity)
        camCoords = eCoords - (pForward * 2.2) + vector3(0.0, 0.0, 0.7)
    else
        local pCoords = GetEntityCoords(playerPed)
        camCoords = pCoords + vector3(0.0, 0.0, 1.2)
    end

    SetCamCoord(cam, camCoords.x, camCoords.y, camCoords.z)
    SetCamRot(cam, -14.0, 0.0, pRot.z, 2)
    SetCamFov(cam, 55.0)
    SetCamActive(cam, true)
    RenderScriptCams(true, true, 400, true, true)

    local camYaw = pRot.z
    local camPitch = -14.0
    local targetCamYaw = camYaw
    local targetCamPitch = camPitch
    local camVelocity = vector3(0.0, 0.0, 0.0)
    local camBaseSpeed = 0.18

    local dragStartCoords = currentEntity and GetEntityCoords(currentEntity) or nil
    local dragStartRot = currentEntity and GetEntityRotation(currentEntity, 2) or nil
    local isDragging = false
    local hasDuplicatedThisDrag = false
    local isDuplicatingCooldown = false

    local function duplicateCurrentProp()
        if not currentEntity or not DoesEntityExist(currentEntity) then return end
        if isDuplicatingCooldown then return end
        isDuplicatingCooldown = true
        hasDuplicatedThisDrag = true

        local modelHash = type(currentModelName) == 'number' and currentModelName or (currentModelName and joaat(currentModelName) or (DoesEntityExist(currentEntity) and GetEntityModel(currentEntity)))
        local cloneCoords = dragStartCoords or GetEntityCoords(currentEntity)
        local cloneRot = dragStartRot or GetEntityRotation(currentEntity, 2)

        RequestModel(modelHash)
        local waitStart = GetGameTimer()
        while not HasModelLoaded(modelHash) and (GetGameTimer() - waitStart) < 2000 do
            Wait(0)
        end

        local cloneObj = CreateObject(modelHash, cloneCoords.x, cloneCoords.y, cloneCoords.z, false, false, false)
        SetEntityRotation(cloneObj, cloneRot.x, cloneRot.y, cloneRot.z, 2, true)
        FreezeEntityPosition(cloneObj, true)
        SetEntityCollision(cloneObj, true, true)
        SetEntityDrawOutline(cloneObj, false)
        SetModelAsNoLongerNeeded(modelHash)

        local qx, qy, qz, qw = GetEntityQuaternion(cloneObj)
        TriggerEvent('nxs_ymapbuilder:client:onGizmoDuplicate', {
            handle = cloneObj,
            model = currentModelName or modelHash,
            coords = { x = cloneCoords.x, y = cloneCoords.y, z = cloneCoords.z },
            rot = { x = cloneRot.x, y = cloneRot.y, z = cloneRot.z },
            quat = { x = qx, y = qy, z = qz, w = qw },
            lodDist = Config.DefaultLodDist,
            flags = Config.DefaultFlags
        })

        PlaySoundFrontend(-1, "SELECT", "HUD_FRONTEND_DEFAULT_SOUNDSET", true)
        lib.notify({
            title = 'YMAP Builder',
            description = 'Prop dupliqué avec MAJ !',
            type = 'success'
        })

        dragStartCoords = GetEntityCoords(currentEntity)
        dragStartRot = GetEntityRotation(currentEntity, 2)

        CreateThread(function()
            Wait(400)
            isDuplicatingCooldown = false
        end)
    end
    
    local wasLMBDown = false

    -- Fonction pour calculer l'accélération progressive aux extrémités de l'écran
    local function calculateEdgeFactor(val, margin)
        if not val then return 0.0 end
        if val < margin then
            local factor = (margin - val) / margin
            if factor > 1.2 then factor = 1.2 end
            return -(factor * factor) -- Négatif = vers la gauche ou le haut
        elseif val > (1.0 - margin) then
            local factor = (val - (1.0 - margin)) / margin
            if factor > 1.2 then factor = 1.2 end
            return (factor * factor)  -- Positif = vers la droite ou le bas
        end
        return 0.0
    end

    while gizmoEnabled do
        Wait(0)
        
        -- Réglage dynamique de la vitesse de caméra via la molette de la souris (CodeWalker)
        if IsDisabledControlJustPressed(0, 241) or IsControlJustPressed(0, 241) or IsDisabledControlJustPressed(0, 14) or IsControlJustPressed(0, 14) then
            camBaseSpeed = math.min(1.5, camBaseSpeed + 0.03)
        elseif IsDisabledControlJustPressed(0, 242) or IsControlJustPressed(0, 242) or IsDisabledControlJustPressed(0, 15) or IsControlJustPressed(0, 15) then
            camBaseSpeed = math.max(0.03, camBaseSpeed - 0.03)
        end

        -- Rotation caméra fluide avec le clic droit (CodeWalker look around avec lissage)
        local isHoldingRMB = IsDisabledControlPressed(0, 25) or IsControlPressed(0, 25)
        if isHoldingRMB then
            DisableControlAction(0, 1, true)
            DisableControlAction(0, 2, true)

            local mouseX = GetDisabledControlNormal(0, 1)
            if mouseX == 0.0 then mouseX = GetControlNormal(0, 1) end
            local mouseY = GetDisabledControlNormal(0, 2)
            if mouseY == 0.0 then mouseY = GetControlNormal(0, 2) end

            targetCamYaw = targetCamYaw - (mouseX * 7.5)
            targetCamPitch = targetCamPitch - (mouseY * 7.5)
            if targetCamPitch > 85.0 then targetCamPitch = 85.0 end
            if targetCamPitch < -85.0 then targetCamPitch = -85.0 end
            
            -- Interpolation soyeuse de l'orientation
            camYaw = camYaw + (targetCamYaw - camYaw) * 0.40
            camPitch = camPitch + (targetCamPitch - camPitch) * 0.40
            SetCamRot(cam, camPitch, 0.0, camYaw, 2)
        else
            SetMouseCursorActiveThisFrame()
            SetMouseCursorSprite(1)
            EnableControlAction(0, 239, true)
            EnableControlAction(0, 240, true)
            targetCamYaw = camYaw
            targetCamPitch = camPitch
        end

        local isLMBDown = IsDisabledControlPressed(0, 24) or IsControlPressed(0, 24) 
                       or IsDisabledControlPressed(0, 237) or IsControlPressed(0, 237)
                       or IsDisabledControlPressed(0, 142) or IsControlPressed(0, 142)
        local isLMBJustPressed = (isLMBDown and not wasLMBDown)
                              or IsDisabledControlJustPressed(0, 24) or IsControlJustPressed(0, 24) 
                              or IsDisabledControlJustPressed(0, 237) or IsControlJustPressed(0, 237)
                              or IsDisabledControlJustPressed(0, 142) or IsControlJustPressed(0, 142)
        wasLMBDown = isLMBDown
        local isHoldingShift = IsDisabledControlPressed(0, 21) or IsControlPressed(0, 21)
        local isShiftJustPressed = IsDisabledControlJustPressed(0, 21) or IsControlJustPressed(0, 21)

        -- Vélocité cible des contrôles clavier (ZQSD / WASD / Espace / Ctrl / A / E)
        local currentMoveSpeed = isHoldingShift and (camBaseSpeed * 2.5) or camBaseSpeed
        local camForward, camRight, camUp = GetCamDirections(cam)

        local moveInput = vector3(0.0, 0.0, 0.0)
        -- Z (Avance) / S (Recule)
        if IsDisabledControlPressed(0, 32) or IsControlPressed(0, 32) then moveInput = moveInput + camForward end
        if IsDisabledControlPressed(0, 33) or IsControlPressed(0, 33) then moveInput = moveInput - camForward end
        -- Q/A (Gauche) / D (Droite)
        if IsDisabledControlPressed(0, 34) or IsControlPressed(0, 34) then moveInput = moveInput - camRight end
        if IsDisabledControlPressed(0, 35) or IsControlPressed(0, 35) then moveInput = moveInput + camRight end
        -- E ou Espace (Monte verticalement dans le monde)
        if IsDisabledControlPressed(0, 51) or IsControlPressed(0, 51) or IsDisabledControlPressed(0, 22) or IsControlPressed(0, 22) then
            moveInput = moveInput + vector3(0.0, 0.0, 1.0)
        end
        -- A ou Ctrl (Descend verticalement dans le monde)
        if IsDisabledControlPressed(0, 52) or IsControlPressed(0, 52) or IsDisabledControlPressed(0, 36) or IsControlPressed(0, 36) then
            moveInput = moveInput - vector3(0.0, 0.0, 1.0)
        end

        local inputLen = #(moveInput)
        if inputLen > 0.001 then
            moveInput = moveInput / inputLen
        end
        local targetInputVelocity = moveInput * currentMoveSpeed

        -- Désactiver les actions conflictuelles
        DisableControlAction(0, 21, true)  -- LSHIFT
        DisableControlAction(0, 24, true)  -- Attack / LMB
        DisableControlAction(0, 25, true)  -- Aim / RMB
        DisableControlAction(0, 140, true) -- Melee
        DisableControlAction(0, 30, true)
        DisableControlAction(0, 31, true)
        DisableControlAction(0, 32, true)
        DisableControlAction(0, 33, true)
        DisableControlAction(0, 34, true)
        DisableControlAction(0, 35, true)
        DisableControlAction(0, 36, true)  -- LCTRL
        DisableControlAction(0, 29, true)  -- B
        DisableControlAction(0, 200, true) -- ESCAPE
        DisableControlAction(0, 199, true) -- Pause alternate
        DisableControlAction(0, 178, true) -- Delete
        DisablePlayerFiring(playerPed, true)

        -- Quitter l'Éditeur / Caméra libre (Touche ÉCHAP)
        if (IsDisabledControlJustPressed(0, 200) or IsDisabledControlJustPressed(0, 199) or IsControlJustPressed(0, 200) or IsControlJustPressed(0, 199)) and (GetGameTimer() - gizmoActivationTime) > 300 then
            SetPauseMenuActive(false)
            shouldReopenUI = false
            gizmoEnabled = false
            print('^3[YMAP BUILDER - DEBUG]^7 Touche [ÉCHAP] pressée -> Fermeture complète de l\'éditeur')
            break
        end

        -- Valider et Réouvrir direct l'UI des props (Touche ENTRÉE uniquement via keybind, jamais sur un clic souris)
        if isValidateTriggered and (GetGameTimer() - gizmoActivationTime) > 300 then
            isValidateTriggered = false
            shouldReopenUI = true
            gizmoEnabled = false
            print('^2[YMAP BUILDER - DEBUG]^7 Touche [ENTRÉE] pressée -> Validation du prop et réouverture du menu')
            break
        end

        -- Touche SUPPRIMER (Control 178 ou raccourci ox_lib _ymapGizmoDelete)
        if (IsDisabledControlJustPressed(0, 178) or IsControlJustPressed(0, 178) or isDeleteTriggered) and (GetGameTimer() - gizmoActivationTime) > 200 then
            isDeleteTriggered = false
            if currentEntity and DoesEntityExist(currentEntity) then
                local delHandle = currentEntity
                local delModel = currentModelName
                if DeletePlacedPropByHandle then
                    DeletePlacedPropByHandle(delHandle)
                else
                    if DoesEntityExist(delHandle) then DeleteEntity(delHandle) end
                end
                currentEntity = nil
                currentModelName = nil
                isDragging = false
                PlaySoundFrontend(-1, "CANCEL", "HUD_FRONTEND_DEFAULT_SOUNDSET", true)
                lib.notify({
                    title = 'YMAP Builder',
                    description = ('Prop "%s" supprimé. Caméra libre : cliquez sur un autre prop pour le bouger.'):format(tostring(delModel or 'sélectionné')),
                    type = 'inform'
                })
            else
                lib.notify({
                    title = 'YMAP Builder',
                    description = 'Aucun prop sélectionné. Cliquez sur un prop pour le sélectionner.',
                    type = 'inform'
                })
            end
            -- ON NE FAIT PAS DE BREAK ! LE JOUEUR RESTE EN FREECAM !
        end

        -- Touche RETOUR ARRIÈRE (Backspace via ox_lib _ymapGizmoCancel)
        if isCancelTriggered and (GetGameTimer() - gizmoActivationTime) > 300 then
            isCancelTriggered = false
            if currentEntity and DoesEntityExist(currentEntity) then
                SetEntityDrawOutline(currentEntity, false)
                currentEntity = nil
                currentModelName = nil
                isDragging = false
                PlaySoundFrontend(-1, "CANCEL", "HUD_FRONTEND_DEFAULT_SOUNDSET", true)
                lib.notify({ title = 'Éditeur', description = 'Prop désélectionné. Cliquez sur un prop pour le sélectionner.', type = 'inform' })
            else
                gizmoEnabled = false
                break
            end
        end

        -- Détection MAJ Gauche (ou CTRL comme secours)
        local isDuplicateKeyHeld = isHoldingShift or IsDisabledControlPressed(0, 36) or IsControlPressed(0, 36)
        local isDuplicateKeyJustPressed = isShiftJustPressed or IsDisabledControlJustPressed(0, 36) or IsControlJustPressed(0, 36)

        -- Si le clic de manipulation est relâché, réinitialiser l'état du drag
        if not isLMBDown and isDragging then
            isDragging = false
            hasDuplicatedThisDrag = false
            if currentEntity and DoesEntityExist(currentEntity) then
                dragStartCoords = GetEntityCoords(currentEntity)
                dragStartRot = GetEntityRotation(currentEntity, 2)
                if UpdatePlacedObjectTransform then
                    UpdatePlacedObjectTransform(currentEntity)
                end
                print(('^3[YMAP BUILDER - DEBUG]^7 Fin du déplacement | Nouvelles coordonnées : %.2f, %.2f, %.2f'):format(dragStartCoords.x, dragStartCoords.y, dragStartCoords.z))
            end
        end

        -- Manipulation du prop sélectionné avec DrawGizmo
        local changedNative = false
        if currentEntity and DoesEntityExist(currentEntity) then
            local prevCoords = GetEntityCoords(currentEntity)
            local matrixBuffer = makeEntityMatrix(currentEntity)
            changedNative = Citizen.InvokeNative(0xEB2EDCA2, matrixBuffer:Buffer(), 'Editor1', Citizen.ReturnResultAnyway())

            if changedNative then
                applyEntityMatrix(currentEntity, matrixBuffer)

                if not isDragging then
                    isDragging = true
                    hasDuplicatedThisDrag = false
                    dragStartCoords = prevCoords
                    dragStartRot = GetEntityRotation(currentEntity, 2)
                    print('^2[YMAP BUILDER - DEBUG]^7 Flèche Gizmo saisie -> Déplacement en direct du prop #' .. tostring(currentEntity))
                end

                if (isDuplicateKeyHeld and not hasDuplicatedThisDrag) or isDuplicateKeyJustPressed then
                    duplicateCurrentProp()
                end
            else
                if isLMBDown and isDuplicateKeyJustPressed and not isHoldingRMB then
                    duplicateCurrentProp()
                end
            end
        else
            isDragging = false
        end

        -- SUIVI FLUIDE DE CAMÉRA STYLE CODEWALKER (Extrémités de l'écran lors du drag)
        local edgePushVelocity = vector3(0.0, 0.0, 0.0)
        if isDragging and currentEntity and DoesEntityExist(currentEntity) and not isHoldingRMB then
            local propCoords = GetEntityCoords(currentEntity)
            local onScreen, screenX, screenY = GetScreenCoordFromWorldCoord(propCoords.x, propCoords.y, propCoords.z)
            
            local camCoords = GetCamCoord(cam)
            local toProp = propCoords - camCoords
            local forwardDot = (toProp.x * camForward.x) + (toProp.y * camForward.y) + (toProp.z * camForward.z)

            local pFactorX, pFactorY = 0.0, 0.0
            if forwardDot > 0 then
                if onScreen then
                    -- Zone d'extrémité pour le prop : 20% des bords
                    pFactorX = calculateEdgeFactor(screenX, 0.20)
                    pFactorY = calculateEdgeFactor(screenY, 0.20)
                else
                    -- Si le prop sort de l'écran, poussée dans sa direction
                    local rightDot = (toProp.x * camRight.x) + (toProp.y * camRight.y) + (toProp.z * camRight.z)
                    local upDot = (toProp.x * camUp.x) + (toProp.y * camUp.y) + (toProp.z * camUp.z)
                    pFactorX = rightDot > 0 and 1.0 or -1.0
                    pFactorY = upDot > 0 and -1.0 or 1.0
                end
            end

            -- Détecte également si le curseur de la souris atteint le bord pendant la manipulation
            local mouseX = GetControlNormal(0, 239)
            local mouseY = GetControlNormal(0, 240)
            local mFactorX = calculateEdgeFactor(mouseX, 0.08)
            local mFactorY = calculateEdgeFactor(mouseY, 0.08)

            local moveFactorX = (math.abs(pFactorX) > math.abs(mFactorX)) and pFactorX or mFactorX
            local moveFactorY = (math.abs(pFactorY) > math.abs(mFactorY)) and pFactorY or mFactorY

            if math.abs(moveFactorX) > 0.01 or math.abs(moveFactorY) > 0.01 then
                edgePushVelocity = (camRight * moveFactorX - camUp * moveFactorY) * (currentMoveSpeed * 1.1)
            end
        end

        -- PHYSIQUE ET INERTIE DE VOL CODEWALKER UNIFIÉE (Damping / Friction cinématique)
        local totalTargetVelocity = targetInputVelocity + edgePushVelocity

        if #(totalTargetVelocity) > 0.001 then
            -- Accélération progressive et continue
            camVelocity = camVelocity + (totalTargetVelocity - camVelocity) * 0.16
        else
            -- Décélération et friction soyeuse (inertie CodeWalker)
            camVelocity = camVelocity * 0.82
        end

        if #(camVelocity) > 0.0002 then
            local curCam = GetCamCoord(cam)
            SetCamCoord(cam, curCam.x + camVelocity.x, curCam.y + camVelocity.y, curCam.z + camVelocity.z)
        end

        -- SÉLECTION D'UN AUTRE PROP PAR CLIC GAUCHE DANS LE MONDE
        -- Si l'utilisateur clique (sans glisser les flèches du Gizmo) et ne maintient pas le clic droit
        if isLMBJustPressed and not isDragging and not changedNative and not isHoldingRMB then
            local pickedHandle, pickedData = PickPlacedPropUnderMouse(cam)
            if pickedHandle and DoesEntityExist(pickedHandle) then
                if pickedHandle ~= currentEntity then
                    if currentEntity and DoesEntityExist(currentEntity) then
                        SetEntityDrawOutline(currentEntity, false)
                        if UpdatePlacedObjectTransform then UpdatePlacedObjectTransform(currentEntity) end
                    end
                    currentEntity = pickedHandle
                    currentModelName = (pickedData and pickedData.model) or 'prop'
                    SetEntityDrawOutline(currentEntity, true)
                    SetEntityDrawOutlineColor(0, 180, 255, 255)
                    dragStartCoords = GetEntityCoords(currentEntity)
                    dragStartRot = GetEntityRotation(currentEntity, 2)
                    isDragging = false
                    PlaySoundFrontend(-1, "SELECT", "HUD_FRONTEND_DEFAULT_SOUNDSET", true)
                    lib.notify({
                        title = 'Prop Sélectionné',
                        description = ('Prop "%s" sélectionné. Manipulez les axes ou [SUPPR] pour le supprimer.'):format(tostring(currentModelName)),
                        type = 'info'
                    })
                end
            end
        end
    end
    
    isCursorActive = false
    pcall(LeaveCursorMode)

    RenderScriptCams(false, true, 400, true, true)
    DestroyCam(cam, false)
    currentCam = nil
    FreezeEntityPosition(playerPed, false)
    SetEntityVisible(playerPed, true, false)

    if currentEntity and DoesEntityExist(currentEntity) then
        SetEntityDrawOutline(currentEntity, false)
        if UpdatePlacedObjectTransform then UpdatePlacedObjectTransform(currentEntity) end
    end

    gizmoEnabled = false
    currentEntity = nil

    -- Si validé avec ENTRÉE, réouvrir immédiatement l'UI des props
    if shouldReopenUI then
        shouldReopenUI = false
        Wait(50)
        if openMainUI then
            openMainUI()
        else
            TriggerEvent('nxs_ymapbuilder:client:openUI')
        end
    end
end

local function textUILoop()
    CreateThread(function()
        while gizmoEnabled do
            Wait(250)

            if currentEntity and DoesEntityExist(currentEntity) then
                local coords = GetEntityCoords(currentEntity)
                local rot = GetEntityRotation(currentEntity, 2)

                lib.showTextUI(
                    '**MODE GIZMO 3D (ÉDITEUR)**  \n' ..
                    ('Mode: **%s** | Espace: **%s** | Snap: **%s**  \n'):format(currentMode, isRelative and 'Relatif' or 'Monde', isSnapEnabled and ('OUI (%.1fm/%.0f°)'):format(snapTransStep, snapRotStep) or 'NON') ..
                    ('Pos: `%.2f, %.2f, %.2f`  \n'):format(coords.x, coords.y, coords.z) ..
                    ('Rot: `%.1f, %.1f, %.1f`  \n\n'):format(rot.x, rot.y, rot.z) ..
                    '**[ENTRÉE]** - **Valider & Ouvrir le menu des props**  \n' ..
                    '[Clic Gauche Axes] - Manipuler le prop  \n' ..
                    '**[Clic Gauche Prop]** - **Sélectionner un autre prop**  \n' ..
                    '**[MAJ + Flèche]** - **Dupliquer le prop**  \n' ..
                    '**[SUPPR]** - **Supprimer (Reste en caméra libre)**  \n' ..
                    '**[F]** - **Cibler au viseur (Picker)**  \n' ..
                    '**[X]** - Basculer Snap Grille/Angle  \n' ..
                    '[W] - Translation | [R] - Rotation | [Q] - Local/Monde  \n' ..
                    '[LALT] - Plaquer au sol  \n' ..
                    '[ZQSD / Clic Droit] - Déplacer Caméra  \n' ..
                    '[A / E] - Hauteur Caméra  \n' ..
                    '**[ÉCHAP]** - **Fermer l\'Éditeur**'
                )
            else
                lib.showTextUI(
                    '**CAMÉRA LIBRE (ÉDITEUR)**  \n' ..
                    'Aucun prop sélectionné.  \n\n' ..
                    '**[ENTRÉE]** - **Ouvrir le menu des props**  \n' ..
                    '**[Clic Gauche]** - **Cliquer sur un prop pour le sélectionner & bouger**  \n' ..
                    '**[F]** - **Cibler un prop au viseur (Picker)**  \n' ..
                    '[ZQSD] - Déplacer la caméra  \n' ..
                    '[A / E] - Hauteur de la caméra  \n' ..
                    '[Clic Droit] - Orienter la vue  \n' ..
                    '**[ÉCHAP]** - **Fermer l\'Éditeur**'
                )
            end
        end
        lib.hideTextUI()
    end)
end

function useGizmo(entity, modelName)
    gizmoEnabled = true
    gizmoCancelled = false
    isDeleteTriggered = false
    isCancelTriggered = false
    isValidateTriggered = false
    shouldReopenUI = false
    gizmoActivationTime = GetGameTimer()
    currentEntity = entity
    currentModelName = modelName

    -- Forcer la désactivation totale de NUI et libérer l'écran pour le Gizmo 3D
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'forceClose' })

    textUILoop()
    gizmoLoop(entity)

    SetEntityVisible(PlayerPedId(), true, false)

    return {
        handle = currentEntity,
        cancelled = gizmoCancelled
    }
end

exports("useGizmo", useGizmo)
exports("isGizmoActive", function()
    return gizmoEnabled
end)
exports("PickPlacedPropUnderMouse", PickPlacedPropUnderMouse)

function PickPlacedPropAtCoords(cam, customX, customY)
    return PickPlacedPropUnderMouse(cam, customX, customY)
end

-- Keybinding natif du clic gauche pour la saisie et manipulation des flèches Gizmo (ImGuizmo)
RegisterKeyMapping('+gizmoSelect', 'Sélectionner l\'axe Gizmo', 'MOUSE_BUTTON', 'MOUSE_LEFT')
RegisterKeyMapping('+gizmoTranslation', 'Mode Translation Gizmo', 'keyboard', 'W')
RegisterKeyMapping('+gizmoRotation', 'Mode Rotation Gizmo', 'keyboard', 'R')
RegisterKeyMapping('+gizmoLocal', 'Basculer Espace Local/Monde', 'keyboard', 'Q')

lib.addKeybind({
    name = '_ymapGizmoSelect',
    description = 'Sélectionner l\'axe Gizmo',
    defaultMapper = 'MOUSE_BUTTON',
    defaultKey = 'MOUSE_LEFT',
    onPressed = function()
        if gizmoEnabled then
            ExecuteCommand('+gizmoSelect')
        end
    end,
    onReleased = function()
        if gizmoEnabled then
            ExecuteCommand('-gizmoSelect')
        end
    end
})

-- Raccourcis ox_lib pour changer de mode de manipulation (Translation, Rotation, Espace Local/Monde)
lib.addKeybind({
    name = '_ymapGizmoModeTrans',
    description = 'Mode Translation Gizmo',
    defaultKey = 'W',
    onPressed = function()
        if not gizmoEnabled then return end
        currentMode = 'Translate'
        ExecuteCommand('+gizmoTranslation')
    end,
    onReleased = function()
        ExecuteCommand('-gizmoTranslation')
    end
})

lib.addKeybind({
    name = '_ymapGizmoModeRot',
    description = 'Mode Rotation Gizmo',
    defaultKey = 'R',
    onPressed = function()
        if not gizmoEnabled then return end
        currentMode = 'Rotate'
        ExecuteCommand('+gizmoRotation')
    end,
    onReleased = function()
        ExecuteCommand('-gizmoRotation')
    end
})

lib.addKeybind({
    name = '_ymapGizmoModeLocal',
    description = 'Basculer Espace Local/Monde',
    defaultKey = 'Q',
    onPressed = function()
        if not gizmoEnabled then return end
        isRelative = not isRelative
        ExecuteCommand('+gizmoLocal')
    end,
    onReleased = function()
        ExecuteCommand('-gizmoLocal')
    end
})

lib.addKeybind({
    name = '_ymapGizmoClose',
    description = 'Valider et ouvrir le menu des props',
    defaultKey = 'RETURN',
    onPressed = function()
        if not gizmoEnabled then return end
        if (GetGameTimer() - gizmoActivationTime) < 300 then return end
        isValidateTriggered = true
    end,
    onReleased = function()
        if not gizmoEnabled then return end
        if (GetGameTimer() - gizmoActivationTime) < 300 then return end
        isValidateTriggered = true
    end
})

lib.addKeybind({
    name = '_ymapGizmoCloseNumpad',
    description = 'Valider et ouvrir le menu des props (Pavé Num)',
    defaultKey = 'NUMPADENTER',
    onPressed = function()
        if not gizmoEnabled then return end
        if (GetGameTimer() - gizmoActivationTime) < 300 then return end
        isValidateTriggered = true
    end,
    onReleased = function()
        if not gizmoEnabled then return end
        if (GetGameTimer() - gizmoActivationTime) < 300 then return end
        isValidateTriggered = true
    end
})

lib.addKeybind({
    name = '_ymapGizmoDelete',
    description = 'Supprimer le prop sélectionné (Gizmo)',
    defaultKey = 'DELETE',
    onReleased = function()
        if not gizmoEnabled then return end
        if (GetGameTimer() - gizmoActivationTime) < 200 then return end
        isDeleteTriggered = true
    end
})

lib.addKeybind({
    name = '_ymapGizmoCancel',
    description = 'Désélectionner ou quitter',
    defaultKey = 'BACK',
    onReleased = function()
        if not gizmoEnabled then return end
        if (GetGameTimer() - gizmoActivationTime) < 300 then return end
        isCancelTriggered = true
    end
})

function SnapEntityToGroundProperly(entity)
    if not DoesEntityExist(entity) then return end
    local coords = GetEntityCoords(entity)
    local modelHash = GetEntityModel(entity)
    local minDim, maxDim = GetModelDimensions(modelHash)

    -- 1. Raycast vertical vers le bas sur 60 mètres
    local ray = StartShapeTestRay(coords.x, coords.y, coords.z + 5.0, coords.x, coords.y, coords.z - 60.0, 1, entity, 0)
    local _, hit, hitCoords = GetShapeTestResult(ray)

    if hit and hitCoords.z ~= 0.0 then
        -- minDim.z est négatif : soustraire minDim.z place la base exacte de l'objet au sol
        local groundZ = hitCoords.z - minDim.z
        SetEntityCoords(entity, coords.x, coords.y, groundZ, false, false, false, false)
    else
        local foundGround, groundZ = GetGroundZFor_3dCoord(coords.x, coords.y, coords.z + 5.0, false)
        if foundGround then
            SetEntityCoords(entity, coords.x, coords.y, groundZ - minDim.z, false, false, false, false)
        else
            PlaceObjectOnGroundProperly(entity)
        end
    end

    Wait(10)
    PlaceObjectOnGroundProperly(entity)
end

lib.addKeybind({
    name = '_ymapGizmoSnapGround',
    description = 'Plaquer au sol (Gizmo)',
    defaultKey = 'LMENU',
    onPressed = function()
        if not gizmoEnabled or not currentEntity then return end
        local prev = GetEntityCoords(currentEntity)
        SnapEntityToGroundProperly(currentEntity)
        local after = GetEntityCoords(currentEntity)
        local diff = after - prev
        if #(diff) > 0.001 and currentCam then
            local cp = GetCamCoord(currentCam)
            SetCamCoord(currentCam, cp.x + diff.x, cp.y + diff.y, cp.z + diff.z)
        end
    end
})

lib.addKeybind({
    name = '_ymapGizmoSnapToggle',
    description = 'Basculer Snapping Grille/Angle',
    defaultKey = 'X',
    onPressed = function()
        if not gizmoEnabled then return end
        isSnapEnabled = not isSnapEnabled
        PlaySoundFrontend(-1, "SELECT", "HUD_FRONTEND_DEFAULT_SOUNDSET", true)
        lib.notify({
            title = 'Snapping Grille & Angles',
            description = isSnapEnabled and ('Activé (%.2fm / %.0f°)'):format(snapTransStep, snapRotStep) or 'Désactivé',
            type = isSnapEnabled and 'success' or 'inform'
        })
    end
})

lib.addKeybind({
    name = '_ymapGizmoPropPicker',
    description = 'Cibler un prop au viseur (Picker)',
    defaultKey = 'F',
    onPressed = function()
        if not gizmoEnabled or not currentCam then return end
        local pickedHandle, pickedData = PickPlacedPropUnderMouse(currentCam)

        if pickedHandle and DoesEntityExist(pickedHandle) and pickedHandle ~= currentEntity then
            if currentEntity and DoesEntityExist(currentEntity) then
                SetEntityDrawOutline(currentEntity, false)
                if UpdatePlacedObjectTransform then UpdatePlacedObjectTransform(currentEntity) end
            end
            currentEntity = pickedHandle
            currentModelName = (pickedData and pickedData.model) or 'prop'
            SetEntityDrawOutline(currentEntity, true)
            SetEntityDrawOutlineColor(0, 180, 255, 255)

            PlaySoundFrontend(-1, "SELECT", "HUD_FRONTEND_DEFAULT_SOUNDSET", true)
            lib.notify({
                title = 'Prop Picker',
                description = ('Prop "%s" ciblé au viseur.'):format(tostring(currentModelName)),
                type = 'success'
            })
            TriggerEvent('nxs_ymapbuilder:client:onPropTargeted', pickedHandle)
        else
            lib.notify({
                title = 'Prop Picker',
                description = 'Aucun prop posé détecté dans l\'axe de vue.',
                type = 'inform'
            })
        end
    end
})

-- Nettoyage complet si le script est arrêté ou redémarré en plein mode Gizmo
AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end
    gizmoEnabled = false
    isCursorActive = false
    pcall(LeaveCursorMode)
    pcall(function() lib.hideTextUI() end)
    if currentCam and DoesCamExist(currentCam) then
        RenderScriptCams(false, false, 0, true, true)
        DestroyCam(currentCam, false)
        currentCam = nil
    end
    local playerPed = PlayerPedId()
    FreezeEntityPosition(playerPed, false)
    SetEntityVisible(playerPed, true, false)
end)
