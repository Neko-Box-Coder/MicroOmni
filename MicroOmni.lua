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
local strings = import("strings")
local os = import("os")
local utf8 = import("utf8")
local ioutil = import("io/ioutil")


local OmniContentArgs = config.GetGlobalOption("OmniGlobalSearchArgs")
local OmniLocalSearchArgs = config.GetGlobalOption("OmniLocalSearchArgs")
local OmniGotoFileArgs = config.GetGlobalOption("OmniGotoFileArgs")
local OmniSelectType = config.GetGlobalOption("OmniSelectType")
local OmniHistoryLineDiff = config.GetGlobalOption("OmniHistoryLineDiff")

-- TODO: Allow setting highlight to use regex or not

local OmniFzfCmd = config.GetGlobalOption("OmniFzfCmd")
local OmniNewFileMethod = config.GetGlobalOption("OmniNewFileMethod")


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

local OmniOriginalWordsRecords = {} 
local OmniJumpWordsRecords = {}
local OmniOriginalSearchIgnoreCase = false

local OmniDiffPlusFile = true
local OmniDiffTargetPanes = {}
local OmniDiffDiffPanes = {}




function getOS()
    if runtime.GOOS == "windows" then
        return "Windows"
    else
        return "Unix"
    end
end

function setupFzf(bp)
    if OmniFzfCmd == nil then
        OmniFzfCmd = "fzf"
    end

    if OmniNewFileMethod == nil then
        OmniNewFileMethod = "smart_newtab"
    end
end

function OnSearchDirSetDone(resp, cancelled)
    if cancelled then return end

    local bp = micro.CurPane()
    if bp == nil then return end
    
    OmniContentFindPath = resp:gsub("{fileDir}", filepath.Dir(bp.Buf.AbsPath))
    micro.InfoBar():Prompt("Content to find > ", OmniSearchText, "", nil, OnFindPromptDone)
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
        finalCmd = "rg -F -i -uu -n '\\''"..firstWord.."'\\'' | "..OmniFzfCmd.." "..fzfArgs.." -q '\\''"..selectedText.."'\\''"
    else
        selectedText = selectedText:gsub("'", '"')
        firstWord = firstWord:gsub("'", '""')
        fzfArgs = OmniContentArgs:gsub("'", '"')
        finalCmd = "rg -F -i -uu -n \""..firstWord.."\" | "..OmniFzfCmd.." "..fzfArgs.." -q \""..selectedText.."\""
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
        local path, lineNumber = output:match("^(.-):%s*(%d+):")
        
        if searchLoc ~= nil and searchLoc ~= "" then
            -- micro.InfoBar():Message("Open path is ", filepath.Abs(OmniContentFindPath.."/"..path))
            path = OmniContentFindPath.."/"..path
        end
        
        fzfParseOutput(path, bp, lineNumber)
    end
end

-- NOTE: lineNum is string
function fzfParseOutput(output, bp, lineNum)
    micro.Log("fzfParseOutput called")
    if output ~= "" then
        local file = string.gsub(output, "[\n\r]", "")
    
        if file == nil then
            return
        end
        HandleOpenFile(file, bp, lineNum)
    end
end

function HandleOpenFile(path, bp, lineNum)
    if OmniNewFileMethod == "smart_newtab" then
        SmartNewTab(path, bp, lineNum)
        return
    end

    if OmniNewFileMethod == "newtab" then
       bp:NewTabCmd({path})
    else
        local buf, err = buffer.NewBufferFromFile(path)
        if err ~= nil then return end
        
        if OmniNewFileMethod == "vsplit" then
            bp:VSplitIndex(buf, true)
        elseif OmniNewFileMethod == "hsplit" then
            bp:HSplitIndex(buf, true)
        else
            bp:OpenBuffer(buf)
        end
    end

    -- micro.Log("fzfParseOutput new buffer")
    micro.CurPane():GotoCmd({lineNum})
end

-- NOTE: lineNum is string
function SmartNewTab(path, bp, lineNum)
    local cleanFilepath = filepath.Clean(path)
    
    -- If current pane is empty, we can open in it
    if not path_exists(micro.CurPane().Buf.AbsPath) or IsPathDir(micro.CurPane().Buf.AbsPath) then
        if #micro.CurPane().Buf:Bytes() == 0 then
            bp:OpenCmd({cleanFilepath})
            micro.CurPane():GotoCmd({lineNum})
            return
        end
    end

    -- Otherwise find if there's any existing panes
    for i = 1, #micro.Tabs().List do
        for j = 1, #micro.Tabs().List[i].Panes do
            local currentPane = micro.Tabs().List[i].Panes[j]
            local currentBuf = currentPane.Buf
            if  currentBuf ~= nil and 
                (currentBuf.AbsPath == cleanFilepath or currentBuf.Path == cleanFilepath) then
                

                -- NOTE: SetActive functions has index starting at 0 instead lol
                micro.Tabs():SetActive(i - 1)
                micro.Tabs().List[i]:SetActive(j - 1)
                currentPane:GotoCmd({lineNum})
                -- currentPane:Relocate()
                return
            end
        end
    end
    
    -- If not just open it
    local currentActiveIndex = micro.Tabs():Active()
    bp:NewTabCmd({cleanFilepath})
    bp:TabMoveCmd({tostring(currentActiveIndex + 2)})
    micro.CurPane():GotoCmd({lineNum})
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

function GoToHistoryEntry(bp, entry)
    micro.Log("GoToHistoryEntry called")
    micro.Log(  "Goto Entry: ", OmniCursorFilePathMap[entry.FileId], 
                ", ", entry.CursorLoc.X, ", ", entry.CursorLoc.Y)

    local entryFilePath = OmniCursorFilePathMap[entry.FileId]

    -- micro.Log("We have ", #micro.Tabs().List, " tabs")
    HandleOpenFile(entryFilePath, bp, "1")
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

function UpdateDiffView()
    -- micro.InfoBar():Message("UpdateDiffCalled")
    if  micro.CurPane() == nil then
        return
    end
    
    for i, val in ipairs(OmniDiffTargetPanes) do
        if micro.CurPane() == val then
            OmniDiffDiffPanes[i]:GetView().StartLine.Line = micro.CurPane():GetView().StartLine.Line
            OmniCenter(OmniDiffDiffPanes[i])
            return
        end
    end
    
    for i, val in ipairs(OmniDiffDiffPanes) do
        if micro.CurPane() == val then
            OmniDiffTargetPanes[i]:GetView().StartLine.Line = micro.CurPane():GetView().StartLine.Line
            OmniCenter(OmniDiffTargetPanes[i])
            return
        end
    end
end

function RecordCursorHistory()
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

function CheckAndQuitDiffView(targetBp)
    if  targetBp == nil then
        return
    end
    
    -- If one of the target pane is trying to quit, we quit the diff view first. 
    -- Then remove the records
    for i, val in ipairs(OmniDiffTargetPanes) do
        if targetBp == val then
            OmniDiffDiffPanes[i]:Quit()
            table.remove(OmniDiffTargetPanes, i)
            table.remove(OmniDiffDiffPanes, i)
            return
        end
    end
    
    -- If one of the diff pane is trying to quit, just remove records
    for i, val in ipairs(OmniDiffDiffPanes) do
        if targetBp == val then
            table.remove(OmniDiffTargetPanes, i)
            table.remove(OmniDiffDiffPanes, i)
            return
        end
    end
end

function preQuit(bp)
    CheckAndQuitDiffView(bp)
    return true
end

function onAnyEvent()
    micro.Log("onAnyEvent called")
    UpdateDiffView()
    RecordCursorHistory()
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

function AssignJumpWordsToView(msg)
    local bp = micro.CurPane()
    local view = bp:GetView()
    local numberOfLines = bp.Buf:LinesNum()
    local viewStart = (view.StartLine.Line < 0 and {0} or {view.StartLine.Line})[1]
    local viewEnd = viewStart + view.Height - 2
    viewEnd = (viewEnd >= numberOfLines and {numberOfLines - 1} or {viewEnd})[1]
    local viewMid = (viewEnd + viewStart) / 2

    local leftMajorChars = "ASDF"
    local leftMinorChars = "GQWERTZXCVB"
    
    local rightMajorChars = "JKL"
    local rightMinorChars = "HYUIOPNM"

    local rightOriginalWords, rightJumpWords = AssignJumpWords( rightMajorChars..rightMinorChars, 
                                                                leftMajorChars..leftMinorChars, 
                                                                viewMid, 
                                                                viewEnd,
                                                                msg)
    
    local leftOriginalWords = {}
    local leftJumpWords = {}
    
    if viewMid ~= 0 then
        leftOriginalWords, leftJumpWords = AssignJumpWords(   leftMajorChars..leftMinorChars, 
                                                                    rightMajorChars..rightMinorChars, 
                                                                    viewStart, 
                                                                    viewMid - 1,
                                                                    msg)
    end
    
    OmniOriginalWordsRecords = {}
    OmniJumpWordsRecords = {}
    
    for k, v in pairs(leftOriginalWords) do
        OmniOriginalWordsRecords[k] = v
    end
    
    for k, v in pairs(rightOriginalWords) do
        OmniOriginalWordsRecords[k] = v
    end
    
    if viewMid ~= 0 then
        for k, v in pairs(leftJumpWords) do
            OmniJumpWordsRecords[k] = v
        end
        
        for k, v in pairs(rightJumpWords) do
            OmniJumpWordsRecords[k] = v
        end
    end

    -- if numberOfLines >= 1 then
    --     bp.Buf:Insert(buffer.Loc(0, 0), "A")
    --     bp.Buf:Remove(buffer.Loc(0, 0), buffer.Loc(1, 0))
    -- end
    -- bp.Buf:UpdateRules()
end

function AssignJumpWords(majorChars, minorChars, rowIndexStart, rowIndexEnd, CurrentJumpChar)
    micro.Log("rowIndexStart:", rowIndexStart)
    micro.Log("rowIndexEnd:", rowIndexEnd)
    micro.Log("string.len(majorChars):", string.len(majorChars))
    micro.Log("string.len(minorChars):", string.len(minorChars))
    local bp = micro.CurPane()
    local majorCharIndex = 1
    local minorCharIndex = 1
    
    local jumpWordToRc = {}
    local rcToOriWord = {}
    local jumpWordsSeparators = " \t¬~_++<>:{}|&*($%^!\"£)#-=,.;[]'\\/"

    for i = rowIndexStart, rowIndexEnd do
        rcToOriWord[i] = {}
        
        local currentLineBytes = bp.Buf:LineBytes(i)
        local j = 1
        local wordCharCounter = 0
        local usedAllChars = false
        local charIndex = 0
        
        while j <= #currentLineBytes do
            local endRuneCaptureIndex
            if j + 4 > #currentLineBytes then
                endRuneCaptureIndex = #currentLineBytes
            else
                endRuneCaptureIndex = j + 4
            end
            
            local runeBuffer = {}
            for k = j, endRuneCaptureIndex do
                table.insert(runeBuffer, currentLineBytes[k])
            end
            
            local rune, size = utf8.DecodeRune(runeBuffer)
            runeBuffer = {}
            for k = j, j + size - 1 do
                table.insert(runeBuffer, currentLineBytes[k])
            end
            
            local runeStr = util.String(runeBuffer)
            if jumpWordsSeparators:find(runeStr, 1, true) == nil then
                wordCharCounter = wordCharCounter + 1
                
                if wordCharCounter <= 2 and size == 1 then
                    if wordCharCounter == 2 then
                        local currentMajorChar = majorChars:sub(majorCharIndex, majorCharIndex)
                        local currentMinorChar = minorChars:sub(minorCharIndex, minorCharIndex)
                    
                        rcToOriWord[i][j - 1] = {currentLineBytes[j - 1], currentLineBytes[j]}
                        -- jumpWordToRc[currentMajorChar..currentMinorChar] = {i, j - 1}
                        jumpWordToRc[currentMajorChar..currentMinorChar] = {i, charIndex - 1}

                        if CurrentJumpChar ~= nil and CurrentJumpChar ~= "" then
                            if CurrentJumpChar == currentMajorChar then
                                currentLineBytes[j - 1] = string.byte(string.lower(currentMajorChar))
                                currentLineBytes[j] = string.byte(currentMinorChar)
                            end
                        else
                            currentLineBytes[j - 1] = string.byte(currentMajorChar)
                            currentLineBytes[j] = string.byte(currentMinorChar)
                        end
                        
                        if minorCharIndex >= string.len(minorChars) then
                            if majorCharIndex >= string.len(majorChars) then
                                usedAllChars = true
                                break
                            else
                                majorCharIndex = majorCharIndex + 1
                                minorCharIndex = 1
                            end
                        else
                            minorCharIndex = minorCharIndex + 1
                        end
                    end
                end
            else
                wordCharCounter = 0
            end
            
            if size <= 0 then
                break
            end
            
            j = j + size
            charIndex = charIndex + 1
        end
        
        if usedAllChars then
            break
        end
    end
    
    return rcToOriWord, jumpWordToRc
end

function RestoreOriginalWords(rcToOriWord, exclusionRow)
    local bp = micro.CurPane()
    for row, rowValues in pairs(rcToOriWord) do
        if exclusionRow == nil or row ~= exclusionRow then
            local currentLineBytes = bp.Buf:LineBytes(row)
            for column, words in pairs(rowValues) do
                currentLineBytes[column] = words[1]
                currentLineBytes[column + 1] = words[2]
            end
        end
    end
end

function OnTypingJump(msg)
    local bp = micro.CurPane()

    if string.len(msg) > 2 then
        bp.Buf.HighlightSearch = false
        return
    end
    
    if string.len(msg) == 2 then
        micro.InfoBar():DonePrompt(false)
        return
    end
    
    msg = string.upper(msg)
    RestoreOriginalWords(OmniOriginalWordsRecords, nil)
    AssignJumpWordsToView(msg)
    
    if string.len(msg) == 1 then
        bp.Buf.LastSearch = "\\b[a-z][A-Z]"
    else
        bp.Buf.LastSearch = "\\b[A-Z]{2}"
    end
    
    bp.Buf.HighlightSearch = true
    bp.Buf.LastSearchRegex = true

end

function OnWordJump(msg, cancelled)
    RestoreOriginalWords(OmniOriginalWordsRecords, nil)
    local bp = micro.CurPane()
    bp.Buf.Settings["ignorecase"] = OmniOriginalSearchIgnoreCase
    bp.Buf.LastSearch = ""
    bp.Buf.HighlightSearch = false
    if string.len(msg) ~= 2 or cancelled then
        return
    end
    
    msg = string.upper(msg)
    if OmniJumpWordsRecords[msg] == nil then
        return
    end
    
    local jumpRowColumn = OmniJumpWordsRecords[msg]
    bp.Cursor:GotoLoc(LocBoundCheck(bp.Buf, buffer.Loc(jumpRowColumn[2], jumpRowColumn[1])))
end

function createRuntimeFile(relativePath, data)
    local microOmniDir = config.ConfigDir.."/plug/MicroOmni/"
    
    if not path_exists(filepath.Dir(microOmniDir..relativePath)) then
        local err = os.MkdirAll(filepath.Dir(microOmniDir..relativePath), os.ModePerm)
    
        if err ~= nil then
            micro.InfoBar():Error(  "Failed to create dir: ", filepath.Dir(microOmniDir..relativePath), 
                                    " with error ", err)
            return "", false
        end
    end
    
    local err = ioutil.WriteFile(   microOmniDir..relativePath, 
                                    data,
                                    os.ModePerm)

    if err ~= nil then
        micro.InfoBar():Error(  "Failed to write to file: ", microOmniDir..relativePath, 
                                " with error ", err)
        return "", false
    end

    return microOmniDir..relativePath, true
end

function processDiffOutput(output)
    local outputLines = {}
    local currentLineIndex = 1
    
    -- Split the output string by newline
    for i = 1, #output do
        local c = output:sub(i, i)
        if c == "\r" then
            if outputLines[currentLineIndex] ~= nil then
                outputLines[currentLineIndex] = table.concat(outputLines[currentLineIndex])
            end
            currentLineIndex = currentLineIndex + 1
        elseif c == "\n" then
            if i > 1 and output:sub(i - 1, i - 1) ~= "\r" then
                if outputLines[currentLineIndex] ~= nil then
                    outputLines[currentLineIndex] = table.concat(outputLines[currentLineIndex])
                end
                currentLineIndex = currentLineIndex + 1
            end
        else
            if outputLines[currentLineIndex] == nil then
                outputLines[currentLineIndex] = {}
            end
            
            table.insert(outputLines[currentLineIndex], c)
        end
    end
    
    -- micro.Log("outputLines: ", outputLines)
    
    -- Get the index of the first diff
    local outputLinesCount = currentLineIndex
    local firstDiffIndex = -1
    for i = 1, outputLinesCount do
        local curLine
        if outputLines[i] ~= nil then
            curLine = outputLines[i]
            
            micro.Log("Trying to find first diff: ", curLine)
            if #curLine > 2 then
                micro.Log("Checking[1]: ", curLine:sub(1, 1):byte())
                micro.Log("Checking[2]: ", curLine:sub(2, 2):byte())
            end
            
            if #curLine > 2 and curLine:sub(1, 2) == "@@" then
                firstDiffIndex = i
                break
            end
        end
    end

    micro.Log("firstDiffIndex: ", firstDiffIndex)
    
    -- Return empty string if no diff
    if firstDiffIndex <= 0 then
        micro.Log("No diff found")
        return ""
    end
    
    -- Populate the return lines
    local returnLines = {}
    currentLineIndex = firstDiffIndex
    for i = firstDiffIndex, outputLinesCount do
        local curLine
        if outputLines[i] ~= nil then
            curLine = outputLines[i]
            -- micro.Log("Processing: ", curLine)
            
            local targetLineIndex = nil
            if #curLine > 2 and curLine:sub(1, 2) == "@@" then
                if OmniDiffPlusFile then
                    targetLineIndex = curLine:match("%+%d+")
                else
                    targetLineIndex = curLine:match("%-%d+")
                end
                
                targetLineIndex = tonumber(targetLineIndex:sub(2, #targetLineIndex))
            end
        
            -- micro.Log("targetLineIndex: ", targetLineIndex)

            -- If we are at new diff
            if targetLineIndex ~= nil then
                -- Add empty lines until we reach the hunk
                while #returnLines < targetLineIndex - 2 do
                    table.insert(returnLines, "")
                end
                
                -- Add diff header if possible
                if #returnLines <= targetLineIndex - 2 then
                    table.insert(returnLines, curLine)
                    -- micro.Log("Appending diff header")
                end
            else
                -- Otherwise just append the diffs
                table.insert(returnLines, curLine)
                -- micro.Log("Appending diff content")
            end
        end
    end
    
    return table.concat(returnLines, "\n")
end

function OnDiffFinishCallback(resp, cancelled)
    if cancelled then
        return
    end

    local tabSpecified = false
    local tabIndex = -1
    local splitIndex = 1
    
    if #resp >= 4 and resp:sub(1, 4) == "tab:" then
        tabSpecified = true
        
        local respTokens = {}
        for s in string.gmatch(resp, "[^:]+") do
            table.insert(respTokens, s)
        end
        
        if #respTokens == 1 then
            micro.InfoBar():Error("tab expecting index, like tab:<tab index>")
            return
        elseif #respTokens == 2 then
            tabIndex = tonumber(respTokens[2])
        elseif #respTokens == 3 then
            tabIndex = tonumber(respTokens[2])
            splitIndex = tonumber(respTokens[3])
        end
        
        if tabIndex == nil or splitIndex == nil then
            micro.InfoBar():Error("Failed to parse tab index")
            return
        end
        
        if respTokens[2]:sub(1, 1) == "-" or respTokens[2]:sub(1, 1) == "+" then
            -- NOTE: micro.Tabs():Active() starts counting at 1
            tabIndex = micro.Tabs():Active() + 1 + tabIndex
        end
    end

    local respPath = resp
    
    if tabSpecified then
        if tabIndex <= 0 or tabIndex > #micro.Tabs().List then
            micro.InfoBar():Error("tabIndex ", tabIndex, " out of bound for ", #micro.Tabs().List)
            return
        end
        
        if splitIndex <= 0 or splitIndex > #micro.Tabs().List[tabIndex].Panes then
            micro.InfoBar():Error("splitIndex ", splitIndex, " out of bound for ", #micro.Tabs().List[tabIndex].Panes)
            return
        end
        
        if micro.Tabs().List[tabIndex].Panes[splitIndex] == nil then
            micro.InfoBar():Error("micro.Tabs().List[", tabIndex, "].Panes[", splitIndex, "] is nil")
            return
        end
        
        respPath = micro.Tabs().List[tabIndex].Panes[splitIndex].Buf.AbsPath
    end
    
    local minusFile
    local plusFile

    if OmniDiffPlusFile then
        minusFile = respPath
        plusFile = micro.CurPane().Buf.AbsPath
        
        -- Create temp files if needed
        if tabSpecified and micro.Tabs().List[tabIndex].Panes[splitIndex].Buf:Modified() then
            local createdPath, success = 
                createRuntimeFile( "./temp/minus.temp",
                                    micro.Tabs().List[tabIndex].Panes[splitIndex].Buf:Bytes())
            if not success then
                return
            end
            
            minusFile = createdPath
        end
        
        if micro.CurPane().Buf.ModifiedThisFrame then
            local createdPath, success = 
                createRuntimeFile( "./temp/plus.temp", micro.CurPane().Buf:Bytes())
            
            if not success then
                return
            end
            
            plusFile = createdPath
        end
    else
        minusFile = micro.CurPane().Buf.AbsPath
        plusFile = respPath
        
        -- Create temp files if needed
        if micro.CurPane().Buf.ModifiedThisFrame then
            micro.Log("A")

            local createdPath, success = 
                createRuntimeFile( "./temp/minus.temp", micro.CurPane().Buf:Bytes())
            
            if not success then
                return
            end
            
            minusFile = createdPath
        end
    
        if tabSpecified and micro.Tabs().List[tabIndex].Panes[splitIndex].Buf:Modified() then
            local createdPath, success = 
                createRuntimeFile( "./temp/plus.temp",
                                    micro.Tabs().List[tabIndex].Panes[splitIndex].Buf:Bytes())
            if not success then
                return
            end
            
            micro.Log("Minus plus file success: ", createdPath)
            plusFile = createdPath
        end
    end
    
    if not path_exists(plusFile) then
        micro.InfoBar():Error("plusFile: ", minusFile, " does not exist")
        return
    end
    if not path_exists(minusFile) then
        micro.InfoBar():Error("minusFile: ", minusFile, " does not exist")
        return
    end

    micro.Log("Running: ", "diff -U 5 \""..minusFile.."\" \""..plusFile.."\"")

    local output, err = shell.RunCommand("diff -U 5 \""..minusFile.."\" \""..plusFile.."\"")
    
    micro.Log("output: ", output)
    micro.Log("err: ", err)
    
    local processedDiff = processDiffOutput(output)
    
    micro.Log("processedDiff: ", processedDiff)
    
    if err == nil or err:Error() == "exit status 1" or err:Error() == "exit status 2" then
        local curPane = micro.CurPane()
        
        local relPath, err = filepath.Rel(os.Getwd(), minusFile)
        if err == nil and relPath ~= nil then
            minusFile = relPath
        end
        
        relPath, err = filepath.Rel(os.Getwd(), plusFile)
        if err == nil and relPath ~= nil then
            plusFile = relPath
        end
        
        local buf, err = buffer.NewBuffer(processedDiff, "diff")
        if err ~= nil then 
            micro.InfoBar():Error(err)
            return
        end
        
        local diffPane = micro.CurPane():VSplitIndex(buf, not OmniDiffPlusFile)
        
        table.insert(OmniDiffTargetPanes, curPane)
        table.insert(OmniDiffDiffPanes, diffPane)
        
        micro.CurPane():SetLocalCmd({"filetype", "patch"})
    else
        micro.InfoBar():Error(err)
    end
end

function OnDiffPlusCallback(yes, cancelled)
    if cancelled then
        return
    end
    
    OmniDiffPlusFile = yes
    
    micro.InfoBar():Prompt( "File to diff against (Use tab:[+/-]<tab index>[:<split index>] to diff other buffers) > ", 
                            "",
                            "",
                            nil,
                            OnDiffFinishCallback)
end

function CheckCommand(command)
    local _, error = shell.RunCommand(command)
    if error ~= nil then return false end
    return true
end

function OmniContent(bp)
    if OmniContentArgs == nil or OmniContentArgs == "" then
        OmniContentArgs =   "--bind 'alt-f:reload:rg -i -F -uu -n {q}' "..
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
    end
    
    micro.InfoBar():Prompt("Search Directory ({fileDir} for current file directory) > ", "", "", nil, OnSearchDirSetDone)
end

function OmniLocalSearch(bp, args)
    setupFzf(bp)
    
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

    local output, err = shell.RunInteractiveShell(OmniFzfCmd.." "..localSearchArgs, false, true)

    if err ~= nil or output == "" then
        -- micro.InfoBar():Error("Error is: ", err:Error())
    else
        local lineNumber = output:match("^%s*(.-)%s.*")
        -- micro.InfoBar():Message("Output is ", output, " and extracted lineNumber is ", lineNumber)
        micro.CurPane():GotoCmd({lineNumber})
        micro.CurPane():Center()
    end
end

function OmniGotoFile(bp)
    setupFzf(bp)
    
    if OmniGotoFileArgs == nil or OmniGotoFileArgs == "" then
        OmniGotoFileArgs =  "-i --reverse "..
                            "--bind page-up:preview-half-page-up,page-down:preview-half-page-down,"..
                            "alt-up:half-page-up,alt-down:half-page-down "..
                            "--preview-window 'down' "..
                            "--preview 'bat -f -n {}'"
    end

    local localGotoFileArgs = OmniGotoFileArgs
    if bp.Cursor:HasSelection() then
        localGotoFileArgs = localGotoFileArgs.." -q '"..util.String(bp.Cursor:GetSelection()).."'"
    end

    local output, err = shell.RunInteractiveShell(OmniFzfCmd.." "..localGotoFileArgs, false, true)

    if err ~= nil or output == "" then
        -- micro.InfoBar():Error("Error is: ", err:Error())
    else
        -- local lineNumber = output:match("^%s*(.-)%s.*")
        -- local path, lineNumber = output:match("^(.-):%s*(%d+):")
        
        -- micro.InfoBar():Message("Output is ", output, " and extracted lineNumber is ", lineNumber)
        fzfParseOutput(output, bp, "1")
    end
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

    if OmniSelectType == nil or OmniSelectType == "" then
        OmniSelectType = "relative"
    end

    local selectLineCount = tonumber(args[1])
    if selectLineCount == nil then
        micro.InfoBar():Error(args[1].." is not a valid target selection line")
        return
    end

    if OmniSelectType == "relative" then
        targetLine = targetLine + selectLineCount
    else
        targetLine = selectLineCount - 1
    end
    
    local selectX = 0
    cursor.OrigSelection[1] = buffer.Loc(cursor.Loc.X, cursor.Loc.Y)

    if targetLine > cursor.Loc.Y then
        local lineLength = util.CharacterCountInString(buf:Line(targetLine))
        selectX = lineLength
    end

    -- micro.InfoBar():Message("targetLine: ", targetLine)
    -- micro.Log("targetLine: ", targetLine)
    cursor:GotoLoc(buffer.Loc(selectX, targetLine))
    cursor:SelectTo(buffer.Loc(selectX, targetLine))
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
end

function OmniJump(bp)
    bp.Cursor:ResetSelection()
    bp.Buf:ClearCursors()
    
    AssignJumpWordsToView(msg)
    OmniOriginalSearchIgnoreCase = bp.Buf.Settings["ignorecase"]
    
    -- NOTE:    Syntax highlighting could be used instead of search highlight using UpdateRules.
    --          But would require me to use cursor to modify the buffer instead of modifying bytes.
    --          Which will be a lot of work (and complications!!) plus polluting the history as well.
    bp.Buf.Settings["ignorecase"] = false
    bp.Buf.LastSearch = "\\b[A-Z]{2}"
    bp.Buf.LastSearchRegex = true
    bp.Buf.HighlightSearch = true
    
    micro.InfoBar():Prompt( "Select Word To Jump To > ", "", "Command", OnTypingJump, OnWordJump)
end

-- Testing auto complete for commands
function TestCompleter(buf)
    local activeCursor = buf:GetActiveCursor()
    local input, argstart = buf:GetArg()

    -- micro.Log("input:", input)
    -- micro.Log("argstart:", argstart)

    local suggestions = {}
    local commands =
    {
        "set", 
        "reset",
        "setlocal",
        "show",
        "showkey"
    }
    
    
    for _, cmd in ipairs(commands) do
        -- micro.Log("cmd:", cmd)
        
        if strings.HasPrefix(cmd, input) then
            table.insert(suggestions, cmd)
        end
    end

    -- sort.Strings(suggestions)
    table.sort(suggestions, function(a, b) return a:upper() < b:upper() end)
    
    -- completions := make([]string, len(suggestions))
    completions = {}
    
    for _, suggestion in ipairs(suggestions) do
        local offset = activeCursor.X - argstart
    
        table.insert(completions, string.sub(suggestion, offset + 1, string.len(suggestion)))
    end

    return completions, suggestions
    -- return {"test", "test2"}, {"test", "test A"}
end

function OmniTest(bp, args)
    -- micro.InfoBar():Prompt("Test prompt", "Test Message", "Test", TestECB, TestDoneCB)
    bp:CdCmd(args)
end

function TestDoneCB(msg, cancelled)
    -- git diff --output=test.diff -U5 --no-color ".\DefaultUserConfig.yaml" ".\DefaultUserConfig - Copy.yaml"
    
    local output, err = shell.RunInteractiveShell(msg, false, true)
    
    if err == nil or err:Error() == "exit status 1" then
        OmniNewTabRight(micro.CurPane())
        micro.CurPane().Buf:Insert(buffer.Loc(0, 0), output)
    else
        micro.InfoBar():Error(err)
    end
end

function OmniTest2(bp, args)
    -- micro.InfoBar():Prompt("Test prompt", "Test Message", "Test", TestECB, TestDoneCB)
    -- local wd = os.Getwd()
    -- micro.InfoBar():Message("Getwd: ", wd)
    -- local bp = micro.CurPane()
    
    -- bp:HandleCommand("OmniLocalSearch")
    -- bp:HandleCommand("OmniHighlightOnly")

    micro.InfoBar():Prompt("Test prompt> ", "", "Test", nil, TestDoneCB)
    -- local output, err = shell.RunInteractiveShell(finalCmd, false, true)

    -- micro.InfoBar():Prompt("Test prompt", "Test Message", "Test", nil, OnWordJump)
end

function OmniTest3(bp, args)
    -- micro.InfoBar():Prompt("Test prompt", "Test Message", "Test", TestECB, TestDoneCB)
    -- local wd = os.Getwd()
    -- local path = bp.buf.AbsPath
end

function OmniNewTabRight(bp)
    local currentActiveIndex = micro.Tabs():Active()
    bp:NewTabCmd({})
    bp:TabMoveCmd({tostring(currentActiveIndex + 2)})
end

function OmniNewTabLeft(bp)
    local currentActiveIndex = micro.Tabs():Active()
    bp:NewTabCmd({})
    bp:TabMoveCmd({tostring(currentActiveIndex + 1)})
end

function OmniDiff(bp)
    micro.InfoBar():YNPrompt("Is this plus file? (y/n/esc) > ", OnDiffPlusCallback)
end

function init()
    -- config.MakeCommand("fzfinder", fzfinder, config.NoComplete)
    config.MakeCommand("OmniGlobalSearch", OmniContent, config.NoComplete)
    config.MakeCommand("OmniLocalSearch", OmniLocalSearch, config.NoComplete)
    config.MakeCommand("OmniGotoFile", OmniGotoFile, config.NoComplete)
    config.MakeCommand("OmniCenter", OmniCenter, config.NoComplete)
    config.MakeCommand("OmniJumpSelect", OmniSelect, config.NoComplete)

    config.MakeCommand("OmniPreviousHistory", GoToPreviousHistory, config.NoComplete)
    config.MakeCommand("OmniNextHistory", GoToNextHistory, config.NoComplete)

    config.MakeCommand("OmniCopyRelativePath", OmniCopyRelativePath, config.NoComplete)
    config.MakeCommand("OmniCopyAbsolutePath", OmniCopyAbsolutePath, config.NoComplete)

    config.MakeCommand("OmniHighlightOnly", OmniHighlightOnly, config.NoComplete)
    config.MakeCommand("OmniJump", OmniJump, config.NoComplete)
    
    config.MakeCommand("OmniNewTabRight", OmniNewTabRight, config.NoComplete)
    config.MakeCommand("OmniNewTabLeft", OmniNewTabLeft, config.NoComplete)

    config.MakeCommand("OmniDiff", OmniDiff, config.NoComplete)

    -- Convert history line diff to integer in the beginning
    if OmniHistoryLineDiff == nil or OmniHistoryLineDiff == "" then
        OmniHistoryLineDiff = 5
    else
        OmniHistoryLineDiff = tonumber(OmniHistoryLineDiff)
        if OmniHistoryLineDiff == nil then
            OmniHistoryLineDiff = 5
        end
    end
    
    config.MakeCommand("OmniTest", OmniTest, TestCompleter)
    config.MakeCommand("OmniTest2", OmniTest2, config.NoComplete)
    config.MakeCommand("OmniTest3", OmniTest3, config.NoComplete)

    local missingCommands = {}
    if not CheckCommand("fzf --version") then
        missingCommands[#missingCommands + 1] = "fzf"
    end
    
    if not CheckCommand("rg -V") then
        missingCommands[#missingCommands + 1] = "ripgrep"
    end
    
    if not CheckCommand("bat -V") then
        missingCommands[#missingCommands + 1] = "bat"
    end

    if #missingCommands ~= 0 then
        local missingCommandsString = ""
        
        for i = 1, #missingCommands do
            if i ~= #missingCommands then
                missingCommandsString = missingCommandsString..missingCommands[i]..", "
            else
                missingCommandsString = missingCommandsString..missingCommands[i].." "
            end
        end
        
        micro.InfoBar():Error(missingCommandsString.."are missing. Search may not work properly")
    end

end
