local micro = import("micro")
local buffer = import("micro/buffer")
local util = import("micro/util")

local config = import("micro/config")
local fmt = import('fmt')
package.path = fmt.Sprintf('%s;%s/plug/?.lua', package.path, config.ConfigDir)

local Common = require("MicroOmni.Common")

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
    local searchStart = nil
    local lastCursorBegin = nil
    if lastCursor:HasSelection() then
        -- Move the cursor to the beginning of the selection if it has a selection to allow merging
        if lastCursor.CurSelection[1]:LessThan(buffer.Loc(  lastCursor.CurSelection[2].X, 
                                                            lastCursor.CurSelection[2].Y)) then
            
            lastCursor:GotoLoc(buffer.Loc(lastCursor.CurSelection[1].X, lastCursor.CurSelection[1].Y))
            searchStart = buffer.Loc(lastCursor.CurSelection[2].X, lastCursor.CurSelection[2].Y)
            lastCursorBegin = buffer.Loc(lastCursor.CurSelection[1].X, lastCursor.CurSelection[1].Y)
        else
            lastCursor:GotoLoc(buffer.Loc(lastCursor.CurSelection[2].X, lastCursor.CurSelection[2].Y))
            searchStart = buffer.Loc(lastCursor.CurSelection[1].X, lastCursor.CurSelection[1].Y)
            lastCursorBegin = buffer.Loc(lastCursor.CurSelection[2].X, lastCursor.CurSelection[2].Y)
        end
    end
    
    if searchStart == nil then
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
        if foundLocs[1].X ~= lastCursor.Loc.X or foundLocs[1].Y ~= lastCursor.Loc.Y then
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
            else
                -- micro.Log("lastCursorBegin:", lastCursorBegin)
                -- micro.Log("foundLocs[1]:", foundLocs[1])
                -- micro.Log("searchStart:", searchStart)
            end
            break
        end
        
        i = i + 1
    end
    
    if not differentFound then
        return
    end
    
    local moveCursor = (not cursorOnFound) or forceMove
    -- micro.Log("cursorOnFound:", cursorOnFound)
    
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
        lastCursor:SetSelectionStart(nextFoundLocs[1])
        lastCursor:SetSelectionEnd(nextFoundLocs[2])
        lastCursor.OrigSelection[1].X = lastCursor.CurSelection[1].X
        lastCursor.OrigSelection[1].Y = lastCursor.CurSelection[1].Y
        lastCursor.OrigSelection[2].X = lastCursor.CurSelection[2].X
        lastCursor.OrigSelection[2].Y = lastCursor.CurSelection[2].Y
        lastCursor.Loc.X = lastCursor.CurSelection[2].X
        lastCursor.Loc.Y = lastCursor.CurSelection[2].Y
        if not moveCursor then
            bp.Buf:AddCursor(lastCursor)
        end
    -- Can't do selection because SpawnMultiCursorDown() deselects all the cursors. 
    -- Probably could have saved the cursor selections and then restore them, but effort..
    else
        lastCursor.Loc.X = nextFoundLocs[1].X
        lastCursor.Loc.Y = nextFoundLocs[1].Y
    end
    
    -- micro.Log("lastCursor.Loc:", lastCursor.Loc)
    -- micro.Log("")
    
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
