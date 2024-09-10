local micro = import("micro")
local util = import("micro/util")
local filepath = import("path/filepath")
local shell = import("micro/shell")
local config = import("micro/config")

local os = import("os")
local runtime = import("runtime")
local fmt = import('fmt')

package.path = fmt.Sprintf('%s;%s/plug/MicroOmni/?.lua', package.path, config.ConfigDir)
local Common = require("Common")


local OmniContentFindPath = ""
local OmniSearchText = ""

local Self = {}

-- NOTE: lineNum is string
local function fzfParseOutput(output, bp, lineNum, gotoLineIfExists)
    micro.Log("fzfParseOutput called")
    if output ~= "" then
        local file = string.gsub(output, "[\n\r]", "")
        if file == nil then
            return
        end
        Common.HandleOpenFile(file, bp, lineNum, gotoLineIfExists)
    end
end

local function getOS()
    if runtime.GOOS == "windows" then
        return "Windows"
    else
        return "Unix"
    end
end

local function FindContent(str, searchLoc)
    micro.Log("Find Content called")
    local bp = micro.CurPane()
    local selectedText = str
    local fzfArgs
    -- micro.Log("selectedText before: ", selectedText)
    -- micro.Log("Common.OmniContentArgs before: ", common.OmniContentArgs)

    local firstWord, _ = selectedText:match("^(.[^%s]*)%s-(.*)$")

    if firstWord == nil or firstWord == "" then
        micro.InfoBar():Error("Failed to extract first word... str: ", str)
        return
    end

    local currentOS = getOS()
    local finalCmd;
    if currentOS == "Unix" then
        selectedText = selectedText:gsub("'", "'\\''")
        firstWord = firstWord:gsub("'", "'\\''")
        fzfArgs = Common.OmniContentArgs:gsub("'", "'\\''")
        finalCmd =  "rg -F -i -uu -n '\\''"..firstWord.."'\\'' | "..Common.OmniFzfCmd.." "..fzfArgs..
                    " -q '\\''"..selectedText.."'\\''"
    else
        selectedText = selectedText:gsub("'", '"')
        firstWord = firstWord:gsub("'", '""')
        fzfArgs = Common.OmniContentArgs:gsub("'", '"')
        finalCmd =  "rg -F -i -uu -n \""..firstWord.."\" | "..Common.OmniFzfCmd.." "..fzfArgs..
                    " -q \""..selectedText.."\""
    end

    if currentOS == "Unix" then
        finalCmd = "sh -c \'"..finalCmd.."\'"
    else
        finalCmd = "cmd /s /v /c "..finalCmd..""
    end

    micro.Log("Running search cmd: ", finalCmd)

    local currentLoc = os.Getwd()
    if searchLoc ~= nil and searchLoc ~= "" then
        if not Common.path_exists(searchLoc) then
            micro.InfoBar():Error("", searchLoc, " doesn't exist")
            return
        end

        if not Common.IsPathDir(searchLoc) then
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
        
        fzfParseOutput(path, bp, lineNumber, true)
    end
end

local function OnFindPromptDone(resp, cancelled)
    if cancelled then return end
    FindContent(resp, OmniContentFindPath)
    return
end

local function OnSearchDirSetDone(resp, cancelled)
    if cancelled then return end

    local bp = micro.CurPane()
    if bp == nil then return end
    
    OmniContentFindPath = resp:gsub("{fileDir}", filepath.Dir(bp.Buf.AbsPath))
    micro.InfoBar():Prompt("Content to find > ", OmniSearchText, "", nil, OnFindPromptDone)
end


function Self.OmniContent(bp)
    OmniSearchText = ""
    if bp.Cursor:HasSelection() then
        OmniSearchText = bp.Cursor:GetSelection()
        OmniSearchText = util.String(OmniSearchText)
    end
    
    micro.InfoBar():Prompt( "Search Directory ({fileDir} for current file directory) > ", 
                            "", 
                            "", 
                            nil, 
                            OnSearchDirSetDone)
end



function Self.OmniLocalSearch(bp, args)
    local localSearchArgs = Common.OmniLocalSearchArgs:gsub("{filePath}", "\""..bp.buf.AbsPath.."\"")

    if bp.Cursor:HasSelection() then
        localSearchArgs = localSearchArgs.." -q '"..util.String(bp.Cursor:GetSelection()).."'"
    end

    local output, err = shell.RunInteractiveShell(Common.OmniFzfCmd.." "..localSearchArgs, false, true)

    if err ~= nil or output == "" then
        -- micro.InfoBar():Error("Error is: ", err:Error())
    else
        local lineNumber = output:match("^%s*(.-)%s.*")
        -- micro.InfoBar():Message("Output is ", output, " and extracted lineNumber is ", lineNumber)
        micro.CurPane().Cursor:ResetSelection()
        micro.CurPane():GotoCmd({lineNumber})
        micro.CurPane():Center()
    end
end


function Self.OmniGotoFile(bp)
    local localGotoFileArgs = Common.OmniGotoFileArgs
    if bp.Cursor:HasSelection() then
        localGotoFileArgs = localGotoFileArgs.." -q '"..util.String(bp.Cursor:GetSelection()).."'"
    end

    local output, err = shell.RunInteractiveShell(Common.OmniFzfCmd.." "..localGotoFileArgs, false, true)

    if err ~= nil or output == "" then
        -- micro.InfoBar():Error("Error is: ", err:Error())
    else
        -- local lineNumber = output:match("^%s*(.-)%s.*")
        -- local path, lineNumber = output:match("^(.-):%s*(%d+):")
        
        -- micro.InfoBar():Message("Output is ", output, " and extracted lineNumber is ", lineNumber)
        fzfParseOutput(output, bp, "1", false)
    end
end

return Self
