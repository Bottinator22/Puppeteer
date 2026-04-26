-- prevent cross-context smuggling
-- this should work fine. but it might not.
for k,v in next, _ENV do
    if type(v) == "table" then
        _ENV[k] = setmetatable({},{__index=v})
    end
end
local oldSetMT = setmetatable
local oldGetMT = getmetatable
local stringMT = {__index=string}
function setmetatable(t,mt)
    if type(t) == "string" then
        stringMT = mt
    else
        oldSetMT(t,mt)
    end
    return t
end
function getmetatable(t)
    if type(t) == "string" then
        return stringMT
    else
        return oldGetMT(t)
    end
end
