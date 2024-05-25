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




-- local OmniContentInputArgs = config.GetGlobalOption("OmniContentInputArgs")
local OmniContentArgs = config.GetGlobalOption("OmniContentArgs")
local OmniSelectType = config.GetGlobalOption("OmniSelectType")

local fzfCmd =  config.GetGlobalOption("fzfcmd")
local fzfOpen = config.GetGlobalOption("fzfopen")


local OmniContentFindPath = ""
local OmniSearchText = ""
-- local fzfPath = config.GetGlobalOption("fzfpath")



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
        micro.InfoBar():Prompt("Search Directory ({fileDir}) > ", "", "", nil, OnSearchDirSetDone)
    else
        micro.InfoBar():Prompt("Search Directory ({fileDir}) > ", "", "", nil, OnSearchDirSetDone)
    end
end

function OnSearchDirSetDone(resp, cancelled)
    if cancelled then return end

    local bp = micro.CurPane()
    if bp == nil then return end
    
    OmniContentFindPath = resp:gsub("{fileDir}", filepath.Dir(bp.buf.Path))

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

    micro.InfoBar():Message("Find Content called")

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

    micro.InfoBar():Message("finalCmd: ", finalCmd)

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
    -- TODO(NOW): Trverse the list

end




function TestECB(msg)
    micro.Log("TestECV called with message: ", msg)
end

function TestDoneCB(msg, cancelled)
    micro.Log("TestDoneCB called with message ", msg, " and cancelled ", cancelled)
end

function onAnyEvent()
    -- micro.Log("onAnyEvent called")
    if micro.CurPane() == nil or micro.CurPane().Cursor == nil then
        return
    end
    
    local currentCursorLoc = micro.CurPane().Cursor.Loc
    local bufPath = micro.CurPane().Buf.Path
    
    micro.Log("In ", bufPath, ":", currentCursorLoc.X, currentCursorLoc.Y)

    -- TODO(NOW):   Check if the cursor is different. 
    --              If so, check if it is because we are traversing in history. 
    --                  If not, check if we are at the of the history
    --                      If so, Just append the new history
    --                      If not, remove the rest of the list items, then append


    
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

    config.MakeCommand("OmniTest", OmniTest, config.NoComplete)
    config.MakeCommand("OmniTest2", OmniTest2, config.NoComplete)

  
end
