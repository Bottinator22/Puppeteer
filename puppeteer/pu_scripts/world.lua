function update(dt)
    for _,v in next, world.entities({includedTypes={"npc"},callScript="pu_isPuppet"}) do
        world.callScriptedEntity(v,"pu_postUpdate")
    end
end
