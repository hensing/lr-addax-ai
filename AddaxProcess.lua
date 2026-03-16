local LrApplication = import 'LrApplication'
local LrTasks = import 'LrTasks'
local LrDialogs = import 'LrDialogs'
local LrExportSession = import 'LrExportSession'
local LrPathUtils = import 'LrPathUtils'
local LrFileUtils = import 'LrFileUtils'
local LrErrors = import 'LrErrors'
local LrFunctionContext = import 'LrFunctionContext'
local LrPrefs = import 'LrPrefs'
local LrLogger = import 'LrLogger'
local LrProgressScope = import 'LrProgressScope'

-- External modules
local AddaxKeywords = require 'AddaxKeywords'

local logger = import 'LrLogger'('AddaxProcess')
local prefs = LrPrefs.prefsForPlugin()
local catalog = LrApplication.activeCatalog()

-- --- LOGGING HELPERS ---

--- Logs professional status messages to the Desktop DebugLog.
-- @param msg The message to log.
local function debugLog(msg)
    if prefs.logging then
        local desktop = LrPathUtils.getStandardFilePath('desktop')
        local logPath = LrPathUtils.child(desktop, "Addax_DebugLog.txt")
        local f = io.open(logPath, "a")
        if f then
            f:write(os.date("%H:%M:%S") .. " - " .. tostring(msg) .. "\n")
            f:close()
        end
    end
end

-- --- REPORT MANAGEMENT ---

--- Saves the Addax-AI results JSON to the user-specified destination.
-- @param outputJson Path to the generated results JSON.
-- @param samplePhotoPaths List of original paths to determine the destination folder.
-- @param reportDestType The user preference for destination.
-- @param reportCustomPath The custom directory path if selected.
local function saveReport(outputJson, samplePhotoPaths, reportDestType, reportCustomPath)
    if LrFileUtils.exists(outputJson) and reportDestType ~= "none" then
        local baseName = "addax_report_" .. os.date("%Y%m%d_%H%M%S") .. ".json"
        local finalDest = nil
        
        if reportDestType == "same" and #samplePhotoPaths > 0 then
            local parentFolder = LrPathUtils.parent(samplePhotoPaths[1])
            if parentFolder then finalDest = LrPathUtils.child(parentFolder, baseName) end
        elseif reportDestType == "custom" and reportCustomPath ~= "" then
            if LrFileUtils.exists(reportCustomPath) then finalDest = LrPathUtils.child(reportCustomPath, baseName) end
        end
        
        if finalDest then 
            LrFileUtils.copy(outputJson, finalDest) 
            debugLog("Analysis report saved to: " .. finalDest)
        end
    end
end

-- --- MAIN WORKFLOW HANDLER ---

import 'LrTasks'.startAsyncTask(function()
    LrFunctionContext.callWithContext("AddaxAnalysis", function(context)
        -- Identify user selection
        local targetPhotos = catalog:getTargetPhotos()
        if #targetPhotos == 0 then return end
        
        debugLog("Initializing new analysis session...")

        -- Initialize session state
        local pathMap = {}
        local prefs = LrPrefs.prefsForPlugin()
        local addaxPath = prefs.addaxPath or '/Applications/AddaxAI_files'
        local modelPath = prefs.modelPath or ""
        local exportRes = tonumber(prefs.exportRes) or 2048
        local exportQuality = tonumber(prefs.exportQuality) or 60
        local keywordThreshold = (tonumber(prefs.keywordThreshold) or 90) / 100
        local reportDestType = prefs.reportDestType or "none"
        local reportCustomPath = prefs.reportCustomPath or ""
        local excludeListRaw = prefs.excludeList or "person, vehicle"
        
        -- Build exclusion table for the keyword phase
        local excludes = {}
        for item in excludeListRaw:gmatch("([^,%s]+)") do excludes[item:lower()] = true end

        -- Setup clean temporary workspace
        local tempDir = LrPathUtils.child(LrPathUtils.getStandardFilePath('temp'), "AddaxLR_Session")
        if LrFileUtils.exists(tempDir) then LrFileUtils.delete(tempDir) end
        LrFileUtils.createAllDirectories(tempDir)
        
        local progress = import 'LrProgressScope' { title = "Addax-AI Analysis", functionContext = context }
        progress:setCaption("Phase 1: Generating image previews...")

        -- Collect photos for export (Lightroom exports JPEGs for both images and videos)
        local photosToProcess = {}
        for _, photo in ipairs(targetPhotos) do
            table.insert(photosToProcess, photo)
        end

        -- Perform export and build the preview-to-catalog mapping
        if #photosToProcess > 0 then
            local exportSettings = {
                LR_format = "JPEG", LR_export_destinationType = "specificFolder", LR_export_destinationPathPrefix = tempDir,
                LR_export_useSubfolder = false, LR_overwritePolicy = "overwrite", LR_size_doConstrain = true,
                LR_size_maxSide = exportRes, LR_jpeg_quality = exportQuality / 100, LR_metadata_filterMode = "all",
            }
            local exportSession = LrExportSession({ photosToExport = photosToProcess, exportSettings = exportSettings })
            for i, rendition in exportSession:renditions() do
                if progress:isCanceled() then return end
                local status = rendition:waitForRender()
                if status then
                    local exportedName = LrPathUtils.leafName(rendition.destinationPath)
                    local originalPath = rendition.photo:getRawMetadata('path')
                    pathMap[exportedName] = originalPath
                end
                progress:setPortionComplete(i / #targetPhotos * 0.33)
            end
        end

        -- Configure Python environment and script paths
        local isWin = (LrPathUtils.getStandardFilePath('appData'):find(":") ~= nil)
        local pythonExe = LrPathUtils.child(addaxPath, isWin and "envs\\env-pytorch\\python.exe" or "envs/env-pytorch/bin/python")
        local scriptPath = LrPathUtils.child(_PLUGIN.path, "scripts/addax_bridge.py")
        local outputJson = LrPathUtils.child(tempDir, "results.json")
        local pythonDebugLog = LrPathUtils.child(LrPathUtils.getStandardFilePath('desktop'), "Addax_PythonDebug.txt")
        
        -- Build the search path for the Python sub-process
        local ctPath = LrPathUtils.child(addaxPath, "cameratraps")
        local mdPath = LrPathUtils.child(ctPath, "megadetector")
        local aiPath = LrPathUtils.child(addaxPath, "AddaxAI")
        local yoloPath = LrPathUtils.child(addaxPath, "yolov5_versions/yolov5_new/yolov5")
        local sep = isWin and ";" or ":"
        local pyPath = string.format("%s%s%s%s%s%s%s%s%s", yoloPath, sep, mdPath, sep, ctPath, sep, aiPath, sep, addaxPath)

        local cmd = string.format('"%s" "%s" --addax-path "%s" --model-path "%s" --image-dir "%s" --output-json "%s" --exclude "%s" > "%s" 2>&1',
            pythonExe, scriptPath, addaxPath, modelPath, tempDir, outputJson, excludeListRaw, pythonDebugLog)

        -- Execute the Addax-AI bridge
        progress:setCaption("Phase 2: Addax-AI core processing...")
        if isWin then
            local script = LrPathUtils.child(tempDir, "run.bat")
            local f = io.open(script, "w")
            if f then 
                f:write('@echo off\r\n')
                f:write(string.format('set PYTHONPATH=%s;%%PYTHONPATH%%\r\n', pyPath))
                f:write(cmd .. '\r\n')
                f:close() 
            end
            import 'LrTasks'.execute('cmd.exe /c "' .. script .. '"')
        else
            -- Pre-set PYTHONPATH and execute via AppleScript for best macOS compatibility
            local fullCmd = string.format('export PYTHONPATH="%s":$PYTHONPATH && %s', pyPath, cmd)
            local appleScript = string.format('osascript -e \'do shell script "%s"\'', fullCmd:gsub('"', '\\"'))
            import 'LrTasks'.execute(appleScript)
        end
        
        -- Safeguard the analysis results before any cleanup or import failures
        local samplePaths = {}
        for _, path in pairs(pathMap) do table.insert(samplePaths, path) end
        saveReport(outputJson, samplePaths, reportDestType, reportCustomPath)

        -- Final verification of Python output
        if not LrFileUtils.exists(outputJson) then
            local errorMsg = "Core engine failed to generate results."
            if LrFileUtils.exists(pythonDebugLog) then
                local content = LrFileUtils.readFile(pythonDebugLog)
                if content and content ~= "" then errorMsg = content end
            end
            progress:done()
            LrDialogs.message("Addax-AI Error", "Analysis Failure:\n\n" .. errorMsg, "critical")
            LrFileUtils.delete(tempDir)
            return
        end

        -- Final Phase: Keyword Synchronization
        progress:setCaption("Phase 3: Synchronizing with catalog...")
        local count = 0
        catalog:withWriteAccessDo("Addax AI Synchronization", function(context)
            count = AddaxKeywords.synchronize(catalog, LrPathUtils.child(tempDir, "keywords.txt"), pathMap, excludes, keywordThreshold)
        end)
        
        -- Summary and Cleanup
        LrDialogs.message("Addax-AI", string.format("Processing complete!\n\nMatched %d photo(s).", count), "info")
        debugLog("Cleaning up session data...")
        LrFileUtils.delete(tempDir)
        debugLog("Session finished.")
        progress:done()
    end)
end)
