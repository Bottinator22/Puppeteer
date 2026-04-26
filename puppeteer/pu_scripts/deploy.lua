local oldInit = init
function init()
    local function getPuppeteer()
        -- puppeteer should be at [0,50]
        local puppeteerId = world.entityQuery({-50,0},{50,100},{
            includedTypes={"vehicle"},
            callScript="pu_isPuppeteer"
        })[1]
        if not puppeteerId then
            sb.logInfo("Spawning puppeteer.")
            local params = root.assetJson("/pu_scripts/puppeteerParams.json")
            puppeteerId = world.spawnVehicle("compositerailplatform", {0,50}, params)
        end
        return puppeteerId
    end
    local function relayToPuppeteer(m,l,...)
        if not l then return end
        local puppeteerId = getPuppeteer()
        return world.sendEntityMessage(puppeteerId,m,...):result()
    end
    -- commands for the player to use directly
    message.setHandler("/createPuppet",relayToPuppeteer)
    message.setHandler("/getSave",relayToPuppeteer)
    message.setHandler("/controlPuppet",relayToPuppeteer)
    message.setHandler("/puc",relayToPuppeteer)
    
    -- messages for other mods to integrate with it
    message.setHandler("pu_useSave",relayToPuppeteer)
    message.setHandler("pu_createPuppet",relayToPuppeteer)
    oldInit()
end

local oldUpdate = update 
function update(dt)
    if localAnimator.isPuppet then
        oldUpdate(dt)
        return
    end
    localAnimator.clearDrawables()
    localAnimator.clearLightSources()
    oldUpdate(dt)
    local view = world.clientWindow()
    local min = {view[1]-100,view[2]-100}
    local max = {view[3]+100,view[4]+100}
    local es = world.npcQuery(min,max,{
        callScript="pu_hasDrawables"
    })
    for k,v in next, es do
        world.callScriptedEntity(v, "pu_updateDrawables")
    end
end
