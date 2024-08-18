local micro = import("micro")
local buffer = import("micro/buffer")
local util = import("micro/util")

local config = import("micro/config")
local fmt = import('fmt')
package.path = fmt.Sprintf('%s;%s/plug/MicroOmni/?.lua', package.path, config.ConfigDir)

local Self = {}


function OnTypingHighlight(msg)
    if micro.CurPane() == nil or micro.CurPane().Buf == nil then return end

    local bp = micro.CurPane()
    bp.Buf.LastSearch = msg
    bp.Buf.LastSearchRegex = true
    bp.Buf.HighlightSearch = true
end

function OnSubmitHighlightFind(msg, cancelled)
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


return Self
