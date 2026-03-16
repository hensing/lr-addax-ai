return {
	LrSdkVersion = 13.0,
	LrSdkMinimumVersion = 13.0,
	LrToolkitIdentifier = 'com.hensing.addaxai.classifier',
	LrPluginName = 'Addax-AI Classifier',
	LrAuthor = 'Dr. Henning Dickten (@hensing)',
	
	LrPluginInfoUrl = 'https://github.com/hensing/lr-addax-ai',
	
	-- Initialization file
	LrInitPlugin = "Init.lua",
	
	-- Definition for the Plugin Manager settings sections
	LrPluginInfoProvider = 'AddaxProvider.lua',

	-- Library menu item definition
	LrLibraryMenuItems = {
		{
			title = 'Classify with Addax-AI',
			file = 'AddaxProcess.lua',
		},
	},
}
