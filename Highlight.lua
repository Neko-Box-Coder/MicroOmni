local micro = import("micro")
local buffer = import("micro/buffer")
local util = import("micro/util")

local config = import("micro/config")
local fmt = import('fmt')
package.path = fmt.Sprintf('%s;%s/plug/?.lua', package.path, config.ConfigDir)

local Self = {}

local OmniBufStoredPanes = {}
local OmniBufLastFindMsg = {}
local OmniBufFoundOccurrence = {}
local OmniBufInverseFoundOccurrence = {}

local function OnTypingHighlight(msg)
    if micro.CurPane() == nil or micro.CurPane().Buf == nil then return end

    local bp = micro.CurPane()
    bp.Buf.LastSearch = msg
    bp.Buf.LastSearchRegex = true
    bp.Buf.HighlightSearch = true
end

local function OnSubmitHighlightFind(msg, cancelled)
    if micro.CurPane() == nil or micro.CurPane().Buf == nil or msg == nil or msg == "" then return end

    local bp = micro.CurPane()
    if cancelled then
        bp.Buf.HighlightSearch = false
        return
    end

    bp.Buf.LastSearch = msg
    bp.Buf.LastSearchRegex = true
    bp.Buf.HighlightSearch = true
    
    local startFindLoc = buffer.Loc(0, 0)
    local lastLineIndex = bp.Buf:LinesNum()
    
    if lastLineIndex > 0 then
        lastLineIndex = lastLineIndex - 1
    else
        micro.InfoBar():Message("None found and highlighted")
        return
    end
    
    local lastLineLength = util.CharacterCountInString(bp.Buf:Line(lastLineIndex))
    if lastLineLength ~= 0 then
        lastLineLength = lastLineLength - 1
    end
    
    local endFindLoc = buffer.Loc(lastLineLength, lastLineIndex)
    
    local foundCounter = 0
    local currentLoc = buffer.Loc(startFindLoc.X, startFindLoc.Y)
    local firstOccurrenceLoc = buffer.Loc(-1, -1)
    
    local bpIndex = -1
    for i, val in ipairs(OmniBufStoredPanes) do
        if val == bp then
            bpIndex = i
            break
        end
    end
    
    if bpIndex == -1 then
        table.insert(OmniBufStoredPanes, bp)
        table.insert(OmniBufLastFindMsg, msg)
        table.insert(OmniBufFoundOccurrence, {})
        table.insert(OmniBufInverseFoundOccurrence, {})
        bpIndex = #OmniBufStoredPanes
    else
        OmniBufLastFindMsg[bpIndex] = msg
        OmniBufFoundOccurrence[bpIndex] = {}
        OmniBufInverseFoundOccurrence[bpIndex] = {}
    end
    
    while true do
        local foundLocs, found, err = bp.Buf:FindNext(  msg, 
                                                        startFindLoc, 
                                                        endFindLoc, 
                                                        currentLoc, 
                                                        true,
                                                        true)
        
        if  found == false or 
            err ~= nil or 
            foundCounter >= 1500 or 
            (foundLocs[2].X == firstOccurrenceLoc.X and foundLocs[2].Y == firstOccurrenceLoc.Y) then
            
            break
        end
        
        currentLoc = buffer.Loc(foundLocs[2].X, foundLocs[2].Y)
        
        local currentLocTable = {foundLocs[2].X, foundLocs[2].Y}
        table.insert(OmniBufFoundOccurrence[bpIndex], currentLocTable)
        if OmniBufInverseFoundOccurrence[bpIndex][currentLocTable[1]] == nil then
            OmniBufInverseFoundOccurrence[bpIndex][currentLocTable[1]] = {}
        end
        
        OmniBufInverseFoundOccurrence[bpIndex][currentLocTable[1]][currentLocTable[2]] = 
            #OmniBufFoundOccurrence[bpIndex]
        
        foundCounter = foundCounter + 1
        
        if foundCounter == 1 then
            firstOccurrenceLoc = buffer.Loc(foundLocs[2].X, foundLocs[2].Y)
        end
    end
    
    micro.InfoBar():Message(foundCounter,   " found and highlighted. Do FindNext/FindPrevious to "..
                                            "go to the occurrences")
end

function Self.OmniHighlightOnly(bp)
    local selectionText = ""
    if bp.Cursor:HasSelection() then
        selectionText = bp.Cursor:GetSelection()
        selectionText = util.String(selectionText)
    end
    
    micro.InfoBar():Prompt( "Highlight Then Find (regex) > ", 
                            selectionText, "", OnTypingHighlight, OnSubmitHighlightFind)
end


local function PerformMultiCursor(bp, forceMove)
    -- Check highlight
    if not bp.Buf.HighlightSearch or bp.Buf.LastSearch == "" then
        bp:SpawnMultiCursor()
        return
    end
    
    local lastCursor = bp.Buf:GetCursor(bp.Buf:NumCursors() - 1)
    local searchStart = nil
    local lastCursorBegin = nil
    
    local cursorEnd = true
    local selectionReversed = false
    
    if lastCursor:HasSelection() then
        -- Reorder selection LOC
        local sels = {}
        if lastCursor.CurSelection[1]:LessThan(buffer.Loc(  lastCursor.OrigSelection[1].X, 
                                                            lastCursor.OrigSelection[1].Y)) then
            selectionReversed = true
            cursorEnd = false
        else
            selectionReversed = false
            cursorEnd = true
        end
        
        table.insert(sels, buffer.Loc(lastCursor.CurSelection[1].X, lastCursor.CurSelection[1].Y))
        table.insert(sels, buffer.Loc(lastCursor.CurSelection[2].X, lastCursor.CurSelection[2].Y))
        
        searchStart = buffer.Loc(sels[2].X, sels[2].Y)
        lastCursorBegin = buffer.Loc(sels[1].X, sels[1].Y)
    else
        cursorEnd = false
        searchStart = buffer.Loc(lastCursor.Loc.X + 1, lastCursor.Loc.Y)
        lastCursorBegin = buffer.Loc(lastCursor.Loc.X, lastCursor.Loc.Y)
    end
    
    local differentFound = false
    local nextFoundLocs = nil
    local cursorOnFound = false
    local i = 1
    while i < 2 do
        local foundLocs, found, err = bp.Buf:FindNext(  bp.Buf.LastSearch, 
                                                        bp.Buf:Start(), 
                                                        bp.Buf:End(), 
                                                        searchStart, 
                                                        true,
                                                        true)
        
        if found == false or err ~= nil then
            micro.InfoBar():Message("No occurrences found")
            return
        end
        
        -- We found an unique occurrence, Check if the cursor is on an occurrence
        if foundLocs[1].X ~= lastCursorBegin.X or foundLocs[1].Y ~= lastCursorBegin.Y then
            differentFound = true
            nextFoundLocs = {   buffer.Loc(foundLocs[1].X, foundLocs[1].Y), 
                                buffer.Loc(foundLocs[2].X, foundLocs[2].Y)}
            
            foundLocs, found, err = bp.Buf:FindNext(bp.Buf.LastSearch, 
                                                    bp.Buf:Start(), 
                                                    bp.Buf:End(), 
                                                    nextFoundLocs[1], 
                                                    false,
                                                    true)
            -- What?
            if found == false or err ~= nil then
                break
            end
            
            if lastCursorBegin.X == foundLocs[1].X and lastCursorBegin.Y == foundLocs[1].Y then
                cursorOnFound = true
                cursorEnd = false
            elseif lastCursorBegin.X == foundLocs[2].X and lastCursorBegin.Y == foundLocs[2].Y then
                cursorOnFound = true
                cursorEnd = true
            end
            break
        end
        
        i = i + 1
    end
    
    if not differentFound then
        return
    end
    
    local moveCursor = (not cursorOnFound) or forceMove
    
    -- Spawn new cursor if we don't move the last cursor
    if not moveCursor then
        if bp.Buf.Settings["MicroOmni.CanUseAddCursor"] then
            lastCursor = bp:SpawnCursorAtLoc(buffer.Loc(0, 0))
        else
            -- Save and restore original cursor if we can't use `AddCursor()`, since 
            -- `SpawnMultiCursorDown()` moves the cursor that has selection to the beginning 
            local origHasSelection = lastCursor:HasSelection()
            local origLocX = 0
            local origLocY = 0
            if origHasSelection then
                if not selectionReversed then
                    origLocX = lastCursor.CurSelection[2].X
                    origLocY = lastCursor.CurSelection[2].Y
                    cursorEnd = true
                else
                    origLocX = lastCursor.CurSelection[1].X
                    origLocY = lastCursor.CurSelection[1].Y
                    cursorEnd = false
                end
            end
            
            if not bp:SpawnMultiCursorDown() then
                if not bp:SpawnMultiCursorUp() then
                    micro.InfoBar():Error("Failed to spawn cursor...")
                    return
                end
            end
            
            if origHasSelection then
                lastCursor.Loc.X = origLocX
                lastCursor.Loc.Y = origLocY
            end
            
            lastCursor = bp.Buf:GetCursor(bp.Buf:NumCursors() - 1)
        end
    end
    
    if bp.Buf.Settings["MicroOmni.CanUseAddCursor"] then
        if selectionReversed then
            lastCursor.OrigSelection[1].X = nextFoundLocs[2].X
            lastCursor.OrigSelection[1].Y = nextFoundLocs[2].Y
            lastCursor:SelectTo(nextFoundLocs[1])
            lastCursor.Loc.X = nextFoundLocs[1].X
            lastCursor.Loc.Y = nextFoundLocs[1].Y
        else
            lastCursor.OrigSelection[1].X = nextFoundLocs[1].X
            lastCursor.OrigSelection[1].Y = nextFoundLocs[1].Y
            lastCursor:SelectTo(nextFoundLocs[2])
            lastCursor.Loc.X = nextFoundLocs[2].X
            lastCursor.Loc.Y = nextFoundLocs[2].Y
        end
        
        if not moveCursor then
            bp.Buf:AddCursor(lastCursor)
        end
    -- Can't do selection because SpawnMultiCursorDown() deselects all the cursors. 
    -- Probably could have saved the cursor selections and then restore them, but effort..
    else
        if cursorEnd then
            lastCursor.Loc.X = nextFoundLocs[2].X
            lastCursor.Loc.Y = nextFoundLocs[2].Y
        else
            lastCursor.Loc.X = nextFoundLocs[1].X
            lastCursor.Loc.Y = nextFoundLocs[1].Y
        end
    end
    
    -- micro.Log("lastCursor.Loc:", lastCursor.Loc)
    -- micro.Log("")
    
    bp.Buf:SetCurCursor(bp.Buf:NumCursors() - 1)
    bp.Buf:MergeCursors()
    bp:Relocate()
end

local function ShowFoundIndex()
    if micro.CurPane() == nil or micro.CurPane().Buf == nil then return end
    
    local bp = micro.CurPane()
    
    local bpIndex = -1
    for i, val in ipairs(OmniBufStoredPanes) do
        if val == bp then
            bpIndex = i
            break
        end
    end
    
    if bpIndex == -1 then
        return
    end
    
    if  not bp.Buf.LastSearchRegex or 
        not bp.Buf.HighlightSearch or 
        OmniBufLastFindMsg[bpIndex] ~= bp.Buf.LastSearch then
    
        return
    end
    
    -- If we are not in any of the found entry, get out
    if  OmniBufInverseFoundOccurrence[bpIndex][bp.Cursor.Loc.X] == nil or 
        OmniBufInverseFoundOccurrence[bpIndex][bp.Cursor.Loc.X][bp.Cursor.Loc.Y] == nil then
        -- local currentLocTable = {bp.Cursor.Loc.X, bp.Cursor.Loc.Y}
        -- micro.Log("currentLocTable:", currentLocTable)
        -- 
        -- for i, val in ipairs(OmniBufFoundOccurrence[bpIndex]) do
        --     micro.Log("OmniBufFoundOccurrence[bpIndex][", i, "]:", val)
        -- end
        -- 
        -- for k, v in pairs(OmniBufInverseFoundOccurrence[bpIndex]) do
        --     micro.Log("OmniBufInverseFoundOccurrence[bpIndex] key:", k)
        --     micro.Log("OmniBufInverseFoundOccurrence[bpIndex] val:", v)
        -- end
        return
    end
    
    local outputMsg =   
        "At occurrences " .. 
        tostring(OmniBufInverseFoundOccurrence[bpIndex][bp.Cursor.Loc.X][bp.Cursor.Loc.Y]) .. 
        "/" .. tostring(#OmniBufFoundOccurrence[bpIndex])
                        
    micro.InfoBar():Message(outputMsg)
end

function Self.OmniSpawnCursorNextHighlight(bp)
    PerformMultiCursor(bp, false)
end

function Self.OmniMoveLastCursorNextHighlight(bp)
    PerformMultiCursor(bp, true)
end

function Self.OmniOnNextFind()
    ShowFoundIndex()
end

function Self.OmniOnPrevFind()
    ShowFoundIndex()
end

return Self
