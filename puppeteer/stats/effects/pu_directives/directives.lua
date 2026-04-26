require "/scripts/rect.lua"

function init()
  message.setHandler("puppet_setDirectives", function(_,l,d)
    if not l then return end
    effect.setParentDirectives(d)
  end)
end

function update(dt)
end

function uninit()

end
