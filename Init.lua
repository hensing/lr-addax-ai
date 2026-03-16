---@diagnostic disable: undefined-global

-- Global imports
_G.LrHttp = import 'LrHttp'
_G.LrDate = import 'LrDate'
_G.LrPathUtils = import 'LrPathUtils'
_G.LrFileUtils = import 'LrFileUtils'
_G.LrTasks = import 'LrTasks'
_G.LrErrors = import 'LrErrors'
_G.LrDialogs = import 'LrDialogs'
_G.LrView = import 'LrView'
_G.LrBinding = import 'LrBinding'
_G.LrColor = import 'LrColor'
_G.LrFunctionContext = import 'LrFunctionContext'
_G.LrApplication = import 'LrApplication'
_G.LrPrefs = import 'LrPrefs'
_G.LrProgressScope = import 'LrProgressScope'
_G.LrExportSession = import 'LrExportSession'
_G.LrStringUtils = import 'LrStringUtils'
_G.LrLocalization = import 'LrLocalization'
_G.LrShell = import 'LrShell'
_G.LrSystemInfo = import 'LrSystemInfo'

-- Global initializations
_G.prefs = _G.LrPrefs.prefsForPlugin()
_G.log = import 'LrLogger' ('AddaxInit')

if _G.prefs.logging == nil then
    _G.prefs.logging = false
end

if _G.prefs.logging then
    _G.log:enable('logfile')
else
    _G.log:enable('print')
end

_G.log:trace("Addax-AI Plugin Initialized.")
