local patches
function buildPuppet(save,pos)
    local playerConfig = root.assetJson("/player.config")
    local humanoidConfig = root.assetJson("/humanoid.config")
    local defaultAM = root.assetJson("/default_actor_movement.config")
    local baseNpcConfig = root.assetJson("/npcs/base.npctype")
    local params = root.assetJson("/pu_scripts/puppetBaseParams.json")
    patches = patches or root.assetJson("/pu_scripts/puppetScriptPatches.json")
    params.identity = save.identity
    local mparams = playerConfig.movementParameters
    for k,v in next, baseNpcConfig.movementParameters do
        -- undo everything in here
        mparams[k] = playerConfig.movementParameters[k] or humanoidConfig[k] or defaultAM[k]
    end
    params.movementParameters = mparams
    
    params.statusControllerSettings = playerConfig.statusControllerSettings
    params.statusControllerSettings.statusProperties = sb.jsonMerge(playerConfig.statusControllerSettings.statusProperties, save.statusController.statusProperties)
    
    -- replace some scripts
    for k,v in next, params.statusControllerSettings.primaryScriptSources do
        if patches[v] then
            params.statusControllerSettings.primaryScriptSources[k] = patches[v]
        end
    end
    table.insert(params.statusControllerSettings.primaryScriptSources,1,"/pu_scripts/puppetStatusPatch_pre.lua")
    
    local out = world.spawnNpc(pos or mcontroller.position(), save.identity.species, "base", 1, nil, params)
    world.callScriptedEntity(out, "setSave", save)
    return out
end
