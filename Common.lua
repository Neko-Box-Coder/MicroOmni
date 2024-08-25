local micro = import("micro")
local config = import("micro/config")
local buffer = import("micro/buffer")
local util = import("micro/util")

local os = import("os")
local filepath = import("path/filepath")

local Self = {}

Self.OmniContentArgs = config.GetGlobalOption("OmniGlobalSearchArgs")
Self.OmniLocalSearchArgs = config.GetGlobalOption("OmniLocalSearchArgs")
Self.OmniGotoFileArgs = config.GetGlobalOption("OmniGotoFileArgs")
Self.OmniSelectType = config.GetGlobalOption("OmniSelectType")
Self.OmniHistoryLineDiff = config.GetGlobalOption("OmniHistoryLineDiff")
Self.OmniCanUseNewCursor = config.GetGlobalOption("OmniCanUseNewCursor")

-- TODO: Allow setting highlight to use regex or not

Self.OmniFzfCmd = config.GetGlobalOption("OmniFzfCmd")
Self.OmniNewFileMethod = config.GetGlobalOption("OmniNewFileMethod")


Self.OmniMinimapMaxIndent = config.GetGlobalOption("OmniMinimapMaxIndent")
Self.OmniMinimapContextNumLines = config.GetGlobalOption("OmniMinimapContextNumLines")
Self.OmniMinimapMinDistance = config.GetGlobalOption("OmniMinimapMinDistance")
Self.OmniMinimapMaxColumns = config.GetGlobalOption("OmniMinimapMaxColumns")
Self.OmniMinimapTargetNumLines = config.GetGlobalOption("OmniMinimapTargetNumLines")
Self.OmniMinimapScrollContent = config.GetGlobalOption("OmniMinimapScrollContent")



function Self.IsPathDir(path)
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

-- Grabbed from filemanager2
-- Stat a path to check if it exists, returning true/false
function Self.path_exists(path)
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


function Self.HandleOpenFile(path, bp, lineNum, gotoLineIfExists)
    if Self.OmniNewFileMethod == "smart_newtab" then
        Self.SmartNewTab(path, bp, lineNum, gotoLineIfExists)
        return
    end

    if Self.OmniNewFileMethod == "newtab" then
       bp:NewTabCmd({path})
    else
        local buf, err = buffer.NewBufferFromFile(path)
        if err ~= nil then return end
        
        if Self.OmniNewFileMethod == "vsplit" then
            bp:VSplitIndex(buf, true)
        elseif Self.OmniNewFileMethod == "hsplit" then
            bp:HSplitIndex(buf, true)
        else
            bp:OpenBuffer(buf)
        end
    end

    -- micro.Log("fzfParseOutput new buffer")
    micro.CurPane().Cursor:ResetSelection()
    micro.CurPane():GotoCmd({lineNum})
end

-- NOTE: lineNum is string
function Self.SmartNewTab(path, bp, lineNum, gotoLineIfExists)
    local cleanFilepath = filepath.Clean(path)
    
    -- If current pane is empty, we can open in it
    if not Self.path_exists(micro.CurPane().Buf.AbsPath) or Self.IsPathDir(micro.CurPane().Buf.AbsPath) then
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
            
            -- if currentBuf ~= nil then
            --     micro.Log("cleanFilepath:", cleanFilepath)
            --     micro.Log("currentBuf.AbsPath:", currentBuf.AbsPath)
            --     micro.Log("currentBuf.Path:", currentBuf.Path)
            -- end
            
            if  currentBuf ~= nil and 
                (filepath.Clean(currentBuf.AbsPath) == cleanFilepath or 
                filepath.Clean(currentBuf.Path) == cleanFilepath) then

                -- NOTE: SetActive functions has index starting at 0 instead lol
                micro.Tabs():SetActive(i - 1)
                micro.Tabs().List[i]:SetActive(j - 1)
                if gotoLineIfExists then
                    currentPane.Cursor:ResetSelection()
                    currentPane:GotoCmd({lineNum})
                end
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


function Self.LocBoundCheck(buf, loc)
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

return Self
