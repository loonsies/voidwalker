addon.name = 'voidwalker'
addon.version = '0.01'
addon.author = 'looney'

require 'common'
local settings = require('settings')
local chat = require('chat')
local imgui = require('imgui')
local drawing = require('drawing')

local direction = {
    North = 1,
    East = 2,
    South = 3,
    West = 4,
    Northeast = 5,
    Northwest = 6,
    Southwest = 7,
    Southeast = 8,
    None = 9,
    [1] = 'North',
    [2] = 'East',
    [3] = 'South',
    [4] = 'West',
    [5] = 'Northeast',
    [6] = 'Northwest',
    [7] = 'Southwest',
    [8] = 'Southeast',
    [9] = 'None'
}

local currentDirection = direction.None
local currentDistance = 0.0
local destinationPosition = nil
local visible = false
local proximityMessageSent = false
local bypassHeal = { false }

local function drawUI()
    imgui.PushStyleVar(ImGuiStyleVar_WindowPadding, { 2, 2 })
    imgui.PushStyleVar(ImGuiStyleVar_ItemSpacing, { 4, 0 })
    imgui.PushStyleVar(ImGuiStyleVar_FramePadding, { 2, 2 })
    imgui.PushStyleVar(ImGuiStyleVar_WindowBorderSize, 0)
    imgui.PushStyleVar(ImGuiStyleVar_WindowMinSize, { 0, 0 })

    local windowFlags = bit.bor(ImGuiWindowFlags_NoTitleBar, ImGuiWindowFlags_AlwaysAutoResize)
    imgui.SetNextWindowSize({ 0, 0 }, ImGuiCond_FirstUseEver)
    if imgui.Begin('voidwalker', visible, windowFlags) then
        imgui.Text('Direction: ' .. direction[currentDirection])

        -- Calculate current distance to destination and display appropriate text
        local displayDistance = currentDistance
        if destinationPosition then
            local player = GetPlayerEntity()
            if player then
                local playerPos = player.Movement.LocalPosition
                local deltaX = destinationPosition.X - playerPos.X
                local deltaY = destinationPosition.Y - playerPos.Y
                local actualDistance = math.sqrt(deltaX * deltaX + deltaY * deltaY)

                if actualDistance < 1.0 then
                    imgui.PushStyleColor(ImGuiCol_Text, { 0.0, 1.0, 0.0, 1.0 }) -- Green color
                    imgui.Text('Distance: At NM position')
                    imgui.PopStyleColor()
                else
                    imgui.Text('Distance: ' .. string.format("%.1f", actualDistance))
                end
            else
                imgui.Text('Distance: ' .. currentDistance)
            end
        else
            imgui.Text('Distance: ' .. currentDistance)
        end

        imgui.Checkbox('Bypass Heal', bypassHeal)
        imgui.PopStyleVar(5)
        imgui.End()
    end
end


local function getDirectionVector(dir)
    -- In FFXI, Y and Z are swapped compared to typical 3D conventions
    if dir == direction.North then
        return { x = 0, y = 1 }
    elseif dir == direction.South then
        return { x = 0, y = -1 }
    elseif dir == direction.East then
        return { x = 1, y = 0 }
    elseif dir == direction.West then
        return { x = -1, y = 0 }
    elseif dir == direction.Northeast then
        return { x = 0.707, y = 0.707 } -- normalized diagonal
    elseif dir == direction.Northwest then
        return { x = -0.707, y = 0.707 }
    elseif dir == direction.Southeast then
        return { x = 0.707, y = -0.707 }
    elseif dir == direction.Southwest then
        return { x = -0.707, y = -0.707 }
    else
        return { x = 0, y = 0 }
    end
end

local function handleIncomingText(e)
    if not e or not e.message or e.injected then return end

    local text = string.lower(e.message)

    -- Check for "no monsters" message to reset target
    if (string.find(text, 'there seem to be no monsters')) then
        -- Reset all tracking variables
        currentDirection = direction.None
        currentDistance = 0.0
        destinationPosition = nil
        proximityMessageSent = false
        return
    end

    -- Extract distance from the message (pattern: "number yalms direction")
    local distance = string.match(text, "(%d+)%s+yalms")
    if distance then
        local distanceNum = tonumber(distance)
        if distanceNum then
            currentDistance = distanceNum
        end
    end

    -- Determine direction and calculate absolute destination position
    local newDirection = direction.None
    if (string.find(text, 'yalms northeast')) then
        newDirection = direction.Northeast
    elseif (string.find(text, 'yalms northwest')) then
        newDirection = direction.Northwest
    elseif (string.find(text, 'yalms southwest')) then
        newDirection = direction.Southwest
    elseif (string.find(text, 'yalms southeast')) then
        newDirection = direction.Southeast
    elseif (string.find(text, 'yalms east')) then
        newDirection = direction.East
    elseif (string.find(text, 'yalms west')) then
        newDirection = direction.West
    elseif (string.find(text, 'yalms north')) then
        newDirection = direction.North
    elseif (string.find(text, 'yalms south')) then
        newDirection = direction.South
    end

    -- If we found a direction and distance, calculate the absolute destination position
    if newDirection ~= direction.None and currentDistance > 0 then
        currentDirection = newDirection
        proximityMessageSent = false -- Reset proximity message for new destination

        local player = GetPlayerEntity()
        if player then
            local playerPos = player.Movement.LocalPosition
            local dirVector = getDirectionVector(currentDirection)

            -- Calculate and store the destination position (Z will be updated in real-time to match player height)
            local destX = playerPos.X + (dirVector.x * currentDistance)
            local destY = playerPos.Y + (dirVector.y * currentDistance)
            local destZ = playerPos.Z -- initial Z level, will be updated in real-time

            destinationPosition = { X = destX, Y = destY, Z = destZ }
        end
    end
end

local function drawVoidwalkerPath()
    if not destinationPosition then
        return
    end

    local player = GetPlayerEntity()
    if not player then return end

    local playerPos = player.Movement.LocalPosition

    -- Update destination Z coordinate to match player's current height
    destinationPosition.Z = playerPos.Z

    -- Calculate distance to destination (ignoring Z/height)
    local deltaX = destinationPosition.X - playerPos.X
    local deltaY = destinationPosition.Y - playerPos.Y
    local distance = math.sqrt(deltaX * deltaX + deltaY * deltaY)

    -- Check if player is within 1.0 yalm of destination
    if distance < 1.0 and not proximityMessageSent then
        print(chat.header('voidwalker'):append(chat.success('NM position reached')))
        proximityMessageSent = true
    elseif distance >= 1.0 then
        -- Reset the proximity message flag if player moves away
        proximityMessageSent = false
    end

    local pathColor = 0xFF00FFFF -- Cyan color
    drawing:DrawLine(playerPos, destinationPosition, pathColor)
end

-- Read a single byte from a packet.
local function readByte(packet, offset)
    return packet:byte(offset + 1)
end

-- Write a single byte to a packet.
local function writeByte(packet, offset, value)
    return packet:sub(1, offset) .. string.char(value) .. packet:sub(offset + 2)
end

ashita.events.register('text_in', 'text_in_cb', function(e)
    handleIncomingText(e)
end)

ashita.events.register('d3d_present', 'render_cb', function()
    drawVoidwalkerPath()
    drawUI()
end)

ashita.events.register('packet_in', 'packet_in_cb', function(e)
    if e.id == 0x37 then
        local val = readByte(e.data, 0x30)

        if val == 0x21 and bypassHeal[1] then
            e.data_modified = writeByte(e.data_modified, 0x30, 0x00)
        end
    end
end)
