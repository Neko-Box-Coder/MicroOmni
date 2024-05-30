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




local OmniContentArgs = config.GetGlobalOption("OmniGlobalSearchArgs")
local OmniLocalSearchArgs = config.GetGlobalOption("OmniLocalSearchArgs")
local OmniSelectType = config.GetGlobalOption("OmniSelectType")
local OmniHistoryLineDiff = config.GetGlobalOption("OmniHistoryLineDiff")
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
        OmniContentArgs =   "--bind 'alt-f:reload:rg -i -uu -n {q}' "..
                            "--delimiter : -i --reverse "..
                            "--bind page-up:preview-half-page-up,page-down:preview-half-page-down,"..
                            "alt-up:half-page-up,alt-down:half-page-down "..
                            "--preview-window 'down,+{2}-/2' "..
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
    micro.Log("Find Content called")
    local bp = micro.CurPane()
    setupFzf(bp)

    local selectedText = str
    local fzfArgs = ""
    -- micro.Log("selectedText before: ", selectedText)
    -- micro.Log("OmniContentArgs before: ", OmniContentArgs)

    local firstWord, otherWords = selectedText:match("^(.[^%s]*)%s-(.*)$")

    if firstWord == nil or firstWord == "" then
        micro.InfoBar():Error("Failed to extract first word... str: ", str)
        return
    end

    local currentOS = getOS()
    local finalCmd;
    if currentOS == "Unix" then
        selectedText = selectedText:gsub("'", "'\\''")
        firstWord = firstWord:gsub("'", "'\\''")
        fzfArgs = OmniContentArgs:gsub("'", "'\\''")
        finalCmd = "rg -i -uu -n '\\''"..firstWord.."'\\'' | "..fzfCmd.." "..fzfArgs.." -q '\\''"..selectedText.."'\\''"
    else
        selectedText = selectedText:gsub("'", '"')
        firstWord = firstWord:gsub("'", '""')
        fzfArgs = OmniContentArgs:gsub("'", '"')
        finalCmd = "rg -i -uu -n \""..firstWord.."\" | "..fzfCmd.." "..fzfArgs.." -q \""..selectedText.."\""
    end


    if currentOS == "Unix" then
        finalCmd = "sh -c \'"..finalCmd.."\'"
    else
        finalCmd = "cmd /s /v /c "..finalCmd..""
    end

    micro.Log("Running search cmd: ", finalCmd)

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

    local output, err = shell.RunInteractiveShell(finalCmd, false, true)

    if searchLoc ~= nil and searchLoc ~= "" then
        bp:CdCmd({currentLoc})
    end

    if err ~= nil or output == "--" then
        -- micro.InfoBar():Error("Error is: ", err:Error())
    else
        local filePath, lineNumber = output:match("^(.-):%s*(%d+):")
        
        if searchLoc ~= nil and searchLoc ~= "" then
            -- micro.InfoBar():Message("Open path is ", filepath.Abs(OmniContentFindPath.."/"..filePath))
            filePath = OmniContentFindPath.."/"..filePath
        end
        
        fzfParseOutput(filePath, bp, lineNumber)
    end
end


function fzfParseOutput(output, bp, lineNum)
    micro.Log("fzfParseOutput called")
    if output ~= "" then
        local file = string.gsub(output, "[\n\r]", "")
    
        if file == nil then
            return
        end

        -- micro.InfoBar():Message("file is ", file)

        if fzfOpen == "newtab" then
           bp:NewTabCmd({file})
        else
            local buf, err = buffer.NewBufferFromFile(file)
            if err ~= nil then return end
            
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

function LocBoundCheck(buf, loc)
    local totalNumOfLines = buf:LinesNum()
    local returnLoc = buffer.Loc(loc.X, loc.Y)
    
    if loc.Y >= totalNumOfLines then
        returnLoc = buffer.Loc(returnLoc.X, totalNumOfLines - 1)
    end

    if loc.Y < 0 then
        returnLoc = buffer.Loc(returnLoc.X, 0)
    end

    local lineLength = util.CharacterCountInString(buf:Line(returnLoc.Y))

    if lineLength == 0 then
        returnLoc = buffer.Loc(0, returnLoc.Y)
    elseif loc.X >= lineLength then
        returnLoc = buffer.Loc(lineLength, returnLoc.Y)
    else
        returnLoc = buffer.Loc(loc.X, returnLoc.Y)
    end

    return returnLoc
end

function OmniCenter(bp)
    local view = bp:GetView()
    local oriX = bp.Cursor.Loc.X
    bp.Cursor:ResetSelection()
    bp.Buf:ClearCursors()
    local targetLineY = view.StartLine.Line + view.Height / 2
    bp.Cursor:GotoLoc(LocBoundCheck(bp.Buf, buffer.Loc(bp.Cursor.Loc.X, targetLineY)))
end

function OmniSelect(bp, args)
    if #args < 1 then return end

    local buf = bp.Buf
    local cursor = buf:GetActiveCursor()
    local currentLoc = cursor.Loc
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
    cursor:GotoLoc(buffer.Loc(currentLoc.X, targetLine))
    cursor:SelectTo(buffer.Loc(currentLoc.X, targetLine))
    bp:Relocate()
end


function GoToPreviousHistory(bp)
    if #OmniCursorHistory == 0 or OmniCursorIndices.CurrentIndex <= OmniCursorIndices.StartIndex then
        return
    end

    OmniCursorIndices.CurrentIndex = OmniCursorIndices.CurrentIndex - 1;
    micro.InfoBar():Message("Going to previous history at index ", OmniCursorIndices.CurrentIndex)
    GoToHistoryEntry(bp, OmniCursorHistory[OmniCursorIndices.CurrentIndex])
end

function GoToNextHistory(bp)
    if #OmniCursorHistory == 0 or OmniCursorIndices.CurrentIndex >= OmniCursorIndices.EndIndex then
        return
    end

    OmniCursorIndices.CurrentIndex = OmniCursorIndices.CurrentIndex + 1;
    micro.InfoBar():Message("Going to next history at index ", OmniCursorIndices.CurrentIndex)
    GoToHistoryEntry(bp, OmniCursorHistory[OmniCursorIndices.CurrentIndex])
end

function GoToHistoryEntry(bp, entry)
    micro.Log("GoToHistoryEntry called")
    micro.Log(  "Goto Entry: ", OmniCursorFilePathMap[entry.FileId], 
                ", ", entry.CursorLoc.X, ", ", entry.CursorLoc.Y)

    local entryFilePath = OmniCursorFilePathMap[entry.FileId]

    -- micro.Log("We have ", #micro.Tabs().List, " tabs")
    
    for i = 1, #micro.Tabs().List do
        -- micro.Log("Tab ", i, " has ", #micro.Tabs().List[i].Panes, " panes")
        for j = 1, #micro.Tabs().List[i].Panes do
            local currentPane = micro.Tabs().List[i].Panes[j]
            local currentBuf = currentPane.Buf
            if currentBuf ~= nil and currentBuf.AbsPath == entryFilePath then
                currentPane.Cursor:ResetSelection()
                currentPane.Buf:ClearCursors()
                currentPane.Cursor:GotoLoc(LocBoundCheck(currentBuf, entry.CursorLoc))

                -- NOTE: SetActive functions has index starting at 0 instead lol
                micro.Tabs():SetActive(i - 1)
                micro.Tabs().List[i]:SetActive(j - 1)
                currentPane:Relocate()
                return
            end
        end
    end
    
    local entryRelativePath, err = filepath.Rel(os.Getwd(), entryFilePath)
    
    if err ~= nil or entryRelativePath == nil or entryRelativePath == nil then
        bp:NewTabCmd({entryFilePath})
    else
        bp:NewTabCmd({entryRelativePath})
    end
    
    if  micro.CurPane() == nil or micro.CurPane().Cursor == nil or micro.CurPane().Buf == nil then
        return
    end
    
    micro.CurPane().Cursor:GotoLoc(LocBoundCheck(micro.CurPane().Buf, entry.CursorLoc))
    micro.CurPane():Relocate()
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
        math.abs(currentHistory.CursorLoc.Y - currentCursorLoc.Y) < OmniHistoryLineDiff then

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

-- See issue https://github.com/zyedidia/micro/issues/3320
-- Modified from https://github.com/kaarrot/microgrep/blob/e1a32e8b95397a40e5dda0fb43e7f8d17469b88c/microgrep.lua#L118
function WriteToClipboardWorkaround(content)
    if micro.CurPane() == nil then return end

    local curTab = micro.CurPane():Tab()
    local curPaneId = micro.CurPane():ID()
    local curPaneIndex = curTab:GetPane(curPaneId)

    -- Split pane in half and add some text
    micro.CurPane():HSplitAction()
    
    local buf,err = buffer.NewBuffer(content, "")
    -- Workaround to copy path to clioboard
    micro.CurPane():OpenBuffer(buf)
    micro.CurPane():SelectAll()
    micro.CurPane():Copy()
    micro.CurPane():ForceQuit() -- Close current buffer pane

    curTab:SetActive(curPaneIndex)
end

function OmniCopyRelativePath(bp)
    if bp.Buf == nil then return end

    -- clipboard.Write(bp.Buf.Path, clipboard.ClipboardReg)
    WriteToClipboardWorkaround(bp.Buf.Path)
    micro.InfoBar():Message(bp.Buf.Path, " copied into clipboard")
end

function OmniCopyAbsolutePath(bp)
    if bp.Buf == nil then return end
    
    -- clipboard.Write(bp.Buf.AbsPath, clipboard.ClipboardReg)
    WriteToClipboardWorkaround(bp.Buf.AbsPath)
    micro.InfoBar():Message(bp.Buf.AbsPath, " copied into clipboard")
end


function OmniHighlightOnly(bp)
    local selectionText = ""
    if bp.Cursor:HasSelection() then
        selectionText = bp.Cursor:GetSelection()
        selectionText = util.String(selectionText)
    end
    
    micro.InfoBar():Prompt( "Highlight Then Find (regex) > ", 
                            selectionText, "", OnTypingHighlight, OnSubmitHighlightFind)

    -- bp.Buf.LastSearch = args[1]
    -- bp.Buf.LastSearchRegex = true
    -- bp.Buf.HighlightSearch = true
end

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
            foundCounter == 1500 or 
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

function OmniLocalSearch(bp, args)
    if OmniLocalSearchArgs == nil or OmniLocalSearchArgs == "" then
        OmniLocalSearchArgs =   "--bind 'start:reload:bat -n --decorations always {filePath}' "..
                                "-i --reverse "..
                                "--bind page-up:preview-half-page-up,page-down:preview-half-page-down,"..
                                "alt-up:half-page-up,alt-down:half-page-down "..
                                "--preview-window 'down,+{1}-/2' "..
                                "--preview 'bat -f -n --highlight-line {1} {filePath}'"
    end

    local localSearchArgs = OmniLocalSearchArgs:gsub("{filePath}", "\""..bp.buf.AbsPath.."\"")

    if bp.Cursor:HasSelection() then
            localSearchArgs = localSearchArgs.." -q '"..util.String(bp.Cursor:GetSelection()).."'"
    end

    local output, err = shell.RunInteractiveShell(fzfCmd.." "..localSearchArgs, false, true)

    if err ~= nil or output == "" then
        -- micro.InfoBar():Error("Error is: ", err:Error())
    else
        local lineNumber = output:match("^%s*(.-)%s.*")
        -- micro.InfoBar():Message("Output is ", output, " and extracted lineNumber is ", lineNumber)
        micro.CurPane():GotoCmd({lineNumber})
        micro.CurPane():Center()
    end
end


function TestECB(msg)
    micro.Log("TestECV called with message: ", msg)
end

function TestDoneCB(msg, cancelled)
    micro.Log("TestDoneCB called with message ", msg, " and cancelled ", cancelled)
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


function OmniTest3(bp, args)
    -- micro.InfoBar():Prompt("Test prompt", "Test Message", "Test", TestECB, TestDoneCB)
    -- local wd = os.Getwd()
    -- local filePath = bp.buf.AbsPath

end


function init()
    -- config.MakeCommand("fzfinder", fzfinder, config.NoComplete)
    config.MakeCommand("OmniGlobalSearch", OmniContent, config.NoComplete)
    config.MakeCommand("OmniLocalSearch", OmniLocalSearch, config.NoComplete)
    config.MakeCommand("OmniCenter", OmniCenter, config.NoComplete)
    config.MakeCommand("OmniJumpSelect", OmniSelect, config.NoComplete)

    config.MakeCommand("OmniPreviousHistory", GoToPreviousHistory, config.NoComplete)
    config.MakeCommand("OmniNextHistory", GoToNextHistory, config.NoComplete)

    config.MakeCommand("OmniCopyRelativePath", OmniCopyRelativePath, config.NoComplete)
    config.MakeCommand("OmniCopyAbsolutePath", OmniCopyAbsolutePath, config.NoComplete)

    config.MakeCommand("OmniHighlightOnly", OmniHighlightOnly, config.NoComplete)


    -- Convert history line diff to integer in the beginning
    if OmniHistoryLineDiff == nil or OmniHistoryLineDiff == "" then
        OmniHistoryLineDiff = 5
    else
        OmniHistoryLineDiff = tonumber(OmniHistoryLineDiff)
        if OmniHistoryLineDiff == nil then
            OmniHistoryLineDiff = 5
        end
    end
    
    config.MakeCommand("OmniTest", OmniTest, config.NoComplete)
    config.MakeCommand("OmniTest2", OmniTest2, config.NoComplete)
    config.MakeCommand("OmniTest3", OmniTest3, config.NoComplete)

  
end
