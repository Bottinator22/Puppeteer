require "/pu_scripts/puppetBuilder.lua"

function pu_isPuppeteer()
    return true
end
local controlling = nil
local delayedSwapTarget = nil
local delayedSwapTimer = 0
local delayedSwappedFrom = nil
function undoAutoswap()
    if delayedSwappedFrom then
        chat.addMessage("Autoswapping to last non-puppeteer.")
        chat.command(string.format("/swap %s",delayedSwappedFrom))
        delayedSwappedFrom = nil
    end
end
function tryControlPuppet(e)
    world.sendEntityMessage(world.mainPlayer(),"puppeteer_control",e)
    controlling = e
    if e then
        return "Now controlling puppet."
    else
        undoAutoswap()
        return "No longer controlling puppet."
    end
end
function init()
    vehicle.setInteractive(false)
    storage.puppets = storage.puppets or {}
    storage.saves = storage.saves or {}
    local function removeDirectives(n)
        local nn = ""
        local iD = false
        for i=1,#n do
            local c = string.sub(n,i,i)
            if c == "^" then
                iD = true
            end
            if not iD then
                nn = nn..c
            end
            if c == ";" then
                iD = false
            end
        end
        return nn
    end
    local function saveByPartialName(n)
        local sn = string.lower(removeDirectives(n))
        local num = 0
        local out
        for k,v in next, storage.saves do
            if string.sub(string.lower(removeDirectives(v.identity.name)),1,#sn) == sn then
                out = v
                num = num + 1
            end
        end
        if num > 1 then
            -- try again with case sensitivity
            out = nil
            num = 0
            sn = string.lower(removeDirectives(n))
            
            for k,v in next, storage.saves do
                if string.sub(removeDirectives(v.identity.name),1,#sn) == sn then
                    out = v
                    num = num + 1
                end
            end
            
            if num > 1 then
                return num
            else
                return out
            end
        end
        return out
    end
    message.setHandler("/createPuppet", function(_,l,n)
        if not l then return "no" end
        local c = saveByPartialName(n)
        if type(c) == "number" then
            return string.format("There are %d characters with names that fit this. Need to be more specific.",c)
        end
        if not c then
            return "Cannot find a character of that name."
        end
        local pos = world.entityPosition(world.mainPlayer())
        buildPuppet(c,pos)
        return "Spawned a puppet."
    end)
    message.setHandler("/getSave", function(_,l)
        if not l then return "no" end
        local save = world.sendEntityMessage(world.mainPlayer(),"player.save"):result()
        if not save then
            return "Could not get save. Player table is likely not exposed by proxy."
        end
        storage.saves[save.uuid] = save
        return "Saved."
    end)
    message.setHandler("controllerUninit", function(_,l)
        if not l then return "no" end
        -- Sent by the controller (the Puppeteer char)
        controlling = nil
    end)
    message.setHandler("/controlPuppet", function(_,l)
        if not l then return "no" end
        local aim = world.sendEntityMessage(world.mainPlayer(),"player.aimPosition"):result()
        local e = world.npcQuery(aim,2,{
            callScript="pu_isPuppet",
            order="nearest"
        })[1]
        if not e and not controlling then
            return "Could not find puppet to control. Place cursor over puppet."
        end
        if not world.sendEntityMessage(world.mainPlayer(),"isPuppeteer"):result() then
            chat.addMessage("Attempting to auto-swap to puppeteer.")
            delayedSwapTarget = e
            delayedSwapTimer = 0.125
            delayedSwappedFrom = world.entityName(world.mainPlayer())
            chat.command("/swap Puppeteer")
        else
            return tryControlPuppet(e)
        end
    end)
    message.setHandler("/puc", function(_,l,c)
        if not l then return "no" end
        local aim = world.sendEntityMessage(world.mainPlayer(),"player.aimPosition"):result()
        if not aim then
            return "Could not get aim. Player table is likely not exposed by proxy."
        end
        local e = world.npcQuery(aim,2,{
            callScript="pu_isPuppet",
            order="nearest"
        })[1]
        if not e then
            e = controlling
        end
        if not e then
            return "Could not find puppet to command. Place cursor over puppet."
        end
        local split = {}
        for v in string.gmatch(c,"([^ ]+)") do
            table.insert(split, v)
        end
        local command = ""
        for k,v in next, split do
            if k > 1 then
                if k > 2 then
                    command = command.." "
                end
                command = command..v
            end
        end
        return world.sendEntityMessage(e,split[1],command):result()
    end)
    
    message.setHandler("pu_useSave", function(_,l,save)
        if not l then return "no" end
        storage.saves[save.uuid] = save
    end)
    message.setHandler("pu_createPuppet", function(_,l,uuid,pos)
        if not l then return "no" end
        if not storage.saves[uuid] then
            sb.logWarn("pu_createPuppet: Cannot spawn puppet, save not defined!")
            return nil
        end
        
        return buildPuppet(storage.saves[uuid],pos)
    end)
end
function update(dt)
    mcontroller.setPosition({0,50})
    mcontroller.setVelocity({0,0})
    if controlling and not world.entityExists(controlling) then
        undoAutoswap()
        controlling = nil
    end
    if delayedSwapTimer > 0 then
        delayedSwapTimer = delayedSwapTimer - dt
        if delayedSwapTimer <= 0 then
            if not world.sendEntityMessage(world.mainPlayer(),"isPuppeteer"):result() then
                delayedSwappedFrom = nil
                chat.addMessage("Couldn't auto-swap to a puppeteer.\nEither they are not named 'Puppeteer', they lack the tech, or you lack a puppeteer.")
            else
                chat.addMessage(tryControlPuppet(delayedSwapTarget))
            end
        end
    end
end
function applyDamage(damageRequest)
    return {}
end
