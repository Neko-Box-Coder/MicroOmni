VERSION = "0.1.0"

local micro = import("micro")
local config = import("micro/config")
local buffer = import("micro/buffer")
local shell = import("micro/shell")
local filepath = import("path/filepath")
local action = import("micro/action")
local util = import("micro/util")
local screen = import("micro/screen")
local runtime = import("runtime")
local os = import("os")




local OmniContentArgs = config.GetGlobalOption("OmniContentArgs")
local OmniSelectType = config.GetGlobalOption("OmniSelectType")
local fzfCmd =  config.GetGlobalOption("fzfcmd")
local fzfOpen = config.GetGlobalOption("fzfopen")


local OmniCursorHistory = {}
local OmniCursorIndices = 
{
    StartIndex = 0,
    EndIndex = 0,
    CurrentIndex = 0,
}
local OmniCursorFilePathMap = {}
local OmniCursorReverseFilePathMap = {}


local OmniContentFindPath = ""
local OmniSearchText = ""



function getOS()
    if runtime.GOOS == "windows" then
        return "Windows"
    else
        return "Unix"
    end
end

function setupFzf(bp)
    if fzfCmd == nil then
        fzfCmd = "fzf"
    end

    if fzfOpen == nil then
        fzfOpen = "thispane"
    end
end

function OmniContent(bp)
    if OmniContentArgs == nil or OmniContentArgs == "" then
        -- OmniContentArgs =   "--bind 'start:reload:rg -i -uu -n {q}' "..
        OmniContentArgs =   "--bind 'alt-f:reload:rg -i -uu -n {q}' "..
                            "--delimiter : -i "..
                            "--bind page-up:preview-half-page-up,page-down:preview-half-page-down,"..
                            "alt-up:half-page-up,alt-down:half-page-down "..
                            "--preview-window '+{2}-/2' "..
                            "--preview 'bat -f -n --highlight-line {2} {1}'"
    end

    OmniSearchText = ""
    if bp.Cursor:HasSelection() then
        OmniSearchText = bp.Cursor:GetSelection()
        OmniSearchText = util.String(OmniSearchText)
        micro.InfoBar():Prompt("Search Directory ({fileDir} for current file directory) > ", "", "", nil, OnSearchDirSetDone)
    else
        micro.InfoBar():Prompt("Search Directory ({fileDir} for current file directory) > ", "", "", nil, OnSearchDirSetDone)
    end
end

function OnSearchDirSetDone(resp, cancelled)
    if cancelled then return end

    local bp = micro.CurPane()
    if bp == nil then return end
    
    OmniContentFindPath = resp:gsub("{fileDir}", filepath.Dir(bp.buf.AbsPath))

    if OmniSearchText == "" then
        micro.InfoBar():Prompt("Content to find > ", "", "", nil, OnFindPromptDone)
    else
        FindContent(OmniSearchText, OmniContentFindPath)
    end
end

function OnFindPromptDone(resp, cancelled)
    if cancelled then return end
    FindContent(resp, OmniContentFindPath)
    return
end

-- Grabbed from filemanager2
-- Stat a path to check if it exists, returning true/false
function path_exists(path)
    -- Stat the file/dir path we created
    -- file_stat should be non-nil, and stat_err should be nil on success
    local file_stat, stat_err = os.Stat(path)
    -- Check if what we tried to create exists
    if stat_err ~= nil then
        -- true/false if the file/dir exists
        return os.IsExist(stat_err)
    elseif file_stat ~= nil then
        -- Assume it exists if no errors
        return true
    end
    return false
end

function IsPathDir(path)
    -- Stat the file/dir path we created
    -- file_stat should be non-nil, and stat_err should be nil on success
    local file_stat, stat_err = os.Stat(path)
    if stat_err ~= nil then
        return false
    elseif file_stat ~= nil then
        -- Assume it exists if no errors
        return file_stat:IsDir()
    end
    return false
end


function FindContent(str, searchLoc)

    local bp = micro.CurPane()

    -- micro.InfoBar():Message("Find Content called")

    setupFzf(bp)
    -- local selectedText = util.String(str)
    local selectedText = str
    local fzfArgs = ""

    -- micro.Log("selectedText before: ", selectedText)
    -- micro.Log("OmniContentArgs before: ", OmniContentArgs)

    local firstWord, otherWords = selectedText:match("^(.-)%s-(.*)$")

    if firstWord == nil then
        micro.InfoBar():Error("Failed to extract first word... str: ", str)
        return
    end

    local currentOS = getOS()
    if currentOS == "Unix" then
        selectedText = selectedText:gsub("'", "'\\''")
        firstWord = firstWord:gsub("'", "'\\''")
        fzfArgs = OmniContentArgs:gsub("'", "'\\''")
    else
        selectedText = selectedText:gsub("'", '"')
        firstWord = firstWord:gsub("'", '""')
        fzfArgs = OmniContentArgs:gsub("'", '"')
    end


    local finalCmd = "rg -i -uu -n \""..firstWord.."\" | "..fzfCmd.." "..fzfArgs.." -q \""..selectedText.."\""

    if currentOS == "Unix" then
        finalCmd = "sh -c \'"..finalCmd.."\'"
    else
        finalCmd = "cmd /s /v /c "..finalCmd..""
    end

    -- micro.Log("Running search cmd: ", finalCmd)

    local currentLoc = os.Getwd()

    if searchLoc ~= nil and searchLoc ~= "" then
        if not path_exists(searchLoc) then
            micro.InfoBar():Error("", searchLoc, " doesn't exist")
            return
        end

        if not IsPathDir(searchLoc) then
            micro.InfoBar():Error("", searchLoc, " is not a directory")
            return
        end

        bp:CdCmd({searchLoc})
    end

    -- micro.InfoBar():Message("finalCmd: ", finalCmd)

    local output, err = shell.RunInteractiveShell(finalCmd, false, true)

    if searchLoc ~= nil and searchLoc ~= "" then
        bp:CdCmd({currentLoc})
    end

    if err ~= nil or output == "--" then
        -- micro.InfoBar():Error("Error is: ", err:Error())
    else
        local filePath, lineNumber = output:match("^(.-):%s*(%d+):")
        -- lineNumber = tonumber(lineNumber)
        fzfParseOutput(filePath, bp, lineNumber)
    end
end


function fzfParseOutput(output, bp, lineNum)
    if output ~= "" then
        local file = string.gsub(output, "[\n\r]", "")
    
        if file == nil then
            return
        end

        -- micro.Log("fzfParseOutput starts")
        -- micro.InfoBar():Message("file is ", file)

        if fzfOpen == "newtab" then
           bp:NewTabCmd({file})
        else
            local buf, err = buffer.NewBufferFromFile(file)
            if fzfOpen == "vsplit" then
                bp:VSplitIndex(buf, true)
            elseif fzfOpen == "hsplit" then
                bp:HSplitIndex(buf, true)
            else
                bp:OpenBuffer(buf)
            end
        end

        -- micro.Log("fzfParseOutput new buffer")
        micro.CurPane():GotoCmd({lineNum})
        -- micro.Log("fzfParseOutput new line")
    end
end

function OmniCenter(bp)
    local view = bp:GetView()
    bp.Cursor:ResetSelection()
    bp.Buf:ClearCursors()
    bp.Cursor:GotoLoc(buffer.Loc(view.StartCol, view.StartLine.Line + view.Height / 2))
end

function OmniSelect(bp, args)
    if #args < 1 then return end

    local buf = bp.Buf
    -- local bufLineNum = buf:LinesNum()
    local cursor = buf:GetActiveCursor()
    local currentLoc = cursor.Loc
    -- local currentLine = cursor.Loc.Y
    local targetLine = cursor.Loc.Y

    cursor.OrigSelection[1] = buffer.Loc(cursor.Loc.X, cursor.Loc.Y)

    if OmniSelectType == nil or OmniSelectType == "" then
        OmniSelectType = "relative"
    end

    if OmniSelectType == "relative" then
        targetLine = targetLine + tonumber(args[1])
     else
        targetLine = tonumber(args[1]) - 1
    end

    -- micro.InfoBar():Message("targetLine: ", targetLine)
    -- micro.Log("targetLine: ", targetLine)

    -- cursor:SetSelectionStart(currentLoc)
    cursor:GotoLoc(buffer.Loc(currentLoc.X, targetLine))
    cursor:SelectTo(buffer.Loc(currentLoc.X, targetLine))
    bp:Relocate()
end


function GoToPreviousHistory(bp)
    if #OmniCursorHistory == 0 or OmniCursorIndices.CurrentIndex <= OmniCursorIndices.StartIndex then
        return
    end

    OmniCursorIndices.CurrentIndex = OmniCursorIndices.CurrentIndex - 1;
    micro.Log("Going to previous, index ", OmniCursorIndices.CurrentIndex)
    GoToHistoryEntry(bp, OmniCursorHistory[OmniCursorIndices.CurrentIndex])
end

function GoToNextHistory(bp)
    if #OmniCursorHistory == 0 or OmniCursorIndices.CurrentIndex >= OmniCursorIndices.EndIndex then
        return
    end

    OmniCursorIndices.CurrentIndex = OmniCursorIndices.CurrentIndex + 1;
    micro.Log("Going to next, index ", OmniCursorIndices.CurrentIndex)
    GoToHistoryEntry(bp, OmniCursorHistory[OmniCursorIndices.CurrentIndex])
end

function GoToHistoryEntry(bp, entry)
    micro.Log("GoToHistoryEntry called")
    micro.Log(  "Goto Entry: ", OmniCursorFilePathMap[entry.FileId], 
                ", ", entry.CursorLoc.X, ", ", entry.CursorLoc.Y)

    local entryFilePath = OmniCursorFilePathMap[entry.FileId]

    micro.Log("We have ", #micro.Tabs().List, " tabs")
    for i = 1, #micro.Tabs().List do
        -- micro.Log("Tab ", i, " has ", #micro.Tabs().List[i].Panes, " panes")
        for j = 1, #micro.Tabs().List[i].Panes do
            local currentPane = micro.Tabs().List[i].Panes[j]
            local currentBuf = currentPane.Buf
            if currentBuf ~= nil and currentBuf.AbsPath == entryFilePath then
                currentPane.Cursor:GotoLoc(entry.CursorLoc)

                -- NOTE: SetActive functions has index starting at 0 instead lol
                micro.Tabs():SetActive(i - 1)
                micro.Tabs().List[i]:SetActive(j - 1)
                currentPane:Relocate()
                return
            end
        end
    end

    bp.Cursor:GotoLoc(entry.CursorLoc)
    bp:Relocate()
end


function TestECB(msg)
    micro.Log("TestECV called with message: ", msg)
end

function TestDoneCB(msg, cancelled)
    micro.Log("TestDoneCB called with message ", msg, " and cancelled ", cancelled)
end

function LuaCopy(obj, seen)
    if type(obj) ~= 'table' then return obj end
    if seen and seen[obj] then return seen[obj] end
    local s = seen or {}
    local res = setmetatable({}, getmetatable(obj))
    s[obj] = res
    for k, v in pairs(obj) do res[copy(k, s)] = copy(v, s) end
    return res
end

function CopyLoc(loc)
    return buffer.Loc(loc.X, loc.Y)
end

function onAnyEvent()
    micro.Log("onAnyEvent called")
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
    if not path_exists(bufPath) or IsPathDir(bufPath) then
        return
    end

    -- micro.Log("onAnyEvent called")
    -- micro.Log("currentCursorLoc: ", currentCursorLoc.X, ", ", currentCursorLoc.Y)
    -- micro.Log("bufPath: ", bufPath)
    -- micro.Log("currentHistorySize: ", currentHistorySize)

    -- If we haven't see this path
    if OmniCursorReverseFilePathMap[bufPath] == nil then
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
        math.abs(currentHistory.CursorLoc.Y - currentCursorLoc.Y) < 5 then

        -- micro.Log("currentHistory.CursorLoc.Y: ", currentHistory.CursorLoc.Y)
        -- micro.Log("math.abs(currentHistory.CursorLoc.Y - currentCursorLoc.Y): ", math.abs(currentHistory.CursorLoc.Y - currentCursorLoc.Y))

        -- Just update X if on the same line
        if currentHistory.CursorLoc.Y == currentCursorLoc.Y then
            -- micro.Log("currentHistory.CursorLoc.X: ", currentHistory.CursorLoc.X)
            -- micro.Log("currentCursorLoc.X: ", currentCursorLoc.X)
            OmniCursorHistory[OmniCursorIndices.CurrentIndex].CursorLoc = CopyLoc(currentCursorLoc)
            -- currentHistory.CursorLoc.X = currentCursorLoc.X
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
    for i = OmniCursorIndices.StartIndex, OmniCursorIndices.EndIndex do
        if i == OmniCursorIndices.CurrentIndex then
            micro.Log("Current Index")
        end

        micro.Log(  "Cursor History at ", i, ": ",  OmniCursorFilePathMap[OmniCursorHistory[i].FileId], 
                    ", ", OmniCursorHistory[i].CursorLoc.X, ", ", OmniCursorHistory[i].CursorLoc.Y)
    end

    
end

function OmniTest(bp, args)
    -- micro.InfoBar():Prompt("Test prompt", "Test Message", "Test", TestECB, TestDoneCB)
    bp:CdCmd(args)
end

function OmniTest2(bp, args)
    -- micro.InfoBar():Prompt("Test prompt", "Test Message", "Test", TestECB, TestDoneCB)
    local wd = os.Getwd()

    micro.InfoBar():Message("Getwd: ", wd)
end


function init()
    -- config.MakeCommand("fzfinder", fzfinder, config.NoComplete)
    config.MakeCommand("OmniFind", OmniContent, config.NoComplete)
    config.MakeCommand("OmniCenter", OmniCenter, config.NoComplete)
    config.MakeCommand("OmniJumpSelect", OmniSelect, config.NoComplete)
    config.MakeCommand("OmniPreviousHistory", GoToPreviousHistory, config.NoComplete)
    config.MakeCommand("OmniNextHistory", GoToNextHistory, config.NoComplete)


    config.MakeCommand("OmniTest", OmniTest, config.NoComplete)
    config.MakeCommand("OmniTest2", OmniTest2, config.NoComplete)

  
end
