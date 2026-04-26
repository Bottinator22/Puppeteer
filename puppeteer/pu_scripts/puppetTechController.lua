function setupTechController(techs,techController)
    local dirs = root.assetJson("/pu_scripts/techDirectories.json")
    local controller = {}
    local aim = mcontroller.position()
    local techSlots = CaseInsensitiveTable({
        head={},
        body={},
        legs={}
    })
    local function equipTech(sn,kind,storage)
        local slot = techSlots[sn]
        local cat = string.lower(sn)
        if slot.script then
            slot.script.uninit()
        end
        slot.name = kind
        if kind then
            local path = dirs[kind]
            slot.storage = storage or {}
            slot.directives = nil
            slot.hidden = false
            slot.parentState = nil
            slot.visible = false
            slot.offset = {0,0}
            slot.toolUsageSuppressed = false
            local techConfig = root.techConfig(kind)
            local techConfigT = buildContextConfig(techConfig)
            if techConfig.animator then
                status.setPersistentEffects(cat,{"pu_tech_"..kind})
            else
                status.clearPersistentEffects(cat)
            end
            local tech = {}
            function tech.aimPosition()
                return aim
            end
            function tech.setVisible(v)
                slot.visible = v
            end
            function tech.setParentState(s)
                slot.parentState = s
            end
            function tech.setParentDirectives(d)
                slot.directives = d
            end
            function tech.setParentHidden(h)
                slot.hidden = h
            end
            function tech.setParentOffset(o)
                slot.offset = o
            end
            function tech.parentLounging()
                return player.isLounging()
            end
            function tech.setToolUsageSuppressed(t)
                slot.toolUsageSuppressed = t
            end
            local animator
            if techConfig.animator then
                animator = terra_proxy.setupProxy(string.format("pu_tech_%s_animator",kind),entity.id())
            else
                animator = {}
                setmetatable(animator,placeholderMT)
            end
            slot.mcontroller = buildSubMcontroller(safeTables.mcontroller)
            local techTables = withCommon({config=techConfigT,tech=tech,animator=animator,input=puppetInput,mcontroller=slot.mcontroller.table,player=player}) -- oSB adds player table to techs
            local scripts = sb.jsonMerge({},techConfig.scripts)
            for k,v in next, scripts do
                if string.sub(v,1,1) ~= "/" then
                    -- path isn't absolute
                    scripts[k] = path..v
                end
            end
            slot.script = buildContext_strict(scripts,techTables,slot.storage,{"init","update","uninit"},{subMcontroller=slot.mcontroller})
            slot.script.init()
        else
            slot.script = nil
            slot.storage = nil
            slot.directives = nil
            slot.hidden = false
            slot.parentState = nil
            slot.visible = false
            slot.offset = {0,0}
            slot.toolUsageSuppressed = false
            slot.mcontroller = nil
            status.clearPersistentEffects(cat)
        end
    end
    function controller.init()
        for k,v in next, techs.equippedTechs do
            local storage
            for _,v2 in next, techController.techModules do
                if v2.module == v then
                    storage = v2.scriptData
                    break
                end
            end
            equipTech(k,v,storage)
        end
    end
    function controller.update(args)
        for k,v in next, techSlots do
            if v.script then
                v.script.update(args)
            end
            if v.mcontroller then
                v.mcontroller.update()
            end
        end
    end
    function controller.uninit()
        for k,v in next, techSlots do
            if v.script then
                v.script.uninit()
            end
        end
    end
    function controller.setAim(naim)
        aim = naim
    end
    function controller.makeTechAvailable(t)
    end
    function controller.makeTechUnavailable(t)
    end
    function controller.enableTech(t)
    end
    function controller.equipTech(t)
        local tc = root.techConfig(t)
        equipTech(tc.type,t)
    end
    function controller.unequipTech(t)
        local tc = root.techConfig(t)
        if techSlots[tc.type].name == t then
            equipTech(tc.type,nil)
        end
    end
    function controller.enabledTechs()
    end
    function controller.availableTechs()
    end
    function controller.equippedTech(s)
    end
    function controller.hidden()
        for k,v in next, techSlots do
            if v.hidden then
                return true
            end
        end
        return false
    end
    function controller.toolUsageSuppressed()
        for k,v in next, techSlots do
            if v.toolUsageSuppressed then
                return true
            end
        end
        return false
    end
    function controller.directives()
        local d = ""
        for k,v in next, techSlots do
            if v.directives then
                d = d..v.directives
            end
        end
        return d
    end
    function controller.parentState()
        for k,v in next, techSlots do
            if v.parentState then
                return v.parentState
            end
        end
    end
    return controller
end
