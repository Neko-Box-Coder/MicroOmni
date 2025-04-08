local micro = import("micro")
local config = import("micro/config")
local buffer = import("micro/buffer")
local util = import("micro/util")
local ioutil = import("io/ioutil")
local filepath = import("path/filepath")
local strings = import("strings")
local goos = import("os")

local Common = require("Common")

local Session = {}

-- Directory where sessions will be stored
local sessionsDir = "sessions"

-- Get the path to a session file
local function getSessionFilePath(sessionName, useWorkingDir)
    if useWorkingDir then
        local wd, err = goos.Getwd()
        if err ~= nil then
            micro.InfoBar():Error("Failed to get working directory:", err)
            return nil
        end
        return filepath.Join(wd, sessionName .. ".omnisession")
    else
        local microOmniDir = config.ConfigDir.."/plug/MicroOmni/"
        local sessionsPath = filepath.Join(microOmniDir, sessionsDir)
        return filepath.Join(sessionsPath, sessionName .. ".omnisession")
    end
end

-- List available sessions
local function listSessions(useWorkingDir)
    local sessions = {}
    
    if not useWorkingDir then
        -- Get sessions from plugin directory
        local microOmniDir = config.ConfigDir.."/plug/MicroOmni/"
        local sessionsPath = filepath.Join(microOmniDir, sessionsDir)
        
        if not Common.path_exists(sessionsPath) then
            return {}
        end
        
        local files, err = ioutil.ReadDir(sessionsPath)
        if err ~= nil then
            micro.InfoBar():Error("Failed to read sessions directory:", err)
            return {}
        end
        
        for i = 1, #files do
            local fileName = files[i]:Name()
            if string.match(fileName, "%.omnisession$") then
                table.insert(sessions, string.sub(fileName, 1, -13)) -- remove .omnisession extension
            end
        end
    else
        -- Get sessions from current working directory
        local wd, err = goos.Getwd()
        if err ~= nil then
            micro.InfoBar():Error("Failed to get working directory:", err)
            return {}
        end
        
        local files, err2 = ioutil.ReadDir(wd)
        if err2 ~= nil then
            micro.InfoBar():Error("Failed to read working directory:", err2)
            return {}
        end
        
        for i = 1, #files do
            local fileName = files[i]:Name()
            if string.match(fileName, "%.omnisession$") then
                table.insert(sessions, string.sub(fileName, 1, -13)) -- remove .omnisession extension
            end
        end
    end
    
    return sessions
end

-- Save current session
function Session.SaveSession(bp, args, useWorkingDir)
    if useWorkingDir == nil then
        useWorkingDir = false
    end
    
    if #args < 1 then
        micro.InfoBar():Error("Please provide a session name")
        return
    end
    
    local sessionName = args[1]
    local sessionData = ""
    
    -- Iterate through tabs and panes to save all open files
    for i = 1, #micro.Tabs().List do
        local tab = micro.Tabs().List[i]
        local tabData = {}
        
        for j = 1, #tab.Panes do
            local pane = tab.Panes[j]
            local buf = pane.Buf
            
            if buf ~= nil and buf.Path ~= "" then
                -- Save file path and cursor line number
                local cursor = pane.Cursor
                local fileData = buf.AbsPath .. ":" .. tostring(cursor.Loc.Y + 1)
                table.insert(tabData, fileData)
            end
        end
        
        if #tabData > 0 then
            sessionData = sessionData .. table.concat(tabData, ",") .. "\n"
        end
    end
    
    -- Write to file
    local sessionFilePath = getSessionFilePath(sessionName, useWorkingDir)
    if sessionFilePath == nil then
        return
    end
    
    local err = ioutil.WriteFile(sessionFilePath, sessionData, goos.ModePerm)
    local success = (err == nil)
    
    if not success then
        micro.InfoBar():Error("Failed to save session: " .. sessionName)
    else
        micro.InfoBar():Message("Session '" .. sessionName .. "' saved" .. 
                                (useWorkingDir and " to working directory" or ""))
    end
end

-- Load a session
function Session.LoadSession(bp, args, useWorkingDir)
    if useWorkingDir == nil then
        useWorkingDir = false
    end
    
    if #args < 1 then
        -- List available sessions if no session name provided
        local sessions = listSessions(useWorkingDir)
        if #sessions == 0 then
            micro.InfoBar():Message("No saved sessions found" .. 
                                    (useWorkingDir and " in working directory" or ""))
        else
            micro.InfoBar():Message("Available sessions" .. 
                                    (useWorkingDir and " in working directory" or "") .. 
                                    ": " .. table.concat(sessions, ", "))
        end
        return
    end
    
    local sessionName = args[1]
    local sessionFilePath = getSessionFilePath(sessionName, useWorkingDir)
    if sessionFilePath == nil then
        return
    end
    
    if not Common.path_exists(sessionFilePath) then
        micro.InfoBar():Error("Session '" .. sessionName .. "' not found")
        -- micro.InfoBar():Error("Session '" .. sessionFilePath .. "' not found")
        return
    end
    
    local data, err = ioutil.ReadFile(sessionFilePath)
    if err ~= nil then
        micro.InfoBar():Error("Failed to read session file:", err)
        return
    end
    
    local sessionStr = util.String(data)
    
    -- Process session data
    local lines = {}
    for line in string.gmatch(sessionStr, "[^\r\n]+") do
        table.insert(lines, line)
    end
    
    local originalTabIdx = 0
    -- local originalPaneIdx = 0
    
    for i = 1, #micro.Tabs().List do
        if micro.Tabs().List[i]:ID() == bp:Tab():ID() then
            originalTabIdx = i - 1
            break
        end
    end

    -- for i = 1, #bp:Tab().Panes do
    --     if bp:Tab().Panes[i]:ID() == bp:ID() then
    --         originalPaneIdx = i - 1
    --         break
    --     end
    -- end
    
    for _, line in ipairs(lines) do
        local files = {}
        local lineNumbers = {}
        
        for fileData in string.gmatch(line, "[^,]+") do
            -- Parse file path and line number
            local filePath, lineNum = string.match(fileData, "(.+):(%d+)")
            
            if filePath == nil then
                -- No line number in the file data
                filePath = fileData
                lineNum = "1" -- Default to line 1
            end
            
            table.insert(files, filePath)
            table.insert(lineNumbers, tonumber(lineNum))
        end
        
        if #files > 0 then
            -- Create new tabs for files
            Common.SmartNewTab( Common.ToRelPath(files[1]), 
                                micro.CurPane(), 
                                tostring(lineNumbers[1]), 
                                false)
            
            -- Create splits for additional files in this tab
            if #files > 1 then
                for i = 2, #files do
                    if Common.path_exists(files[i]) then
                        local buf, _ = buffer.NewBufferFromFile(Common.ToRelPath(files[i]))
                        
                        if buf ~= nil then
                            if i % 2 == 0 then
                                micro.CurPane():VSplitIndex(buf, true)
                            else
                                micro.CurPane():HSplitIndex(buf, true)
                            end
                            
                            -- Set cursor position for this pane to the saved line number
                            micro.CurPane():GotoCmd({tostring(lineNumbers[i])})
                        end
                    end
                end
            end
        end
    end
    
    micro.Tabs():SetActive(originalTabIdx)
    -- micro.Tabs().List[originalTabIdx + 1]:SetActive(originalPaneIdx)
    micro.InfoBar():Message("Session '" .. sessionName .. "' loaded" .. 
                            (useWorkingDir and " from working directory" or ""))
    -- micro.InfoBar():Message("Loaded " .. sessionFilePath)
end

-- List available sessions
function Session.ListSessions(bp, args, useWorkingDir)
    if useWorkingDir == nil then
        useWorkingDir = false
    end
    
    local sessions = listSessions(useWorkingDir)
    
    if #sessions == 0 then
        micro.InfoBar():Message("No saved sessions found" .. 
                                (useWorkingDir and " in working directory" or ""))
    else
        micro.InfoBar():Message("Available sessions" .. 
                                (useWorkingDir and " in working directory" or "") .. 
                                ": " .. table.concat(sessions, ", "))
    end
end

-- Delete a session
function Session.DeleteSession(bp, args, useWorkingDir)
    if useWorkingDir == nil then
        useWorkingDir = false
    end
    
    if #args < 1 then
        micro.InfoBar():Error("Please provide a session name to delete")
        return
    end
    
    local sessionName = args[1]
    local sessionFilePath = getSessionFilePath(sessionName, useWorkingDir)
    if sessionFilePath == nil then
        return
    end
    
    if not Common.path_exists(sessionFilePath) then
        micro.InfoBar():Error("Session '" .. sessionName .. "' not found")
        return
    end
    
    local err = goos.Remove(sessionFilePath)
    if err ~= nil then
        micro.InfoBar():Error("Failed to delete session:", err)
    else
        micro.InfoBar():Message("Session '" .. sessionName .. "' deleted" .. 
                                (useWorkingDir and " from working directory" or ""))
    end
end

-- Local session commands
function Session.SaveSessionLocal(bp, args)
    Session.SaveSession(bp, args, true)
end

function Session.LoadSessionLocal(bp, args)
    Session.LoadSession(bp, args, true)
end

function Session.ListSessionsLocal(bp, args)
    Session.ListSessions(bp, args, true)
end

function Session.DeleteSessionLocal(bp, args)
    Session.DeleteSession(bp, args, true)
end

-- Tab completion for session names
function Session.SessionCompleter(buf)
    local activeCursor = buf:GetActiveCursor()
    local input, argstart = buf:GetArg()
    
    local sessions = listSessions(false)
    local suggestions = {}
    
    for _, session in ipairs(sessions) do
        if strings.HasPrefix(session, input) then
            table.insert(suggestions, session)
        end
    end
    
    table.sort(suggestions, function(a, b) return a:upper() < b:upper() end)
    
    local completions = {}
    for _, suggestion in ipairs(suggestions) do
        local offset = activeCursor.X - argstart
        table.insert(completions, string.sub(suggestion, offset + 1, string.len(suggestion)))
    end
    
    return completions, suggestions
end

-- Tab completion for local session names
function Session.SessionCompleterLocal(buf)
    local activeCursor = buf:GetActiveCursor()
    local input, argstart = buf:GetArg()
    
    local sessions = listSessions(true)
    local suggestions = {}
    
    for _, session in ipairs(sessions) do
        if strings.HasPrefix(session, input) then
            table.insert(suggestions, session)
        end
    end
    
    table.sort(suggestions, function(a, b) return a:upper() < b:upper() end)
    
    local completions = {}
    for _, suggestion in ipairs(suggestions) do
        local offset = activeCursor.X - argstart
        table.insert(completions, string.sub(suggestion, offset + 1, string.len(suggestion)))
    end
    
    return completions, suggestions
end

-- Auto-save functionality
local lastAutoSaveTime = 0

-- Check if auto-save should be performed
function Session.CheckAutoSave()
    if not config.GetGlobalOption("MicroOmni.AutoSaveEnabled") then
        return
    end
    
    local currentTime = os.time()
    if lastAutoSaveTime == 0 then
        lastAutoSaveTime = currentTime
    end
    
    local lastRunTimeDiff = os.difftime(os.time(), lastAutoSaveTime)
    if lastRunTimeDiff >= config.GetGlobalOption("MicroOmni.AutoSaveInterval") then
        lastAutoSaveTime = currentTime
        if config.GetGlobalOption("MicroOmni.AutoSaveToLocal") then
            Session.SaveSessionLocal(micro.CurPane(), {config.GetGlobalOption("MicroOmni.AutoSaveName")})
        else
            Session.SaveSession(micro.CurPane(), {config.GetGlobalOption("MicroOmni.AutoSaveName")})
        end
    end
end

return Session 
