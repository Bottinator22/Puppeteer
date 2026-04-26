function setupDeployment(deployment,configs)
    local deploy = {}
    local deployConfig = configs.player.deploymentConfig
    local deployConfigT = buildContextConfig(deployConfig)
    local deployTables = withCommon({config=deployConfigT,player=player,localAnimator=localAnimator,input=puppetInput})
    local deployScript = buildContext_strict(deployConfig,deployTables,deployment.scriptStorage,{"init","update","uninit","canDeploy"})
    function deploy.init()
        deployScript.init()
    end
    function deploy.update(dt)
        deployScript.update(dt)
    end
    function deploy.uninit()
        deployScript.uninit()
    end
    function deploy.teleportOut()
        deployScript.teleportOut()
    end
    function deploy.canDeploy()
        return deployScript.canDeploy()
    end
    return deploy
end
