local micro = import("micro")
local buffer = import("micro/buffer")
local util = import("micro/util")

local config = import("micro/config")
local fmt = import('fmt')
package.path = fmt.Sprintf('%s;%s/plug/MicroOmni/?.lua', package.path, config.ConfigDir)

local Common = require("Common")

local Self = {}

local OmniFirstMultiCursorSpawned = false

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
    if lastCursor:HasSelection() then
        -- Move the cursor to the beginning of the selection if it has a selection to allow merging
        if lastCursor:LessThan(buffer.Loc(lastCursor.CurSelection[1].X, lastCursor.CurSelection[1].Y)) then
            lastCursor:GotoLoc(buffer.Loc(lastCursor.CurSelection[1].X, lastCursor.CurSelection[1].Y))
        end
        if lastCursor:LessThan(buffer.Loc(lastCursor.CurSelection[2].X, lastCursor.CurSelection[2].Y)) then
            lastCursor:GotoLoc(buffer.Loc(lastCursor.CurSelection[2].X, lastCursor.CurSelection[2].Y))
        end
    end
    
    local moveCursor = false
    if bp.Buf.Settings["MicroOmni.CanUseAddCursor"] then
        moveCursor = not lastCursor:HasSelection()
    else
        moveCursor = (bp.Buf:NumCursors() == 1 and not OmniFirstMultiCursorSpawned)
        -- moveCursor = (() and {true} or {false})[1]
    end
    
    if forceMove then moveCursor = true end
    
    local searchStart = nil
    
    if moveCursor then
        OmniFirstMultiCursorSpawned = true
        bp:Deselect()
        local currentLoc = lastCursor.Loc
        -- searchStart = bp.Buf, buffer.Loc(currentLoc.X, currentLoc.Y)
        -- searchStart = Common.LocBoundCheck(bp.Buf, buffer.Loc(currentLoc.X, currentLoc.Y - 1))
        searchStart = Common.LocBoundCheck(bp.Buf, buffer.Loc(0, currentLoc.Y))
        -- bp.Cursor:Deselect(false)
    else
        OmniFirstMultiCursorSpawned = false
        
        if bp.Buf.Settings["MicroOmni.CanUseAddCursor"] then
            searchStart = buffer.Loc(lastCursor.CurSelection[2].X, lastCursor.CurSelection[2].Y)
        else
            searchStart = buffer.Loc(lastCursor.Loc.X, lastCursor.Loc.Y)
        end
    end
    
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
    
    -- Spawn new cursor if we don't move the last cursor
    if not moveCursor then
        if bp.Buf.Settings["MicroOmni.CanUseAddCursor"] then
            lastCursor = bp:SpawnCursorAtLoc(buffer.Loc(0, 0))
        else
            if not bp:SpawnMultiCursorDown() then
                if not bp:SpawnMultiCursorUp() then
                    micro.InfoBar():Error("Failed to spawn cursor...")
                    return
                end
            end
            lastCursor = bp.Buf:GetCursor(bp.Buf:NumCursors() - 1)
        end
    end
    
    if bp.Buf.Settings["MicroOmni.CanUseAddCursor"] then
        lastCursor:SetSelectionStart(foundLocs[1])
        lastCursor:SetSelectionEnd(foundLocs[2])
        lastCursor.OrigSelection[1].X = lastCursor.CurSelection[1].X
        lastCursor.OrigSelection[1].Y = lastCursor.CurSelection[1].Y
        lastCursor.OrigSelection[2].X = lastCursor.CurSelection[2].X
        lastCursor.OrigSelection[2].Y = lastCursor.CurSelection[2].Y
        lastCursor.Loc.X = lastCursor.CurSelection[2].X
        lastCursor.Loc.Y = lastCursor.CurSelection[2].Y
        if not moveCursor then
            bp.Buf:AddCursor(lastCursor)
        end
    else
        lastCursor.Loc.X = foundLocs[2].X
        lastCursor.Loc.Y = foundLocs[2].Y
    end
    
    bp.Buf:SetCurCursor(bp.Buf:NumCursors() - 1)
    bp.Buf:MergeCursors()
    bp:Relocate()
end


function Self.OmniSpawnCursorNextHighlight(bp)
    PerformMultiCursor(bp, false)
end

function Self.OmniMoveLastCursorNextHighlight(bp)
    PerformMultiCursor(bp, true)
end

return Self
