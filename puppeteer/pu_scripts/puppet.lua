require "/scripts/util.lua"
require "/scripts/terra_vec2ref.lua"
require "/scripts/terra_polyref.lua"
require "/scripts/terra_proxy.lua"
require "/scripts/terra_context.lua"
require "/scripts/terra_subMcontroller.lua"
require "/scripts/terra_dataTypes.lua"
require "/scripts/terra_safeTable.lua"
require "/pu_scripts/saveUtil.lua"
require "/pu_scripts/puppetTechController.lua" 
require "/pu_scripts/puppetDeployment.lua" 
require "/pu_scripts/puppetCompanions.lua" 

-- TODO: equipmentVisibilityMask
-- last 8 bits (least significant bits) are vanilla slots, the first 12 are the extra ones

local function nullFunc() end
placeholderMT = {
    __index = function(t,k)
        return nullFunc
    end
}
local function fillPlaceholders(t,base)
    local mt = getmetatable(base)
    if mt.terra_keys then
        for _,k in next, mt.terra_keys do
            if not t[k] then
                t[k] = nullFunc
            end
        end
    else
        for k,v in next, base do
            if not t[k] then
                t[k] = nullFunc
            end
        end
    end
end

-- modules
local techController
local deployment
local companions

local needsData = true
local save = {}
local inventory = {
    bags=CaseInsensitiveTable(),
    bagSizes=CaseInsensitiveTable(),
    currencies=CaseInsensitiveTable(),
    equipped=CaseInsensitiveTable()
}
local playerProperties = {}
player = {}
mainPlayer = nil
celestial = nil
local mainLocalAnimator = nil

local equipmentVisibilityMask = 0xffffffff

local controlled = false
puppetInput = {}
setmetatable(puppetInput, {__index=function(t,k)
    if controlled then
        return input[k]
    elseif ai then
        return ai.getInputFunc(k)
    else
        return nullFunc
    end
end})
localAnimator = nil
local toMakeSafe = {
    "entity",
    "mcontroller",
    "status",
    "songbook"
}
safeTables = {}
function ensureSafe(t)
    for k,v in next, safeTables do
        if not t[k] then
            t[k] = v
        end
    end
    return t
end

local commonTables = {
    "input",
    "voice",
    "camera",
    "renderer",
    "clipboard",
    "entity",
    "world",
    "status",
    "message"
}
function withCommon(t)
    for _,k in next, commonTables do
        t[k] = t[k] or safeTables[k] or _ENV[k]
    end
    return t
end
local drawables = {}
local lights = {}
local actionBar = {
    selectedGroup=0,
    selectedSlot=nil, -- string if essential, number if not, nil if nothing selected
    groups={},
    essentials=CaseInsensitiveTable(),
    swapSlot=nil
}
-- slot link
-- type: <bagName>
-- location: <slot number>
local configs
local inventoryFilters
local essentialSlots = {"beamAxe","wireTool","paintTool","inspectionTool"}
local armourSlots = {"head","headCosmetic","chest","chestCosmetic","legs","legsCosmetic","back","backCosmetic"}
local handSlots = {
    primary=true,
    alt=true
}
local slotIndexes = {
    head = 0,
    chest = 1,
    legs = 2,
    back = 3,
    headcosmetic = 4,
    chestcosmetic = 5,
    legscosmetic = 6,
    backcosmetic = 7
}
for i=1,12 do
    local sname = string.format("cosmetic%d",i)
    table.insert(armourSlots,sname)
    slotIndexes[sname] = i+7
end
local function slotMask(s)
    local i = slotIndexes[string.lower(s)]
    if not i then
        sb.logWarn(string.format("Can't find the index for slot %s",s))
    end
    return ((equipmentVisibilityMask >> i) & 0x1) > 0
end
local function patchActiveItem(i)
    if not i then return i end
    local itype = root.itemType(i.name)
    if itype ~= "activeitem" then
        return i
    else
        local patchDat = {}
        local ni = {parameters={}}
        local cfg = root.itemConfig(i).config
        if i.parameters.scripts then
            patchDat.hadScriptOverride = true
            ni.parameters.scripts = {table.unpack(i.parameters.scripts)}
        else
            ni.parameters.scripts = cfg.scripts
        end
        table.insert(ni.parameters.scripts,"/pu_scripts/puppetActiveItemPatch_post.lua")
        ni.parameters.pu_patchData = patchDat
        return sb.jsonMerge(i,ni)
    end
end
local function unpatchActiveItem(i)
    if not i then return i end
    local itype = root.itemType(i.name)
    if itype ~= "activeitem" then
        return i
    else
        local patchDat = i.parameters.pu_patchData
        if patchDat.hadScriptOverride then
            table.remove(i.parameters.scripts)
        else
            i.parameters.scripts = nil
        end
        i.parameters.pu_patchData = nil
        return i
    end
end

-- TODO: possibly update essentials or action bar items on them being queried or changed
local lastHeldSlot
local lastHeldGroup
local lastHeld
local function updateSwapSlot()
    if lastHeld == "swapSlot" then
        actionBar.swapSlot = unpatchActiveItem(npc.getItemSlot("primary"))
    end
end
local function updateEssential()
    if lastHeld == "essential" then
        actionBar.essentials[lastHeldSlot] = unpatchActiveItem(npc.getItemSlot("primary"))
    end
end
local function updateLinkItem()
    if lastHeld == "link" then
        local link = actionBar.groups[lastHeldGroup][lastHeldSlot]
        if link.primary then
            inventory.bags[link.primary.type][link.primary.location+1] = unpatchActiveItem(npc.getItemSlot("primary"))
        end
        if link.alt then
            inventory.bags[link.alt.type][link.alt.location+1] = unpatchActiveItem(npc.getItemSlot("alt"))
        end
    end
end
local function updateHeldItems()
    local newHeld = nil
    local newHeldSlot = nil
    local newHeldGroup = nil
    if not techController.toolUsageSuppressed() then
        if actionBar.swapSlot then
            newHeld = "swapSlot"
        elseif actionBar.selectedSlot then
            newHeldSlot = actionBar.selectedSlot
            if type(actionBar.selectedSlot) == "string" then
                newHeld = "essential"
            else
                newHeld = "link"
                newHeldGroup = actionBar.selectedGroup
            end
        end
    end
    if newHeld ~= lastHeld or newHeldSlot ~= lastHeldSlot or newHeldGroup ~= lastHeldGroup then
        -- save old items
        updateSwapSlot()
        updateEssential()
        updateLinkItem()
        
        -- setup new ones
        if newHeld == "swapSlot" then
            npc.setItemSlot("primary",patchActiveItem(actionBar.swapSlot))
            npc.setItemSlot("alt",nil)
        elseif newHeld == "essential" then
            npc.setItemSlot("primary",patchActiveItem(actionBar.essentials[newHeldSlot]))
            npc.setItemSlot("alt",nil)
        elseif newHeld == "link" then
            local link = actionBar.groups[newHeldGroup][newHeldSlot]
            local primary
            local alt
            if link.primary then
                primary = inventory.bags[link.primary.type][link.primary.location+1]
            end
            if link.alt then
                alt = inventory.bags[link.alt.type][link.alt.location+1]
            end
            npc.setItemSlot("primary",patchActiveItem(primary))
            npc.setItemSlot("alt",patchActiveItem(alt))
        else
            npc.setItemSlot("primary",nil)
            npc.setItemSlot("alt",nil)
        end
    end
    lastHeld = newHeld
    lastHeldSlot = newHeldSlot
    lastHeldGroup = newHeldGroup
end
local function itemAllowedInBag(n,i,c)
    sb.logInfo(sb.print(i))
    local t = root.itemType(i)
    local filter = inventoryFilters[n]
    if filter.typeBlacklist and filter.typeBlacklist[t] then
        return false
    end
    if filter.typeWhitelist and not filter.typeWhitelist[t] then
        return false
    end
    local ic = c or itemCompleteConfig(i)
    if filter.categoryBlacklist and filter.categoryBlacklist[t] then
        return false
    end
    if filter.categoryWhitelist and not filter.categoryWhitelist[t] then
        return false
    end
    if filter.tagBlacklist then
        for k,v in next, ic.tags do
            if filter.tagBlacklist[v] then
                return false
            end
        end
    end
    if filter.tagWhitelist then
        for k,v in next, ic.tags do
            if filter.tagWhitelist[v] then
                return true
            end
        end
        return false
    else
        return true
    end
end
local function cleanupInventory()
    for k,v in next, inventory.bags do
        for k2,v2 in pairs(v) do
            if v2 and v2.count <= 0 then
                v[k2] = nil
            end
        end
    end
end
local function addItem(i)
    local ic = itemCompleteConfig(i)
    local stack = nil
    local limit = ic.maxStack or configs.itemDefaults.maxStack
    for k,v in next, inventory.bags do
        if itemAllowedInBag(k,i,ic) then
            for k2,v2 in pairs(v) do
                if v2 and v2.name == name and table.concat(v2.parameters) == table.concat(params) and v2.count + count < limit then
                    stack = {k,k2}
                end
            end
        end
    end
    local id = {}
    if stack then
        id = inventory.bags[stack[1]][stack[2]]
        id.count = id.count + i.count
    else
        id = i
        for k,v in next, inventory.bags do
            if itemAllowedInBag(k,i,ic) and #v < inventory.bagSizes[k] then
                NumMap.insert(v,i)
            end
        end
    end
    return id
end
local function addItemDesc(id)
    if type(id) == "string" then
        return addItem({name=id,count=1,parameters={}})
    else
        return addItem(id)
    end
end
-- finds by name only
local function findItemInInventoryName(name)
    for k,v in next, inventory.bags do
        for k2,v2 in pairs(v) do
            if v2.name == name and v2.count > 0 then
                return k,k2
            end
        end
    end
    return nil
end
local function findItemInInventory(id,excludeCount)
    for k,v in next, inventory.bags do
        for k2,v2 in pairs(v) do
            if itemEq(id,v2,excludeCount) then
                return k,k2
            end
        end
    end
    return nil
end
local function numItemInInventory(i,exact)
    id = fullItemDescriptor(i)
    local c = 0
    for k,v in next, inventory.bags do
        for k2,v2 in pairs(v) do
            if exact then
                if itemEq(id,v2,true) then
                    c = c + v2.count
                end
            else
                if id.name == v2.name then
                    c = c + v2.count
                end
            end
        end
    end
    return c
end
local function takeItems(i,partial,exact)
    local id = fullItemDescriptor(i)
    if not partial then
        if numItemInInventory(id,exact) < id.count then
            return nil
        end
    end
    local c = id.count
    for k,v in next, inventory.bags do
        for k2,v2 in pairs(v) do
            if exact then
                if itemEq(id,v2,true) then
                    local oc = v2.count
                    v2.count = v2.count-c
                    if v2.count < 0 then
                        v2.count = 0
                    end
                    c = c - (oc-v2.count)
                    if c <= 0 then
                        return id
                    end
                end
            else
                if id.name == v2.name then
                    local oc = v2.count
                    v2.count = v2.count-c
                    if v2.count < 0 then
                        v2.count = 0
                    end
                    c = c - (oc-v2.count)
                    if c <= 0 then
                        return id
                    end
                end
            end
        end
    end
    return {name=id.name,count=id.count-c,parameters=id.parameters}
end
-- TODO: patch activeitems to add player table and query for moves

-- TODO: implement the mask
local function updateEquippedSlot(s)
    if slotMask(s) then
        npc.setItemSlot(s,inventory.equipped[s])
    else
        npc.setItemSlot(s,nil)
    end
end
local function updateEquipped()
    for k,v in next, inventory.equipped do
        if slotMask(k) then
            npc.setItemSlot(k,v)
        else
            npc.setItemSlot(k,nil)
        end
    end
end
local function constant(v)
    return function()
        return v
    end
end
local forceDie = false
function kill()
    forceDie = true
end
local patches
local function patched(scriptSource)
    if patches[scriptSource] then
        return patches[scriptSource]
    end
    return scriptSource
end
local displayNametag = true
function init()
    script.setUpdateDelta(1)
    patches = root.assetJson("/pu_scripts/puppetScriptPatches.json")
    
    terra_proxy.setupReceiveMessages("status",status)
    
    mainPlayer = terra_proxy.setupProxy("player",world.mainPlayer())
    celestial = terra_proxy.setupProxy("celestial",world.mainPlayer())
    mainLocalAnimator = terra_proxy.setupProxy("localAnimator",world.mainPlayer())
    for _,v in next, toMakeSafe do
        safeTables[v] = makeSafe(_ENV[v])
    end
    message.setHandler("/suicide", function(_,l)
        if not l then return end
        status.setResource("health",0)
    end)
    message.setHandler("/destroy", function(_,l)
        if not l then return end
        forceDie = true
    end)
    npc.setDamageOnTouch(false)
    npc.setAggressive(true)
    npc.setDisplayNametag(displayNametag)
    npc.disableWornArmor(false)
    npc.setDropPools(jarray())
    npc.setInteractive(false)
    configs = {
        player=root.assetJson("/player.config"),
        itemDefaults=root.assetJson("/items/defaultParameters.config")
    }
    for k,v in next, configs.player.inventory.itemBags do
        inventory.bags[k] = NumMap()
        inventory.bagSizes[k] = v.size
    end
    for i=1,configs.player.inventory.customBarGroups do
        table.insert(actionBar.groups,NumMap())
    end
    inventoryFilters = {}
    for k,v in next, configs.player.inventoryFilters do
        inventoryFilters[k] = {}
        for k2,v2 in next, v do
            inventoryFilters[k][k2] = arrayToSet(v2)
        end
    end
    -- setup player table
    -- oSB edition
    -- TODO: possibly clone input tables just in case
    function player.load(nsave)
        -- can't do that
    end
    function player.save()
        -- TODO
        --return save
    end
    local function warnFunc(name)
        local t = string.format("%s was called",name)
        return function()
            sb.logWarn(t)
        end
    end
    
    function player.actionBarGroup()
        return actionBar.selectedGroup, #actionBar.groups
    end
    function player.setActionBarGroup(n)
        actionBar.selectedGroup = ((n-1)%#actionBar.groups)+1
    end
    function player.selectedActionBarSlot()
        return actionBar.selectedSlot
    end
    function player.setSelectedActionBarSlot(s)
        actionBar.selectedSlot = s
    end
    function player.actionBarSlotLink(s,h)
        local link = actionBar.groups[actionBar.selectedGroup][s][h]
        if link then
            return {link.type,link.location}
        end
    end
    function player.setActionBarSlotLink(s,h,i)
        if i then
            actionBar.groups[actionBar.selectedGroup][s][h] = {location=i[2],type=i[1]}
        else
            actionBar.groups[actionBar.selectedGroup][s][h] = nil
        end
    end
    function player.itemBagSize(n)
        return inventory.bagSizes[n]
    end
    function player.itemAllowedInBag(n,i)
        return itemAllowedInBag(n,i)
    end
    function player.item(slot)
        return inventory.bags[slot[1]][slot[2]+1]
    end
    function player.setItem(slot,i)
        inventory.bags[slot[1]][slot[2]+1] = fullItemDescriptor(i)
    end
    function player.shipUpgrades()
        return save.shipUpgrades
    end
    player.humanoidIdentity = npc.humanoidIdentity
    function player.description()
        return "Some funny looking person"
    end
    local function buildIdentityCallback(n)
        player[n] = function()
            return npc.humanoidIdentity()[n]
        end
    end
    local function buildHairCallback(n)
        player[n] = function()
            local i = npc.humanoidIdentity()
            return i[n.."Group"],i[n.."Type"],i[n.."Directives"]
        end
    end
    buildIdentityCallback("bodyDirectives")
    buildIdentityCallback("emoteDirectives")
    buildIdentityCallback("hairGroup")
    buildIdentityCallback("hairType")
    buildIdentityCallback("hairDirectives")
    buildIdentityCallback("facialHairGroup")
    buildIdentityCallback("facialHairType")
    buildIdentityCallback("facialHairDirectives")
    buildHairCallback("hair")
    buildHairCallback("facialHair")
    buildHairCallback("facialMask")
    buildIdentityCallback("name")
    buildIdentityCallback("species")
    buildIdentityCallback("imagePath")
    buildIdentityCallback("gender")
    function player.personality()
        local identity = npc.humanoidIdentity()
        return {
            idle=identity.personalityIdle,
            armIdle=identity.personalityArmIdle,
            headOffset=identity.personalityHeadOffset,
            armOffset=identity.personalityArmOffset
        }
    end
    function player.favouriteColor()
        return npc.humanoidIdentity().color
    end
    player.setDamageTeam = npc.setDamageTeam
    player.say = npc.say
    player.emote = npc.emote
    player.id = entity.id
    player.uniqueId = entity.uniqueId
    local function passToTech(f)
        player[f] = function(...)
            return techController[f](...)
        end
    end
    passToTech("makeTechAvailable")
    passToTech("makeTechUnavailable")
    passToTech("enableTech")
    passToTech("equipTech")
    passToTech("unequipTech")
    passToTech("enabledTechs")
    passToTech("availableTechs")
    passToTech("equippedTech")
    player.aimPosition = npc.aimPosition
    function player.currency(c)
        return inventory.currencies[c] or 0
    end
    function player.addCurrency(c,a)
        inventory.currencies[c] = (inventory.currencies[c] or 0) + a
    end
    function player.consumeCurrency(c,a)
        local n = (inventory.currencies[c] or 0) - a
        if n < 0 then
            return false
        end
        inventory.currencies[c] = n
        return true
    end
    player.cleanupItems = cleanupInventory
    function player.giveItem(i)
        addItemDesc(i)
    end
    function player.giveEssentialItem(e,i)
        actionBar.essentials[e] = fullItemDescriptor(i)
    end
    function player.essentialItem(e)
        return actionBar.essentials[e]
    end
    function player.removeEssentialItem(e)
        actionBar.essentials[e] = nil
    end
    function player.setEquippedItem(s,i)
        inventory.equipped[s] = fullItemDescriptor(i)
        updateEquippedSlot(s)
    end
    function player.equippedItem(s,i)
        return inventory.equipped[s]
    end
    function player.hasItem(i,e)
        if e then
            return not not findItemInInventory(i,true)
        else
            return not not findItemInInventoryName(i.name or i)
        end
    end
    player.hasCountOfItem = numItemInInventory(i,e)
    player.consumeItem = takeItems
    function player.inventoryTags()
        local tags = {}
        for k,v in next, inventory.bags do
            for k2,v2 in pairs(v) do
                local ic = itemCompleteConfig(v2)
                for _,v3 in next, ic.tags do
                    if tags[v3] then
                        tags[v3] = tags[v3] + v2.count
                    else
                        tags[v3] = v2.count
                    end
                end
            end
        end
        return tags
    end
    function player.itemsWithTag(t)
        local items = {}
        for k,v in next, inventory.bags do
            for k2,v2 in pairs(v) do
                local ic = itemCompleteConfig(v2)
                for _,v3 in next, ic.tags do
                    if v3 == t then
                        table.insert(items,v2)
                        break
                    end
                end
            end
        end
        return items
    end
    function player.consumeTaggedItem(t,tc)
        local c = tc
        for k,v in next, inventory.bags do
            for k2,v2 in pairs(v) do
                local ic = itemCompleteConfig(v2)
                for _,v3 in next, ic.tags do
                    if v3 == t then
                        local oc = v2.count
                        v2.count = v2.count-c
                        if v2.count < 0 then
                            v2.count = 0
                        end
                        c = c - (oc-v2.count)
                        if c <= 0 then
                            return
                        end
                        break
                    end
                end
            end
        end
    end
    function player.hasItemWithParameter(pn,pv)
        for k,v in next, inventory.bags do
            for k2,v2 in pairs(v) do
                if v2.parameters[pn] == pv then
                    return true
                end
            end
        end
        return false
    end
    function player.consumeItemWithParameter(pn,pv,pc)
        local c = pc
        for k,v in next, inventory.bags do
            for k2,v2 in pairs(v) do
                if v2.parameters[pn] == pv then
                    local oc = v2.count
                    v2.count = v2.count-c
                    if v2.count < 0 then
                        v2.count = 0
                    end
                    c = c - (oc-v2.count)
                    if c <= 0 then
                        return
                    end
                end
            end
        end
    end
    function player.getItemWithParameter(pn,pv)
        for k,v in next, inventory.bags do
            for k2,v2 in pairs(v) do
                if v2.parameters[pn] == pv then
                    return v2
                end
            end
        end
    end
    function player.primaryHandItem()
        return unpatchActiveItem(npc.getItemSlot("primary"))
    end
    function player.altHandItem()
        return unpatchActiveItem(npc.getItemSlot("alt"))
    end
    local function tagify(f)
        return function(...)
            local ic = itemCompleteConfig(f(...))
            return ic.tags
        end
    end
    player.primaryHandItemTags = tagify(player.primaryHandItem)
    player.altHandItemTags = tagify(player.altHandItem)
    function player.swapSlotItem()
        updateSwapSlot()
        return actionBar.swapSlot
    end
    function player.setSwapSlotItem(i)
        actionBar.swapSlot = i
        if lastHeld == "swapSlot" then
            npc.setItemSlot("primary",patchActiveItem(actionBar.swapSlot))
        end
    end
    player.worldId = mainPlayer.worldId
    player.serverUuid = entity.uniqueId
    player.ownShipWorldId = mainPlayer.ownShipWorldId
    function player.interact(iType, cfg, src)
        -- TODO: open with puppet inventory instead of puppeteer inventory
        -- ...which necessitates having a puppet inventory in the first place
        if string.lower(iType) == "scriptpane" then
            if type(cfg) == "string" then
                cfg = root.assetJson(cfg)
            end
            local nscripts = {table.unpack(cfg.scripts)}
            table.insert(nscripts,"/pu_scripts/puppetInterfacePatch_post.lua")
            cfg = sb.jsonMerge(cfg,{
                scripts=nscripts,
                pu_puppetId=entity.id()
            })
        end
        mainPlayer.interact(iType,cfg,src)
    end
    player.lounge = npc.setLounging
    player.isLounging = npc.isLounging
    player.loungingIn = npc.loungingIn
    player.stopLounging = npc.resetLounging
    player.playTime = constant(0)
    player.introComplete = constant(true)
    -- TODO: possibly implement player.warp
    local function passToDeploy(f)
        player[f] = function(...)
            return deployment[f](...)
        end
    end
    passToDeploy("canDeploy")
    player.isDeployed = constant(false)
    function player.getProperty(p,d)
        if playerProperties[p] == nil then
            return d
        end
        return playerProperties[p]
    end
    function player.setProperty(p,v)
        playerProperties[p] = v
    end
    function player.interactRadius()
        return 0
    end
    function player.nametag()
        if displayNametag then
            return npc.humanoidIdentity().name
        else
            return ""
        end
    end
    function player.setNametag(n)
        displayNametag = (not n) or #n > 0
        npc.setDisplayNametag(displayNametag)
    end
    
    -- I'm probably not gonna implement half the functions due to npc limitations and otherwise making no sense to do so
    fillPlaceholders(player,mainPlayer)
    terra_proxy.setupReceiveMessages("player",player)
    
    localAnimator = {
        addDrawable=function(d,layer)
            table.insert(drawables, {drawable=d,layer=layer})
        end,
        clearDrawables=function()
            table.clear(drawables)
        end,
        addLightSource=function(l)
            table.insert(lights, {light=l})
        end,
        clearLightSources=function()
            table.clear(lights)
        end,
        isPuppet=true
    }
    setmetatable(localAnimator, {
        __index=mainLocalAnimator
    })
    
    mcontroller.setAutoClearControls(true)
    if storage.save then
        setSave(storage.save)
    end
end

local propsToPort = {
    "scc_sounds_enabled",
    "scc_sounds_whisper_enabled",
    "scc_sound_pitch",
    "scc_charactervoice_custom",
    "scc_sound_species",
    "icc_custom_portrait",
    "icc_custom_portrait_selected",
    "scc_custom_frame_selected",
    "icc_portrait_settings"
}
local statusPropsToPort = {
    "sccSecondSound",
    "sccThirdSound",
    "sccFourthSound"
}
function updatePuppeteerData()
    if not world.sendEntityMessage(mainPlayer.id(),"isPuppeteer"):result() then
        -- do NOT change non-puppeteer properties
        return
    end
    local changed = false
    for _,v in next, propsToPort do
        if player.getProperty(v) ~= mainPlayer.getProperty(v) then
            mainPlayer.setProperty(v,player.getProperty(v))
            changed = true
        end
    end
    for _,k in next, statusPropsToPort do
        local v = status.statusProperty(k)
        world.sendEntityMessage(mainPlayer.id(),"puppeteer_setStatusProperty",k,v)
    end
    if changed then
        world.sendEntityMessage(mainPlayer.id(),"scc_reset_settings")
    end
end

local bannedEffects={
    starchatdots=true
}
function filterEffects(peffects)
    local out = {}
    for k,v in next, peffects do
        if type(v) == "string" then
            if not bannedEffects[v] then
                table.insert(out,v)
            end
        elseif type(v) == "table" then
            if v.effect and bannedEffects[v.effect] then
            else
                table.insert(out,v)
            end
        end
    end
    return out
end

local genericContexts = {}
function setSave(nsave)
    save = sb.jsonMerge({},nsave)
    playerProperties = save.genericProperties
    local sCS = save.statusController
    for k,v in next, sCS.resourceValues do
        status.setResource(k,v)
    end
    for k,v in next, sCS.resourcesLocked do
        status.setResourceLocked(k,v)
    end
    for k,v in next, sCS.statusProperties do
        status.setStatusProperty(k,v)
    end
    for k,v in next, sCS.persistentEffectCategories do
        status.setPersistentEffects(k,filterEffects(v))
    end
    deployment = setupDeployment(save.deployment, configs)
    companions = setupCompanions(save.companions, configs)
    -- TODO: inventory
    local sI = save.inventory
    equipmentVisibilityMask = sI.equipmentVisibilityMask
    for k,v in next, sI.customBar do
        for k2,v2 in next, v do
            actionBar.groups[k][k2] = arr2ToHands(v2)
        end
    end
    actionBar.selectedGroup = sI.customBarGroup+1
    if type(sI.selectedActionBar) == "number" then
        actionBar.selectedSlot = sI.selectedActionBar+1
    else
        actionBar.selectedSlot = sI.selectedActionBar
    end
    inventory.currencies = sI.currencies
    for k,v in next, essentialSlots do
        actionBar.essentials[v] = fromVersioned(sI[v])
    end
    for k,v in next, armourSlots do
        inventory.equipped[v] = fromVersioned(sI[v.."Slot"])
    end
    for k,v in next, sI.itemBags do
        for k2,v2 in next, v do
            inventory.bags[k][k2] = fromVersioned(v2)
        end
    end
    -- TODO: tech controller should probably act as if movement updated before it, not after,
    -- rn things are detaching due to velocity
    local genericInvokables = {"init","update","uninit"}
    for k,v in next, configs.player.genericScriptContexts do
        local storage = sb.jsonMerge({},save.genericScriptStorage[k])
        local subMcontroller = buildSubMcontroller(safeTables.mcontroller)
        local tables = withCommon({player=player,celestial=celestial,input=puppetInput,mcontroller=subMcontroller.table,songbook=safeTables.songbook})
        genericContexts[k] = buildContext_strict({patched(v)},tables,storage,genericInvokables,{subMcontroller=subMcontroller})
    end
    techController = setupTechController(save.techs, save.techController, configs)
    --npc.setUniqueId(save.uuid)
    storage.uuid = storage.uuid or sb.makeUuid()
    npc.setUniqueId(storage.uuid)
    npc.setDamageTeam(save.team)
    updateEquipped()
    techController.init()
    deployment.init()
    companions.init()
    for k,v in next, genericContexts do
        v.init()
    end
    
    -- TODO: make and use a default ai script
    local aiScripts = playerProperties.pu_aiScripts or {}
    if #aiScripts > 0 then
        local tables = {player=player}
        ai = buildContext(aiScripts,tables,storage,{
            "init","update","uninit",
            "getMoves","getAim","getInputFunc","selectedActionBarGroup","selectedActionBarSlot",
            "commandable","command_version","command_isPassive","command_radius","order","clearOrders","supportsOrder","drawOrders","command_priority"
        })
    end
    
    if ai then
        ai.init()
    end
    
    status.setPersistentEffects("pu_directives",{"pu_directives"})
    needsData = false
    storage.save = save
end

local updateArgs
function getUpdateArgs()
    return updateArgs
end
local controlMoves
local controlAim
function setMoves(nmoves, aim, swap)
    controlMoves = nmoves
    controlAim = aim
    if swap ~= "unchanged" and not root.itemDescriptorsMatch(actionBar.swapSlot, swap) then
        player.setSwapSlotItem(swap)
    end
end
function setControlling(c)
    if not c then
        controlMoves = nil
        controlAim = nil
    else
        updatePuppeteerData()
    end
    controlled = c
end

function pu_isPuppet()
    return true
end

function commandable()
    return not controlled and ai and ai.commandable()
end
-- TODO: pass command functions to ai
function command_enableBars()
  return true
end
function command_energy()
    return status.resource("energy")
end
function command_energyMax()
    return status.resourceMax("energy")
end
function command_energyLocked()
    return status.resourceLocked("energy")
end
function command_energyRegenDelayPerc()
    return status.resourcePercentage("energyRegenBlock")
end
function command_isPassive()
    if ai then
        return ai.command_isPassive()
    end
end
function command_radius()
    if ai then
        return ai.command_radius() or 2
    end
end
function drawOrders(orderTypes, ownerPos)
  if ai then
    return ai.drawOrders(orderTypes,ownerPos)
  end
  return {out={},endPos=mcontroller.position()}
end
local commandToPass = {
    "command_version","command_isPassive","command_priority","order","clearOrders","supportsOrder"
}
for k,v in next, commandToPass do
    _ENV[v] = function(...)
        if ai then
            return ai[v](...)
        end
    end
end
--[[
-- example ai updateOrders
function updateOrders(current)
  local done = false
  local mePos = mcontroller.position()
  if current.type == "suicide" then
    status.setResourcePercentage("health",0)
  end
  if current.type == "attack" then
    done = not world.entityExists(current.target)
    if not done then
      overrideTargetId = current.target
    end
  end
  if current.type == "attackpos" then
    overrideTargetingPos = current.target
  end
  return done
end
]]

local function localToLocal(pos)
    return world.distance(vec2.add(mcontroller.position(),pos), world.entityPosition(world.mainPlayer()))
end

function pu_hasDrawables()
    return true
end
function pu_updateDrawables()
    -- assumes drawables have already been cleared beforehand
    for k,v in next, drawables do
        local drawable = sb.jsonMerge(v.drawable)
        if v.drawable.position then
            drawable.position = localToLocal(v.drawable.position)
        elseif v.drawable.line then
            drawable.line[1] = localToLocal(v.drawable.line[1])
            drawable.line[2] = localToLocal(v.drawable.line[2])
        end
        mainLocalAnimator.addDrawable(drawable,v.layer)
    end
    for k,v in next, lights do
        local light = sb.jsonMerge(v.light)
        light.position = worldToLocal(v.light.position)
        mainLocalAnimator.addLightSource(light)
    end
end

local lastPrimary = false
local lastAlt = false
local lastInteract = false
function update(dt)
    if needsData then
        return
    end
    if controlled and not world.sendEntityMessage(world.mainPlayer(),"isPuppeteer"):result() then
        chat.addMessage("Puppeteer no longer active, resetting control")
        setControlling(false)
    end
    local directives = ""
    storage.hadData = true
    deployment.update(dt)
    companions.update(dt)
    if ai then
        ai.update(dt,controlled)
    end
    if controlled then
        actionBar.selectedGroup = mainPlayer.actionBarGroup()
        actionBar.selectedSlot = mainPlayer.selectedActionBarSlot()
    elseif ai then
        actionBar.selectedGroup = ai.selectedActionBarGroup() or 1
        actionBar.selectedSlot = ai.selectedActionBarSlot()
    end
    updateHeldItems()
    local moves = controlMoves or (ai and ai.getMoves() or {})
    local aim = controlAim or (ai and ai.getAim() or npc.aimPosition())
    -- update the updateArgs
    updateArgs = {
        dt=dt,
        moves=moves
    }
    if moves.primaryFire and not lastPrimary then
        npc.beginPrimaryFire()
    elseif lastPrimary and not moves.primaryFire then
        npc.endPrimaryFire()
    end
    if moves.altFire and not lastAlt then
        npc.beginAltFire()
    elseif lastAlt and not moves.altFire then
        npc.endAltFire()
    end
    lastPrimary = moves.primaryFire
    lastAlt = moves.altFire
    npc.setShifting(not moves.run)
    npc.setAimPosition(aim)
    local dir = 0
    if moves.left then dir = dir - 1 end
    if moves.right then dir = dir + 1 end
    if dir ~= 0 then
        mcontroller.controlMove(dir,moves.run)
    end
    if mcontroller.onGround() and not moves.left and not moves.right and not moves.jump and moves.down then
        mcontroller.controlCrouch()
    end
    if moves.jump then
        if moves.down then
            mcontroller.controlDown()
        else
            mcontroller.controlJump()
        end
    end
    if puppetInput.bindHeld("puppeteer","interact") and not lastInteract then
        if npc.isLounging() then
            npc.resetLounging()
        else
            local loungeables = world.entityQuery(aim, 2, {
                includedTypes={"object","vehicle"},
                order="nearest"
            })
            for k,v in next, loungeables do
                if npc.setLounging(v) then
                    break
                end
            end
        end
    end
    lastInteract = puppetInput.bindHeld("puppeteer","interact")
    techController.setAim(aim)
    techController.update(updateArgs)
    for k,v in next, genericContexts do
        v.update(dt)
        v.mcontroller.update()
    end
    if techController.hidden() then
        directives = "?multiply=00000000"
    else
        directives = techController.directives()
    end
    world.sendEntityMessage(entity.id(),"puppet_setDirectives",directives)
end
-- Engine callback - called on interact
function interact(args)
end

-- Engine callback - called on taking damage
function damage(args)
end

function shouldDie()
  return not status.resourcePositive("health") or forceDie or not world.entityExists(world.mainPlayer())
end

function die()
end

function uninit()
    if needsData then
        return
    end
    if ai then
        ai.uninit()
    end
    techController.uninit()
    deployment.uninit()
    companions.uninit()
    for k,v in next, genericContexts do
        v.uninit()
    end
    for k,v in next, safeTables do
        v:markDestroyed()
    end
end
