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
local gizmoConfirmed = false
local isDeleteTriggered = false
local isCancelTriggered = false
local isEnterTriggered = false
local isAltPressed = false
local isRMBPressed = false
local gizmoActivationTime = 0
local isFreecamMode = false
local camMoveSpeed = 0.15

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

local sharedMatrixBuffer = dataview.ArrayBuffer(60)

local function makeEntityMatrix(entity)
    local f, r, u, a = GetEntityMatrix(entity)

    sharedMatrixBuffer:SetFloat32(0, r[1])
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

    return sharedMatrixBuffer
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

    if isSnapEnabled and currentMode == 'Rotate' then
        local r = GetEntityRotation(entity, 2)
        SetEntityRotation(entity, roundToStep(r.x, snapRotStep), roundToStep(r.y, snapRotStep), roundToStep(r.z, snapRotStep), 2, true)
    end
end

local function GetCamDirections(cam)
    local rot = GetCamRot(cam, 2)
    local tX = math.rad(rot.x)
    local tZ = math.rad(rot.z)
    local num = math.abs(math.cos(tX))
    
    local forward = vector3(-math.sin(tZ) * num, math.cos(tZ) * num, math.sin(tX))
    local right = vector3(math.cos(tZ), math.sin(tZ), 0.0)
    local up = vector3(0.0, 0.0, 1.0)
    
    return forward, right, up
end

local function RaycastForProp(cam)
    local camCoords = GetCamCoord(cam)
    local mouseX = GetControlNormal(0, 239)
    local mouseY = GetControlNormal(0, 240)
    local camForward, camRight, camUp = GetCamDirections(cam)
    local dir = camForward

    if mouseX and mouseY and (mouseX > 0.01 or mouseY > 0.01) then
        local fov = GetCamFov(cam)
        local aspect = GetAspectRatio(true)
        local radFov = math.rad(fov)
        local tanFov = math.tan(radFov / 2)

        local screenX = (mouseX - 0.5) * 2.0
        local screenY = (mouseY - 0.5) * 2.0

        local rightVec = camRight * (screenX * tanFov * aspect)
        local upVec = camUp * (-screenY * tanFov)
        local rawDir = camForward + rightVec + upVec
        local len = #(rawDir)
        if len > 0 then
            dir = rawDir / len
        end
    end

    local dest = camCoords + (dir * 120.0)
    local ray = StartShapeTestRay(camCoords.x, camCoords.y, camCoords.z, dest.x, dest.y, dest.z, 16, currentEntity or 0, 0)
    local _, hit, hitCoords, _, entityHit = GetShapeTestResult(ray)

    if hit and entityHit ~= 0 and DoesEntityExist(entityHit) then
        return entityHit, hitCoords
    end

    local rayWorld = StartShapeTestRay(camCoords.x, camCoords.y, camCoords.z, dest.x, dest.y, dest.z, 1 + 16, currentEntity or 0, 0)
    local _, hitW, hitCoordsW, _, entityHitW = GetShapeTestResult(rayWorld)

    if hitW and entityHitW ~= 0 and DoesEntityExist(entityHitW) then
        return entityHitW, hitCoordsW
    end

    return nil, (hitW and hitCoordsW or hitCoords)
end

local function PickPlacedPropUnderMouse(cam)
    local hitEnt, hitCoords = RaycastForProp(cam)
    local allPlaced = GetPlacedObjects and GetPlacedObjects() or (placedObjects or {})

    -- 1. Si hitEnt direct : vérifier UNIQUEMENT si c'est l'un de nos props posés
    if hitEnt and DoesEntityExist(hitEnt) then
        for i = 1, #allPlaced do
            if allPlaced[i] and allPlaced[i].handle == hitEnt then
                return hitEnt, allPlaced[i]
            end
        end
    end

    -- 2. Si hitCoords, trouver le prop posé le plus proche dans un rayon de 2.5m
    if hitCoords and hitCoords.x ~= 0.0 then
        local nearest = nil
        local minDist = 2.5
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
        return LeaveCursorMode()
    end

    EnterCursorMode()
    isCursorActive = true
    currentEntity = entity

    if currentEntity and DoesEntityExist(currentEntity) then
        SetEntityDrawOutline(currentEntity, true)
        SetEntityDrawOutlineColor(0, 180, 255, 255)
    end
    
    local playerPed = PlayerPedId()
    FreezeEntityPosition(playerPed, true)
    SetEntityVisible(playerPed, false, false)
    SetEntityCollision(playerPed, false, false)

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

    local initRot = GetCamRot(cam, 2)
    local camYaw = initRot.z
    local camPitch = initRot.x
    local rmbLastX = nil
    local rmbLastY = nil

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
            description = 'Prop dupliqué avec ALT !',
            type = 'success'
        })

        dragStartCoords = GetEntityCoords(currentEntity)
        dragStartRot = GetEntityRotation(currentEntity, 2)

        CreateThread(function()
            Wait(400)
            isDuplicatingCooldown = false
        end)
    end
    
    while gizmoEnabled do
        Wait(0)

        -- Mettre à jour le focus de streaming GTA V sur la caméra sans déplacer le ped
        local currentCamCoords = GetCamCoord(cam)
        SetFocusPosAndVel(currentCamCoords.x, currentCamCoords.y, currentCamCoords.z, 0.0, 0.0, 0.0)

        -- Désactiver les actions conflictuelles dès le début de chaque frame
        DisableControlAction(0, 1, true)   -- Look LR
        DisableControlAction(0, 2, true)   -- Look UD
        DisableControlAction(0, 21, true)  -- LSHIFT
        DisableControlAction(0, 22, true)  -- SPACE (Jump)
        DisableControlAction(0, 24, true)  -- Attack (LMB)
        DisableControlAction(0, 25, true)  -- Aim (RMB)
        DisableControlAction(2, 25, true)  -- Aim Frontend (RMB)
        DisableControlAction(0, 26, true)  -- Look Behind
        DisableControlAction(0, 68, true)  -- Veh Aim (RMB)
        DisableControlAction(0, 70, true)  -- Veh Attack (RMB)
        DisableControlAction(0, 238, true) -- Cursor Cancel (RMB)
        DisableControlAction(2, 238, true) -- Cursor Cancel Frontend (RMB)
        DisableControlAction(0, 172, true) -- Flèche Haut
        DisableControlAction(0, 173, true) -- Flèche Bas
        DisableControlAction(0, 174, true) -- Flèche Gauche
        DisableControlAction(0, 175, true) -- Flèche Droite
        DisableControlAction(0, 140, true) -- Melee
        DisableControlAction(0, 30, true)
        DisableControlAction(0, 31, true)
        DisableControlAction(0, 32, true)
        DisableControlAction(0, 33, true)
        DisableControlAction(0, 34, true)
        DisableControlAction(0, 35, true)
        DisableControlAction(0, 19, true)  -- LALT
        DisableControlAction(0, 36, true)  -- LCTRL
        DisableControlAction(0, 29, true)  -- B
        DisableControlAction(0, 200, true) -- ESCAPE
        DisableControlAction(0, 199, true) -- Pause alternate
        DisableControlAction(0, 177, true) -- Backspace
        DisableControlAction(0, 178, true) -- Delete
        DisablePlayerFiring(playerPed, true)

        -- Touche ESPACE : Basculer entre Caméra Libre (Freecam) et Mode Gizmo (Curseur)
        if (IsDisabledControlJustPressed(0, 22) or IsControlJustPressed(0, 22)) and (GetGameTimer() - gizmoActivationTime) > 200 then
            isFreecamMode = not isFreecamMode
            if isFreecamMode then
                if isCursorActive then
                    LeaveCursorMode()
                    isCursorActive = false
                end
                PlaySoundFrontend(-1, "SELECT", "HUD_FRONTEND_DEFAULT_SOUNDSET", true)
            else
                if not isCursorActive then
                    EnterCursorMode()
                    isCursorActive = true
                end
                PlaySoundFrontend(-1, "CANCEL", "HUD_FRONTEND_DEFAULT_SOUNDSET", true)
            end
        end

        -- Détection clic gauche (manipulation / sélection de prop)
        local isLMBDown = isGizmoSelectPressed or
                          IsDisabledControlPressed(0, 24) or IsControlPressed(0, 24) or
                          IsDisabledControlPressed(0, 237) or IsControlPressed(0, 237) or
                          IsDisabledControlPressed(2, 237) or IsControlPressed(2, 237)
        local isLMBJustPressed = IsDisabledControlJustPressed(0, 24) or IsControlJustPressed(0, 24) or
                                 IsDisabledControlJustPressed(0, 237) or IsControlJustPressed(0, 237) or
                                 IsDisabledControlJustPressed(2, 237) or IsControlJustPressed(2, 237)
        local isHoldingShift = IsDisabledControlPressed(0, 21) or IsControlPressed(0, 21)
        local isShiftJustPressed = IsDisabledControlJustPressed(0, 21) or IsControlJustPressed(0, 21)

        -- Rotation caméra avec le clic droit (RMB / INPUT_AIM / INPUT_CURSOR_CANCEL)
        local isHoldingRMB = not isLMBDown and (
            isRMBPressed or
            IsDisabledControlPressed(0, 25) or IsControlPressed(0, 25) or
            IsDisabledControlPressed(2, 25) or IsControlPressed(2, 25) or
            IsDisabledControlPressed(0, 238) or IsControlPressed(0, 238) or
            IsDisabledControlPressed(2, 238) or IsControlPressed(2, 238)
        )

        -- Activer la vue libre soit en Mode Freecam soit par maintien du Clic Droit
        local isInFreeLook = isFreecamMode or isHoldingRMB

        if isInFreeLook then
            if isCursorActive then
                LeaveCursorMode()
                isCursorActive = false
            end

            -- Molette de la souris : Ajuster la vitesse de vol de la Freecam
            if IsDisabledControlJustPressed(0, 241) or IsControlJustPressed(0, 241) or IsDisabledControlJustPressed(0, 15) then
                camMoveSpeed = math.min(2.0, camMoveSpeed + 0.04)
            elseif IsDisabledControlJustPressed(0, 242) or IsControlJustPressed(0, 242) or IsDisabledControlJustPressed(0, 16) then
                camMoveSpeed = math.max(0.02, camMoveSpeed - 0.04)
            end

            -- 1. Rotation de la caméra à la souris (Look LR / UD)
            local lookX = GetDisabledControlNormal(0, 1)
            local lookY = GetDisabledControlNormal(0, 2)
            if lookX == 0.0 then lookX = GetControlNormal(0, 1) end
            if lookY == 0.0 then lookY = GetControlNormal(0, 2) end

            local rotDeltaX = 0.0
            local rotDeltaY = 0.0

            if math.abs(lookX) > 0.0001 or math.abs(lookY) > 0.0001 then
                rotDeltaX = lookX * 8.0
                rotDeltaY = lookY * 8.0
            else
                -- 2. Déplacement relatif du curseur si les look controls sont à 0
                local curX = GetControlNormal(0, 239)
                local curY = GetControlNormal(0, 240)
                if curX == 0.0 then curX = GetDisabledControlNormal(0, 239) end
                if curY == 0.0 then curY = GetDisabledControlNormal(0, 240) end
                if curX == 0.0 then curX = GetControlNormal(2, 239) end
                if curY == 0.0 then curY = GetControlNormal(2, 240) end

                if curX ~= 0.0 and curY ~= 0.0 then
                    if rmbLastX and rmbLastY then
                        rotDeltaX = (curX - rmbLastX) * 160.0
                        rotDeltaY = (curY - rmbLastY) * 160.0
                    end
                    rmbLastX = curX
                    rmbLastY = curY
                end
            end

            if math.abs(rotDeltaX) > 0.0001 or math.abs(rotDeltaY) > 0.0001 then
                camYaw = camYaw - rotDeltaX
                camPitch = camPitch - rotDeltaY
                if camPitch > 85.0 then camPitch = 85.0 end
                if camPitch < -85.0 then camPitch = -85.0 end
                SetCamRot(cam, camPitch, 0.0, camYaw, 2)
            end
        else
            rmbLastX = nil
            rmbLastY = nil
            if not isCursorActive then
                EnterCursorMode()
                isCursorActive = true
            end
        end

        -- Rotation caméra au clavier via les flèches directionnelles
        if IsDisabledControlPressed(0, 174) or IsControlPressed(0, 174) then -- Flèche Gauche
            camYaw = camYaw + 1.2
            SetCamRot(cam, camPitch, 0.0, camYaw, 2)
        end
        if IsDisabledControlPressed(0, 175) or IsControlPressed(0, 175) then -- Flèche Droite
            camYaw = camYaw - 1.2
            SetCamRot(cam, camPitch, 0.0, camYaw, 2)
        end
        if IsDisabledControlPressed(0, 172) or IsControlPressed(0, 172) then -- Flèche Haut
            camPitch = math.min(85.0, camPitch + 1.0)
            SetCamRot(cam, camPitch, 0.0, camYaw, 2)
        end
        if IsDisabledControlPressed(0, 173) or IsControlPressed(0, 173) then -- Flèche Bas
            camPitch = math.max(-85.0, camPitch - 1.0)
            SetCamRot(cam, camPitch, 0.0, camYaw, 2)
        end

        -- Déplacement caméra (ZQSD / WASD / A/E)
        local isMovingCam = IsDisabledControlPressed(0, 32) or IsDisabledControlPressed(0, 33)
                         or IsDisabledControlPressed(0, 34) or IsDisabledControlPressed(0, 35)
                         or IsDisabledControlPressed(0, 51) or IsDisabledControlPressed(0, 52)

        if isMovingCam then
            local currentSpeed = camMoveSpeed
            if isHoldingShift and not isDragging then
                currentSpeed = currentSpeed * 2.5 -- Sprint rapide
            elseif (isHoldingAlt or IsDisabledControlPressed(0, 19)) and not isDragging then
                currentSpeed = currentSpeed * 0.3 -- Déplacement lent et précis
            end

            local camForward, camRight, camUp = GetCamDirections(cam)
            local camC = GetCamCoord(cam)

            if IsDisabledControlPressed(0, 32) then camC = camC + camForward * currentSpeed end
            if IsDisabledControlPressed(0, 33) then camC = camC - camForward * currentSpeed end
            if IsDisabledControlPressed(0, 34) then camC = camC - camRight * currentSpeed end
            if IsDisabledControlPressed(0, 35) then camC = camC + camRight * currentSpeed end
            if IsDisabledControlPressed(0, 51) then camC = camC + camUp * currentSpeed end
            if IsDisabledControlPressed(0, 52) then camC = camC - camUp * currentSpeed end

            SetCamCoord(cam, camC.x, camC.y, camC.z)
        end

        -- Touche ÉCHAP : Quitter l'Éditeur / Caméra libre
        if (IsDisabledControlJustPressed(0, 200) or IsDisabledControlJustPressed(0, 199) or IsControlJustPressed(0, 200) or IsControlJustPressed(0, 199)) and (GetGameTimer() - gizmoActivationTime) > 300 then
            SetPauseMenuActive(false)
            gizmoEnabled = false
            break
        end

        -- Touche ENTRÉE : Valider le placement du prop et quitter le Gizmo (uniquement touche clavier Entrée)
        if isEnterTriggered and (GetGameTimer() - gizmoActivationTime) > 300 then
            isEnterTriggered = false
            gizmoConfirmed = true
            gizmoEnabled = false
            break
        end

        -- Touche EFFACER / SUPPRIMER (Touches clavier Suppr ou Retour arrière)
        -- Ne pose pas le prop, le supprime et réouvre le menu
        local isErasePressed = isDeleteTriggered or isCancelTriggered or 
                               IsDisabledControlJustPressed(0, 178) or IsControlJustPressed(0, 178)

        if isErasePressed and (GetGameTimer() - gizmoActivationTime) > 200 then
            isDeleteTriggered = false
            isCancelTriggered = false
            gizmoCancelled = true

            local delModel = currentModelName
            if currentEntity and DoesEntityExist(currentEntity) then
                local delHandle = currentEntity
                if DeletePlacedPropByHandle then
                    DeletePlacedPropByHandle(delHandle, true)
                else
                    if DoesEntityExist(delHandle) then DeleteEntity(delHandle) end
                end
                currentEntity = nil
                currentModelName = nil
            end
            isDragging = false

            PlaySoundFrontend(-1, "CANCEL", "HUD_FRONTEND_DEFAULT_SOUNDSET", true)
            lib.notify({
                title = 'YMAP Builder',
                description = delModel and ('Prop "%s" effacé. Retour au menu.'):format(tostring(delModel)) or 'Placement annulé. Retour au menu.',
                type = 'inform'
            })

            gizmoEnabled = false
            break
        end

        -- Détection ALT pour duplication (ou MAJ / CTRL comme secours)
        local isHoldingAlt = isAltPressed or IsDisabledControlPressed(0, 19) or IsControlPressed(0, 19)
        local isAltJustPressed = IsDisabledControlJustPressed(0, 19) or IsControlJustPressed(0, 19)

        local isDuplicateKeyHeld = isHoldingAlt or isHoldingShift or IsDisabledControlPressed(0, 36) or IsControlPressed(0, 36)
        local isDuplicateKeyJustPressed = isAltJustPressed or isShiftJustPressed or IsDisabledControlJustPressed(0, 36) or IsControlJustPressed(0, 36)

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
            end
        end

        -- Manipulation du prop sélectionné avec DrawGizmo (actif en mode Gizmo)
        local changedNative = false
        if not isFreecamMode and currentEntity and DoesEntityExist(currentEntity) then
            local matrixBuffer = makeEntityMatrix(currentEntity)
            changedNative = Citizen.InvokeNative(0xEB2EDCA2, matrixBuffer:Buffer(), 'Editor1', Citizen.ReturnResultAnyway())

            if changedNative then
                applyEntityMatrix(currentEntity, matrixBuffer)

                if not isDragging then
                    isDragging = true
                    hasDuplicatedThisDrag = false
                    dragStartCoords = GetEntityCoords(currentEntity)
                    dragStartRot = GetEntityRotation(currentEntity, 2)
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

        -- SÉLECTION D'UN AUTRE PROP PAR CLIC GAUCHE DANS LE MONDE (actif en mode Gizmo)
        -- Si l'utilisateur clique (sans glisser les flèches du Gizmo) et ne maintient pas le clic droit
        if not isFreecamMode and isLMBJustPressed and not changedNative and not isHoldingRMB then
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
    
    if isCursorActive then
        LeaveCursorMode()
    end
    isCursorActive = false

    ClearFocus()
    RenderScriptCams(false, true, 400, true, true)
    DestroyCam(cam, false)
    currentCam = nil
    FreezeEntityPosition(playerPed, false)
    SetEntityCollision(playerPed, true, true)
    SetEntityVisible(playerPed, true, false)

    if currentEntity and DoesEntityExist(currentEntity) then
        SetEntityDrawOutline(currentEntity, false)
        if UpdatePlacedObjectTransform then UpdatePlacedObjectTransform(currentEntity) end
    end

    gizmoEnabled = false
    currentEntity = nil
end

local function textUILoop()
    CreateThread(function()
        while gizmoEnabled do
            Wait(250)

            if isFreecamMode then
                lib.showTextUI(
                    '**MODE CAMÉRA LIBRE (FREECAM)**  \n' ..
                    ('Vitesse de vol : **%.2f** (Molette Souris)  \n\n'):format(camMoveSpeed) ..
                    '**[Souris]** - **Orienter la vue à 360°**  \n' ..
                    '**[ZQSD]** - **Voler dans la scène**  \n' ..
                    '**[A / E]** - Monter / Descendre  \n' ..
                    '**[MAJ]** - Accélérer | **[ALT]** - Ralentir  \n' ..
                    '**[ESPACE]** - **Passer en Mode Gizmo (Manipuler)**  \n' ..
                    '**[ENTRÉE]** - **Valider la position**  \n' ..
                    '**[EFFACER / SUPPR]** - **Annuler & Menu**  \n' ..
                    '**[ÉCHAP]** - **Quitter**'
                )
            elseif currentEntity and DoesEntityExist(currentEntity) then
                local coords = GetEntityCoords(currentEntity)
                local rot = GetEntityRotation(currentEntity, 2)

                lib.showTextUI(
                    '**MODE GIZMO 3D (MANIPULATION)**  \n' ..
                    ('Mode: **%s** | Espace: **%s** | Snap: **%s**  \n'):format(currentMode, isRelative and 'Relatif' or 'Monde', isSnapEnabled and ('OUI (%.1fm/%.0f°)'):format(snapTransStep, snapRotStep) or 'NON') ..
                    ('Pos: `%.2f, %.2f, %.2f`  \n'):format(coords.x, coords.y, coords.z) ..
                    ('Rot: `%.1f, %.1f, %.1f`  \n\n'):format(rot.x, rot.y, rot.z) ..
                    '**[ESPACE]** - **Activer la Caméra Libre (Freecam)**  \n' ..
                    '[Clic Gauche Axes] - Manipuler le prop  \n' ..
                    '**[ALT + Déplacer]** - **Dupliquer le prop**  \n' ..
                    '**[EFFACER / SUPPR]** - **Effacer le prop & Réouvrir le menu**  \n' ..
                    '**[ENTRÉE]** - **Valider la position & Réouvrir le menu**  \n' ..
                    '**[F]** - **Cibler au viseur (Picker)**  \n' ..
                    '**[X]** - Basculer Snap Grille/Angle  \n' ..
                    '[W] - Translation | [R] - Rotation | [Q] - Local/Monde  \n' ..
                    '[G] - Plaquer au sol  \n' ..
                    '[Clic Droit Maintenu] - Pivoter temporairement la vue  \n' ..
                    '[ZQSD] - Déplacer Caméra | [A / E] - Hauteur  \n' ..
                    '**[ÉCHAP]** - **Quitter l\'Éditeur**'
                )
            else
                lib.showTextUI(
                    '**CAMÉRA LIBRE (ÉDITEUR)**  \n' ..
                    'Aucun prop sélectionné.  \n\n' ..
                    '**[ESPACE]** - **Activer la Caméra Libre (Freecam)**  \n' ..
                    '**[Clic Gauche]** - **Cliquer sur un prop pour le sélectionner & bouger**  \n' ..
                    '**[F]** - **Cibler un prop au viseur (Picker)**  \n' ..
                    '**[EFFACER / SUPPR]** - **Réouvrir le menu**  \n' ..
                    '[ZQSD] - Déplacer la caméra | [A / E] - Hauteur  \n' ..
                    '[Clic Droit Maintenu] - Orienter la vue  \n' ..
                    '**[ENTRÉE / ÉCHAP]** - **Quitter l\'Éditeur**'
                )
            end
        end
        lib.hideTextUI()
    end)
end

function useGizmo(entity, modelName)
    gizmoEnabled = true
    gizmoCancelled = false
    gizmoConfirmed = false
    isDeleteTriggered = false
    isCancelTriggered = false
    isEnterTriggered = false
    isAltPressed = false
    isRMBPressed = false
    gizmoActivationTime = GetGameTimer()
    isFreecamMode = false
    camMoveSpeed = 0.15
    currentEntity = entity
    currentModelName = modelName

    textUILoop()
    gizmoLoop(entity)

    SetEntityVisible(PlayerPedId(), true, false)

    if gizmoCancelled or gizmoConfirmed then
        Wait(150)
        if openMainUI then
            openMainUI()
        else
            TriggerEvent('nxs_ymapbuilder:client:openUI')
        end
    end

    return {
        handle = currentEntity,
        cancelled = gizmoCancelled,
        confirmed = gizmoConfirmed
    }
end

exports("useGizmo", useGizmo)
exports("isGizmoActive", function()
    return gizmoEnabled
end)

-- Raccourcis clavier pour le Gizmo
lib.addKeybind({
    name = '_ymapGizmoSelect',
    description = 'Sélectionner l\'axe Gizmo',
    defaultMapper = 'MOUSE_BUTTON',
    defaultKey = 'MOUSE_LEFT',
    onPressed = function()
        if not gizmoEnabled then return end
        isGizmoSelectPressed = true
        ExecuteCommand('+gizmoSelect')
    end,
    onReleased = function()
        isGizmoSelectPressed = false
        ExecuteCommand('-gizmoSelect')
    end
})

lib.addKeybind({
    name = '_ymapGizmoCamRMB',
    description = 'Orienter Caméra (Clic Droit)',
    defaultMapper = 'MOUSE_BUTTON',
    defaultKey = 'MOUSE_RIGHT',
    onPressed = function()
        if not gizmoEnabled then return end
        isRMBPressed = true
    end,
    onReleased = function()
        isRMBPressed = false
    end
})

lib.addKeybind({
    name = '_ymapGizmoTranslation',
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
    name = '_ymapGizmoRotation',
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
    name = '_ymapGizmoLocal',
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
    description = 'Valider modifications Gizmo (Entrée)',
    defaultKey = 'RETURN',
    onReleased = function()
        if not gizmoEnabled then return end
        if (GetGameTimer() - gizmoActivationTime) < 300 then return end
        isEnterTriggered = true
    end
})

lib.addKeybind({
    name = '_ymapGizmoDelete',
    description = 'Effacer / Annuler le prop et réouvrir le menu (Suppr)',
    defaultKey = 'DELETE',
    onReleased = function()
        if not gizmoEnabled then return end
        if (GetGameTimer() - gizmoActivationTime) < 200 then return end
        isDeleteTriggered = true
    end
})

lib.addKeybind({
    name = '_ymapGizmoCancel',
    description = 'Effacer / Annuler le prop et réouvrir le menu (Retour)',
    defaultKey = 'BACK',
    onReleased = function()
        if not gizmoEnabled then return end
        if (GetGameTimer() - gizmoActivationTime) < 200 then return end
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
    name = '_ymapGizmoDuplicateAlt',
    description = 'Maintenir pour dupliquer le prop (Alt)',
    defaultKey = 'LMENU',
    onPressed = function()
        if not gizmoEnabled then return end
        isAltPressed = true
    end,
    onReleased = function()
        isAltPressed = false
    end
})

lib.addKeybind({
    name = '_ymapGizmoSnapGround',
    description = 'Plaquer au sol (Gizmo) [G]',
    defaultKey = 'G',
    onPressed = function()
        if not gizmoEnabled or not currentEntity then return end
        SnapEntityToGroundProperly(currentEntity)
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
