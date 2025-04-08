local micro = import("micro")
local config = import("micro/config")
local buffer = import("micro/buffer")
local util = import("micro/util")

local os = import("os")
local ioutil = import("io/ioutil")
local filepath = import("path/filepath")

local Self = {}

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


function Self.ToRelPath(path)
    local wd, err = os.Getwd()
    local pathCopy = path
    if err == nil then
        pathCopy = filepath.Clean(pathCopy)
        wd = filepath.Clean(wd)
        local relPath, relErr = filepath.Rel(wd, pathCopy)
        if relErr == nil and relPath ~= nil then
            return relPath
        end
    end
    return pathCopy
end

function Self.HandleOpenFile(path, bp, lineNum, gotoLineIfExists)
    -- Turn to relative path if possible
    local maybeRelPath = Self.ToRelPath(path)
    
    if config.GetGlobalOption("MicroOmni.NewFileMethod") == "smart_newtab" then
        Self.SmartNewTab(maybeRelPath, bp, lineNum, gotoLineIfExists)
        return
    end

    if config.GetGlobalOption("MicroOmni.NewFileMethod") == "newtab" then
       bp:NewTabCmd({maybeRelPath})
    else
        local buf, bufErr = buffer.NewBufferFromFile(maybeRelPath)
        if bufErr ~= nil then return end
        
        if config.GetGlobalOption("MicroOmni.NewFileMethod") == "vsplit" then
            bp:VSplitIndex(buf, true)
        elseif config.GetGlobalOption("MicroOmni.NewFileMethod") == "hsplit" then
            bp:HSplitIndex(buf, true)
        else
            bp:OpenBuffer(buf)
        end
    end

    -- micro.Log("fzfParseOutput new buffer")
    micro.CurPane().Cursor:ResetSelection()
    micro.CurPane():GotoCmd({lineNum})
end

function Self.OpenPaneIfExist(path)
    local cleanFilepath = filepath.Clean(path)
    local wd, wdErr = os.Getwd()
    for i = 1, #micro.Tabs().List do
        for j = 1, #micro.Tabs().List[i].Panes do
            local currentPane = micro.Tabs().List[i].Panes[j]
            local currentBuf = currentPane.Buf
            
            -- if currentBuf ~= nil then
            --     micro.Log("cleanFilepath:", cleanFilepath)
            --     micro.Log("currentBuf.AbsPath:", currentBuf.AbsPath)
            --     micro.Log("currentBuf.Path:", currentBuf.Path)
            -- end
            
            if currentBuf ~= nil and currentBuf.AbsPath ~= nil and currentBuf.AbsPath ~= "" then
                local calculatedAbsPath = filepath.Abs(cleanFilepath)
                if not filepath.IsAbs(cleanFilepath) and wdErr == nil then
                    local absPath, absErr = filepath.Abs(filepath.Join(wd, cleanFilepath))
                    -- micro.Log("absPath:", absPath)
                    if absErr == nil then
                        calculatedAbsPath = absPath
                    end
                end
                -- micro.Log("calculatedAbsPath:", calculatedAbsPath)
                
                if  filepath.Clean(currentBuf.AbsPath) == calculatedAbsPath or
                    filepath.Clean(currentBuf.AbsPath) == cleanFilepath or 
                    filepath.Clean(currentBuf.Path) == cleanFilepath then

                    -- NOTE: SetActive functions has index starting at 0 instead lol
                    micro.Tabs():SetActive(i - 1)
                    micro.Tabs().List[i]:SetActive(j - 1)
                    return true
                end
            end
        end
    end
    
    return false
end

-- NOTE: lineNum is string
function Self.SmartNewTab(path, bp, lineNum, gotoLineIfExists)
    local cleanFilepath = filepath.Clean(path)
    -- micro.Log("cleanFilepath:", cleanFilepath)
    
    -- micro.Log("path:", path)
    -- micro.Log("cleanFilepath:", cleanFilepath)
    
    -- micro.Log("micro.CurPane().Buf.AbsPath:", micro.CurPane().Buf.AbsPath)
    
    -- If current pane is empty, we can open in it
    if not Self.path_exists(micro.CurPane().Buf.AbsPath) or Self.IsPathDir(micro.CurPane().Buf.AbsPath) then
        -- micro.Log("#micro.CurPane().Buf:Bytes():", #micro.CurPane().Buf:Bytes())
        if #micro.CurPane().Buf:Bytes() == 0 then
            bp:OpenCmd({cleanFilepath})
            micro.CurPane():GotoCmd({lineNum})
            return
        end
    end

    -- Otherwise find if there's any existing panes
    if Self.OpenPaneIfExist(cleanFilepath) then
        if gotoLineIfExists then
            micro.CurPane().Cursor:ResetSelection()
            micro.CurPane():GotoCmd({lineNum})
        end
        return
    end
    -- currentPane:Relocate()
    
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

function Self.CreateRuntimeFile(relativePath, data)
    local microOmniDir = config.ConfigDir.."/plug/MicroOmni/"
    if not Self.path_exists(filepath.Dir(microOmniDir..relativePath)) then
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

return Self
