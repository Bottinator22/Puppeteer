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
print(removeDirectives("^afafaf;Quadruple Arms^reset;"))
