-- just loads of utilities for saves and inventory management and such
local configCache = {}
function itemConfig(i)
    if configCache[i] then
        return configCache[i]
    else
        local c = root.itemConfig(i)
        configCache[i] = c.config
        return c.config
    end
end
function arr2ToHands(arr)
    return {primary=arr[1],alt=arr[2]}
end 
function itemCompleteConfig(i)
    local id = fullItemDescriptor(i)
    local ic = itemConfig(id.name)
    return sb.jsonMerge(ic,id.parameters)
end
function arrayToSet(a)
    local out = {}
    for k,v in next, a do
        out[v] = true
    end
    return out
end
function fromVersioned(d)
    if not d then return nil end
    -- TODO: possibly make versioning work?
    return d.content
end
function equals(o1, o2, ignore_mt)
    if o1 == o2 then return true end
    local o1Type = type(o1)
    local o2Type = type(o2)
    if o1Type ~= o2Type then return false end
    if o1Type ~= 'table' then return false end
    if not ignore_mt then
        local mt1 = getmetatable(o1)
        if mt1 and mt1.__eq then
            --compare using built in method
            return o1 == o2
        end
    end
    local keySet = {}
    for key1, value1 in pairs(o1) do
        local value2 = o2[key1]
        if value2 == nil or equals(value1, value2, ignore_mt) == false then
            return false
        end
        keySet[key1] = true
    end
    for key2, _ in pairs(o2) do
        if not keySet[key2] then return false end
    end
    return true
end
function itemEq(a,b,excludeCount)
    if not a or not b then
        return false
    end
    if a == b then
        return true
    end
    if a.count ~= b.count and not excludeCount then
        return false
    end
    if a.name ~= b.name then
        return false
    end
    return equals(a.parameters, b.parameters)
end
local baseItemDesc = {name="perfectlygenericitem",count=1,parameters={}}
function fullItemDescriptor(i)
    if type(i) == "string" then
        return {name=i,count=1,parameters={}}
    else
        return sb.jsonMerge(baseItemDesc,i)
    end
end
