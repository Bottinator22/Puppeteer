require "/scripts/vec2.lua"
require "/scripts/terra_proxy.lua"
require "/scripts/abysscommand.lua"

function doEffects()
    status.clearEphemeralEffects()
    status.setPersistentEffects("puppeteertech", {
        {stat = "maxHealth", effectiveMultiplier = 20},
        {stat = "invulnerable", amount=1},
        {stat = "statusImmunity", amount=1},
        {stat = "knockbackStunTime", effectiveMultiplier = 0},
        {stat = "knockbackThreshold", effectiveMultiplier = 0},
        {stat = "grit", amount = 1},
        {stat = "breathProtection", amount = 1},
        {stat = "waterImmunity", amount = 1}
    })
end

local controlling

local function resetControl()
    chat.addMessage("Not resetting player nick due to vanilla issues")
    player.setNametag()
    player.setProperty("scc_sounds_enabled",false)
    world.sendEntityMessage(entity.id(),"scc_reset_settings")
end

function init()
    doEffects()
    message.setHandler("isPuppeteer", function(_,l)
        if l then
            return true
        end
    end)
    message.setHandler("puppeteer_control", function(_,l,p)
        if not l then return end
        if controlling then
            world.callScriptedEntity(controlling,"setControlling",false)
        end
        controlling = p
        if p then
            world.callScriptedEntity(p,"setControlling",true)
            local n = world.entityName(p)
            chat.addMessage(string.format("Changing player nick to %s",n))
            chat.command(string.format("/nick %s^reset;^reset;",n))
            player.setNametag("")
        else
            resetControl()
        end
    end)
    message.setHandler("puppeteer_setStatusProperty", function(_,l,k,v)
        if not l then return end
        status.setStatusProperty(k,v)
    end)
end

local special1 = false
local special2 = false
local special3 = false
local lastCommandHeld = false

local commandMode = false

local nullVec = {0,0}

function update(args)
    tech.setParentState("stand")
    
    if #status.activeUniqueStatusEffectSummary() > 0 then
        doEffects()
    end
    
    local toggledCommand = false
    tech.setParentHidden(true)
    if controlling then
        if not world.entityExists(controlling) then
            controlling = nil
            chat.addMessage("Active puppet has died")
            resetControl()
            return
        end
        mcontroller.setPosition(world.entityPosition(controlling))
        mcontroller.setVelocity(nullVec)
        
        if commandMode then
            --[[
            command.update(args)
            local moves = sb.jsonMerge({},args.moves)
            moves.special1 = false
            moves.special2 = false
            moves.special3 = false
            moves.primaryFire = false
            moves.altFire = false
            world.callScriptedEntity(controlling, "setMoves", moves, tech.aimPosition(), "unchanged")]]
            commandMode = false
            command.uninit()
        else
            world.callScriptedEntity(controlling, "setMoves", args.moves, tech.aimPosition(), player.swapSlotItem())
        end
        tech.setToolUsageSuppressed(true)
    else
        local teleBind = args.moves.special2 or input.bindHeld("abysscore","blink")
        if teleBind and not special2 and not commandMode then
            mcontroller.setPosition(tech.aimPosition())
        end
        special2 = teleBind
        if args.moves.special1 and not special1 then
            toggledCommand = true
            if args.moves.run then
                commandMode = not commandMode
                if commandMode then
                    command.init()
                else
                    command.uninit()
                end
            else
                command.togglePause()
            end
        end
        special1 = args.moves.special1
           
        if commandMode then
            command.update(args)
        end
        
        tech.setToolUsageSuppressed(commandMode)
        -- fly
        local speed = args.moves.run and 30 or 10
        local flyVelocity = {0, 0}
        if args.moves["right"] then flyVelocity[1] = speed end
        if args.moves["left"] then flyVelocity[1] = speed * -1 end
        if args.moves["up"] then flyVelocity[2] = speed end
        if args.moves["down"] then flyVelocity[2] = speed * -1 end

        mcontroller.setVelocity(flyVelocity)
        local params = mcontroller.baseParameters()
        mcontroller.controlParameters({
            collisionPoly={{0,0}},
            collisionEnabled=false,
            gravityEnabled=false,
            liquidFriction = params.airFriction,
            liquidBuoyancy = 0,
            liquidImpedance = 0,
            minimumLiquidPercentage=2})
    end
    local cbind = input.bindHeld("abysscore","toggleCommand")
    if not toggleCommand and cbind and not lastCommandHeld and not controlling then
        toggledCommand = true
        if args.moves.run then
            commandMode = not commandMode
            if commandMode then
                command.init()
            else
                command.uninit()
            end
        else
            command.togglePause()
        end
    end
    lastCommandHeld = cbind
end
function uninit()
    if controlling then
        resetControl()
    end
    tech.setToolUsageSuppressed(false)
    tech.setParentHidden(false)
    status.clearPersistentEffects("puppeteertech")
    tech.setParentState()
    local puppeteerId = world.entityQuery({-50,0},{50,100},{
        includedTypes={"vehicle"},
        callScript="pu_isPuppeteer"
    })[1]
    if puppeteerId then
        world.sendEntityMessage(puppeteerId, "controllerUninit")
    end
end
