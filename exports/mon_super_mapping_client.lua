-- Mapping généré par nxs_ymapbuilder (mon_super_mapping)
-- Nombre d'objets: 1
local props = {
    { model = `catreaper`, coords = vector3(1810.358, 3668.558, 33.261), rot = vector3(-0.00, -0.00, -54.70) },
}

CreateThread(function()
    for _, data in ipairs(props) do
        lib.requestModel(data.model)
        local obj = CreateObject(data.model, data.coords.x, data.coords.y, data.coords.z, false, false, false)
        SetEntityRotation(obj, data.rot.x, data.rot.y, data.rot.z, 2, true)
        FreezeEntityPosition(obj, true)
        SetModelAsNoLongerNeeded(data.model)
    end
end)