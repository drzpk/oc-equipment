-- ##########################################
-- #		  settings test module			#
-- #										#
-- #  08.2020			by: Dominik Rzepka  #
-- ##########################################

local version = "1.0"
local args = {...}

local core = nil

local mod = {
    name = "test_settings",
    version = version,
    id = 50,
    apiLevel = 5,
    actions = {}
}

local function settingsEditorTest()
    local editor = core.createSettingsEditor(mod, "testSettings")

    editor:addStringProperty("stringKey", "String property 1", "default value")
    editor:addPropertySeparator()
    editor:addStringProperty("anotherKey", "String property 2")
    editor:addIntegerProperty("intKey", "Int value", 12)
    editor:addBooleanProperty("boolKey", "Bool value")

    editor:addButton("very long button name 123456", function ()
        core.messageBox(mod, "clicked button 1")
    end)
    editor:addButtonSeparator()
    editor:addButton("button 2", function ()
        core.messageBox(mod, "clicked button 2")
    end)
    editor:addButton("button 3", function (e, manager)
        local int = manager:getValue("intKey")
        local bool = manager:getValue("boolKey") or false
        core.messageBox(mod, "Current int value: " .. tostring(int) .. ", bool value: " .. tostring(bool))
    end)

    editor:show("Settings editor")
end

local function settingsValidationTest()
    local editor = core.createSettingsEditor(mod, "testSettings_validation")

    editor:addStringProperty("requiredKey", "Required property", nil, {required = true})
    editor:addStringProperty("minLengthKey", "Min length property", nil, {minLength = 5})
    editor:addIntegerProperty("maxValueKey", "Max value property", nil, {maxValue = 100})
    
    editor:show("Settings editor (validation)")
end

function mod.setUI(window)
    window:addLabel("center", 1, 26, ">> settings test module <<")
    window:addButton(2, 3, 24, 1, "settings editor test", settingsEditorTest)
    window:addButton(2, 4, 28, 1, "settings validation test", settingsValidationTest)
end

function mod.start(api)
    core = api
end

function mod.stop(api)

end

function mod.pullEvent(event)

end

return mod