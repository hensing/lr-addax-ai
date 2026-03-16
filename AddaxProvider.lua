--[[----------------------------------------------------------------------------
AddaxProvider.lua
Provides the Plugin Manager settings sections.
------------------------------------------------------------------------------]]

local LrView = import 'LrView'
local LrBinding = import 'LrBinding'
local LrPathUtils = import 'LrPathUtils'
local LrFileUtils = import 'LrFileUtils'
local LrDialogs = import 'LrDialogs'
local LrPrefs = import 'LrPrefs'

local prefs = LrPrefs.prefsForPlugin()

local function startDialog(propertyTable)
    -- Load preferences into the property table for the dialog
    propertyTable.addaxPath = prefs.addaxPath or '/Applications/AddaxAI_files'
    propertyTable.exportRes = tonumber(prefs.exportRes) or 2048
    propertyTable.exportQuality = tonumber(prefs.exportQuality) or 60
    propertyTable.keywordThreshold = tonumber(prefs.keywordThreshold) or 90
    propertyTable.modelPath = prefs.modelPath or ""
    propertyTable.reportDestType = prefs.reportDestType or "none"
    propertyTable.reportCustomPath = prefs.reportCustomPath or LrPathUtils.getStandardFilePath('desktop')
    propertyTable.excludeList = prefs.excludeList or "person, vehicle"
    propertyTable.logging = prefs.logging or false

    -- Add observer to instantly apply logging preference when clicked
    propertyTable:addObserver('logging', function(propertyTable, key, value)
        prefs.logging = value
        if value then
            _G.log:enable('logfile')
        else
            _G.log:enable('print')
        end
    end)
end

local function endDialog(propertyTable)
    -- Save preferences from the dialog back to the Lightroom prefs system
    prefs.addaxPath = propertyTable.addaxPath
    prefs.exportRes = propertyTable.exportRes
    prefs.exportQuality = propertyTable.exportQuality
    prefs.keywordThreshold = propertyTable.keywordThreshold
    prefs.modelPath = propertyTable.modelPath
    prefs.reportDestType = propertyTable.reportDestType
    prefs.reportCustomPath = propertyTable.reportCustomPath
    prefs.excludeList = propertyTable.excludeList
    prefs.logging = propertyTable.logging
end

local function sectionsForTopOfDialog(f, propertyTable)
    local bind = LrView.bind
    local share = LrView.share

    -- Helper function to scan for Addax-AI models recursively (in subfolders)
    local function getModels()
        local models = {}
        local path = propertyTable.addaxPath
        if type(path) == "string" and path ~= "" then
            local clsDir = LrPathUtils.child(path, "models/cls")
            pcall(function()
                if LrFileUtils.exists(clsDir) then
                    for folder in LrFileUtils.directoryEntries(clsDir) do
                        if LrFileUtils.exists(folder) and LrFileUtils.directoryEntries(folder) then
                            for file in LrFileUtils.directoryEntries(folder) do
                                if file:lower():match("%.pt$") or file:lower():match("%.onnx$") then
                                    local modelName = LrPathUtils.leafName(folder) .. " (" .. LrPathUtils.leafName(file) .. ")"
                                    table.insert(models, { title = modelName, value = file })
                                end
                            end
                        end
                    end
                end
            end)
        end
        
        if #models == 0 then
            table.insert(models, { title = "No models found (Check path)", value = "" })
        end
        
        return models
    end

    -- Store model items in propertyTable to trigger dynamic UI updates upon path changes
    propertyTable.modelItems = getModels()

    return {
        {
            title = "Addax-AI Configuration",
            bind_to_object = propertyTable,
            f:row {
                f:static_text {
                    title = "Addax-AI Path:",
                    width = share 'label_width',
                },
                f:edit_field {
                    value = bind 'addaxPath',
                    width_in_chars = 30,
                },
                f:push_button {
                    title = "Browse...",
                    action = function()
                        local path = LrDialogs.runOpenPanel({
                            title = "Select Addax-AI Files Folder",
                            canChooseDirectories = true,
                            canChooseFiles = false,
                            allowsMultipleSelection = false,
                        })
                        if path and #path > 0 then
                            propertyTable.addaxPath = path[1]
                            propertyTable.modelItems = getModels()
                            if propertyTable.modelItems[1].value ~= "" then
                                propertyTable.modelPath = propertyTable.modelItems[1].value
                            else
                                propertyTable.modelPath = ""
                            end
                        end
                    end,
                },
            },
            f:row {
                f:static_text {
                    title = "Classification Model:",
                    width = share 'label_width',
                },
                f:popup_menu {
                    value = bind 'modelPath',
                    items = bind 'modelItems',
                    width = 250,
                },
                f:push_button {
                    title = "Refresh",
                    action = function()
                        propertyTable.modelItems = getModels()
                        if propertyTable.modelPath == "" and propertyTable.modelItems[1].value ~= "" then
                            propertyTable.modelPath = propertyTable.modelItems[1].value
                        end
                    end,
                },
            },
            f:row {
                f:static_text {
                    title = "Save JSON Report:",
                    width = share 'label_width',
                },
                f:popup_menu {
                    value = bind 'reportDestType',
                    items = {
                        { title = "Do not save", value = "none" },
                        { title = "Same folder as original picture", value = "same" },
                        { title = "Custom folder...", value = "custom" },
                    },
                    width = 250,
                },
            },
            f:row {
                f:static_text {
                    title = "Custom Folder Path:",
                    width = share 'label_width',
                    enabled = LrBinding.negativeOfKey('reportDestType', "custom", true),
                },
                f:edit_field {
                    value = bind 'reportCustomPath',
                    width_in_chars = 30,
                    enabled = LrBinding.negativeOfKey('reportDestType', "custom", true),
                },
                f:push_button {
                    title = "Browse...",
                    enabled = LrBinding.negativeOfKey('reportDestType', "custom", true),
                    action = function()
                        local path = LrDialogs.runOpenPanel({
                            title = "Select Report Folder",
                            canChooseDirectories = true,
                            canChooseFiles = false,
                            allowsMultipleSelection = false,
                        })
                        if path and #path > 0 then
                            propertyTable.reportCustomPath = path[1]
                        end
                    end,
                },
            },
            f:row {
                f:checkbox {
                    title = "Enable Diagnostic Logging (saves Addax_DebugLog.txt to Desktop)",
                    value = bind 'logging',
                },
            },
        },
        {
            title = "Filter & Analysis Settings",
            bind_to_object = propertyTable,
            f:row {
                f:static_text {
                    title = "Excluded Classes:",
                    width = share 'label_width',
                },
                f:edit_field {
                    value = bind 'excludeList',
                    width_in_chars = 30,
                },
            },
            f:row {
                f:static_text {
                    title = "",
                    width = share 'label_width',
                },
                f:static_text {
                    title = "(Comma-separated categories to skip, e.g. person, vehicle)",
                    font_size = "small",
                },
            },
            f:row {
                f:static_text {
                    title = "Resolution (px):",
                    width = share 'label_width',
                },
                f:edit_field {
                    value = bind 'exportRes',
                    width_in_chars = 5,
                    validate = function(view, value)
                        local n = tonumber(value)
                        if n and n >= 320 and n <= 4096 then return true, n end
                        return false, value, "Value must be a number between 320 and 4096."
                    end
                },
                f:static_text {
                    title = "(Long edge for temporary JPEG)",
                },
            },
            f:row {
                f:static_text {
                    title = "Keyword Confidence Threshold:",
                    width = share 'label_width',
                },
                f:slider {
                    value = bind 'keywordThreshold',
                    min = 0,
                    max = 100,
                    width = 150,
                },
                f:static_text {
                    title = bind 'keywordThreshold',
                },
                f:static_text {
                    title = "%",
                },
            },
            f:row {
                f:static_text {
                    title = "",
                    width = share 'label_width',
                },
                f:static_text {
                    title = "(Only import species keywords with at least this confidence)",
                    font_size = "small",
                },
            },
            f:row {
                f:static_text {
                    title = "JPEG Quality:",
                    width = share 'label_width',
                },
                f:slider {
                    value = bind 'exportQuality',
                    min = 10,
                    max = 100,
                    width = 150,
                },
                f:static_text {
                    title = bind 'exportQuality',
                },
            },
        },
    }
end

return {
    startDialog = startDialog,
    endDialog = endDialog,
    sectionsForTopOfDialog = sectionsForTopOfDialog
}
