function setupCompanions(companionsData,configs)
    local companions = {}
    local actualCompanions = companionsData.companions
    local playerCompanions = {}
    function playerCompanions.getCompanions(t)
        return actualCompanions[t]
    end
    function playerCompanions.setCompanions(t,a)
        actualCompanions[t] = a
    end
    local companionsConfig = configs.player.companionsConfig
    local companionsConfigT = buildContextConfig(companionsConfig)
    local companionsTables = withCommon({config=companionsConfigT,player=player,playerCompanions=playerCompanions,input=puppetInput})
    local companionsScript = buildContext_strict(companionsConfig,companionsTables,companionsData.scriptStorage,{"init","update","uninit"})
    function companions.init()
        companionsScript.init()
    end
    function companions.update(dt)
        companionsScript.update(dt)
    end
    function companions.uninit()
        companionsScript.uninit()
    end
    function companions.teleportOut()
        companionsScript.teleportOut()
    end
    function companions.canDeploy()
        return companionsScript.canDeploy()
    end
    return companions
end
