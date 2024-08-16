local micro = import("micro")
local config = import("micro/config")
local buffer = import("micro/buffer")

local fmt = import('fmt')

local OmniCursorHistory = {}
local OmniCursorReverseFilePathMap = {}
local OmniCursorFilePathMap = {}
local OmniCursorIndices = 
{
    StartIndex = 0,
    EndIndex = 0,
    CurrentIndex = 0,
}

package.path = fmt.Sprintf('%s;%s/plug/MicroOmni/?.lua', package.path, config.ConfigDir)
local Common = require("Common")

local Self = {}

local function CopyLoc(loc)
    return buffer.Loc(loc.X, loc.Y)
end

function Self.RecordCursorHistory()
    if  micro.CurPane() == nil or micro.CurPane().Cursor == nil or micro.CurPane().Buf == nil then
        return
    end
    
    local currentCursorLoc = micro.CurPane().Cursor.Loc
    local bufPath = micro.CurPane().Buf.AbsPath
    local currentHistorySize = #OmniCursorHistory

    if bufPath == nil or bufPath == "" then
        return
    end

    -- Check bufPath exists and is a file
    if not Common.path_exists(bufPath) or Common.IsPathDir(bufPath) then
        return
    end

    -- micro.Log("currentCursorLoc: ", currentCursorLoc.X, ", ", currentCursorLoc.Y)
    -- micro.Log("bufPath: ", bufPath)
    -- micro.Log("currentHistorySize: ", currentHistorySize)

    -- If we haven't see this path
    if  OmniCursorReverseFilePathMap[bufPath] == nil then
        OmniCursorFilePathMap[#OmniCursorFilePathMap + 1] = bufPath
        OmniCursorReverseFilePathMap[bufPath] = #OmniCursorFilePathMap
    end

    -- If first entry, just append
    if currentHistorySize == 0 then
        -- Append current cursor and return
        OmniCursorHistory[1] = 
        {
            FileId = OmniCursorReverseFilePathMap[bufPath],
            CursorLoc = CopyLoc(currentCursorLoc)
        }
        OmniCursorIndices.StartIndex = 1
        OmniCursorIndices.EndIndex = 1
        OmniCursorIndices.CurrentIndex = 1
        return
    end

    local currentHistory = OmniCursorHistory[OmniCursorIndices.CurrentIndex]

    -- If difference is too less, then just leave it
    if  currentHistory.FileId == OmniCursorReverseFilePathMap[bufPath] and 
        math.abs(currentHistory.CursorLoc.Y - currentCursorLoc.Y) < Common.OmniHistoryLineDiff then

        -- Just update X if on the same line
        if currentHistory.CursorLoc.Y == currentCursorLoc.Y then
            -- micro.Log("currentHistory.CursorLoc.X: ", currentHistory.CursorLoc.X)
            -- micro.Log("currentCursorLoc.X: ", currentCursorLoc.X)
            OmniCursorHistory[OmniCursorIndices.CurrentIndex].CursorLoc = CopyLoc(currentCursorLoc)
        end

        return
    end

    OmniCursorHistory[OmniCursorIndices.CurrentIndex + 1] = 
    {
        FileId = OmniCursorReverseFilePathMap[bufPath],
        CursorLoc = CopyLoc(currentCursorLoc)
    }

    OmniCursorIndices.CurrentIndex = OmniCursorIndices.CurrentIndex + 1

    -- If we are not at the end of the history, we will need to remove the rest of the history until the end
    if OmniCursorIndices.EndIndex > OmniCursorIndices.CurrentIndex  then
        for i = OmniCursorIndices.CurrentIndex + 1, OmniCursorIndices.EndIndex do
            OmniCursorHistory[i] = nil
        end
    end

    OmniCursorIndices.EndIndex = OmniCursorIndices.CurrentIndex

    currentHistorySize = #OmniCursorHistory

    -- Remove the first entry if we have more than 256 entries. Just to keep it small
    if currentHistorySize > 256 then
        OmniCursorHistory[OmniCursorIndices.StartIndex] = nil
        OmniCursorIndices.StartIndex = OmniCursorIndices.StartIndex + 1
    end

    -- Debug log printing the whole cursor history
--     for i = OmniCursorIndices.StartIndex, OmniCursorIndices.EndIndex do
--         if i == OmniCursorIndices.CurrentIndex then
--             micro.Log("Current Index")
--         end
-- 
--         micro.Log(  "Cursor History at ", i, ": ",  OmniCursorFilePathMap[OmniCursorHistory[i].FileId], 
--                     ", ", OmniCursorHistory[i].CursorLoc.X, ", ", OmniCursorHistory[i].CursorLoc.Y)
--     end
end


function GoToHistoryEntry(bp, entry)
    micro.Log("GoToHistoryEntry called")
    micro.Log(  "Goto Entry: ", OmniCursorFilePathMap[entry.FileId], 
                ", ", entry.CursorLoc.X, ", ", entry.CursorLoc.Y)

    local entryFilePath = OmniCursorFilePathMap[entry.FileId]

    -- micro.Log("We have ", #micro.Tabs().List, " tabs")
    Common.HandleOpenFile(entryFilePath, bp, "1")
    micro.CurPane().Cursor:ResetSelection()
    micro.CurPane().Cursor:GotoLoc(Common.LocBoundCheck(micro.CurPane().Buf, entry.CursorLoc))
    micro.CurPane():Relocate()
end

function Self.GoToPreviousHistory(bp)
    if #OmniCursorHistory == 0 or OmniCursorIndices.CurrentIndex <= OmniCursorIndices.StartIndex then
        return
    end

    OmniCursorIndices.CurrentIndex = OmniCursorIndices.CurrentIndex - 1;
    micro.InfoBar():Message("Going to previous history at index ", OmniCursorIndices.CurrentIndex)
    GoToHistoryEntry(bp, OmniCursorHistory[OmniCursorIndices.CurrentIndex])
end

function Self.GoToNextHistory(bp)
    if #OmniCursorHistory == 0 or OmniCursorIndices.CurrentIndex >= OmniCursorIndices.EndIndex then
        return
    end

    OmniCursorIndices.CurrentIndex = OmniCursorIndices.CurrentIndex + 1;
    micro.InfoBar():Message("Going to next history at index ", OmniCursorIndices.CurrentIndex)
    GoToHistoryEntry(bp, OmniCursorHistory[OmniCursorIndices.CurrentIndex])
end


return Self
