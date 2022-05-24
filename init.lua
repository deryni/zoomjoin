-- Copyright (c) 2022 Etan Reisner
-- luacheck: read globals hs

--- === Zoom Meeting Launcher ===
---
--- Join zoom meetings from a chooser / menu
---
--- Download: [https://github.com/Hammerspoon/Spoons/raw/master/Spoons/zoomjoin.spoon.zip](zoomjoin.spoon.zip)

local obj = {
    name = 'Zoom Join',
    version = '2',
    author = 'Etan Reisner <deryni@gmail.com>',
    license = 'MPL-2.0',
    homepage = 'https://github.com/deryni/zoomjoin',
}

----

-- Variables

--- zoomjoin.meetingfile
--- Variable
--- Path to the zoomjoin meeting file.
obj.meetingfile = hs.configdir .. '/zoomjoin.json'

--- zoomjoin.meetings
--- Variable
--- Table of meeting definition objects.
obj.meetings = nil

--- zoomjoin.autosave
--- Variable
--- `true` to save meeting configuration after adding a meeting, `false` to require manual saving via menu item
obj.autosave = true

--- zoomjoin.editmenu
--- Variable
--- `true` to display the add/remove submenu, `false` to disable it
obj.editmenu = true

----

-- Internals

-- The zoom menu
local zoommenu = nil

-- The remove meeting chooser
local removechooser = nil

local _meetings = {}

local function removeMeetingCB(tab)
    if not tab then
        return
    end

    local ind
    for i, meeting in ipairs(obj.meetings) do
        if (tab.text == meeting.title) and
            ((tab.subText == meeting.url) or (tab.subText == meeting.id))
        then
            ind = i
            break
        end
    end
    if ind then
        table.remove(obj.meetings, ind)
    end

    obj:makeMenu()
    if obj.autosave then
        obj:writeConfig()
    end
end

local function newChooser(cb, placeholder)
    local _chooser = hs.chooser.new(cb)
    _chooser:rows(5)
    _chooser:width(40)
    _chooser:searchSubText(true)
    _chooser:placeholderText(placeholder)

    -- Clear the query and reset the scroll on dismissal.
    _chooser:hideCallback(function()
        _chooser:query('')
        _chooser:selectedRow(0)
    end)

    return _chooser
end

local function launchMeeting(mods, tab) -- luacheck: no unused args
    if not tab or not tab.meeting
    or (not tab.meeting.url and not tab.meeting.id) then
        return
    end

    if tab.meeting.url then
        hs.application.find('zoom.us'):activate()
        return hs.urlevent.openURLWithBundle(tab.meeting.url, 'us.zoom.xos')
    elseif tab.meeting.id then
        if not tab.meeting.password then
            local url = 'https://zoom.us/j/' .. tab.meeting.id

            return hs.urlevent.openURLWithBundle(url, 'us.zoom.xos')
        else
            -- TODO This needs to go through the zoom UI which needs the AX
            -- stuff as far as I can tell.
        end
    end
end

----

-- Callable functions

--- zoomjoin:makeMenu()
--- Method
--- Create the Zoom meeting menu.
---
--- Parameters:
---  * None
function obj:makeMenu()
    local chooserChoices = {}
    local meetingMenu = {}
    if self.editmenu then
        meetingMenu = {
            {
                title = 'zoomjoin',
                menu = {
                    {
                        title = 'Add Meeting',
                        fn = function()
                            if self:addMeeting() then
                                self:makeMenu()
                                if self.autosave then
                                    self:writeConfig()
                                end
                            end
                        end,
                    },
                    {
                        title = 'Remove Meeting',
                        fn = function()
                            removechooser:show()
                        end
                    },
                    {
                        title = '-',
                    },
                    {
                        title = 'Reload',
                        fn = function()
                            self:loadConfig()
                            self:makeMenu()
                        end,
                    },
                },
            },
            {
                title = '-',
            },
        }

        if not self.autosave then
            meetingMenu[#meetingMenu + 1] = {
                title = 'Save Meetings',
                fn = function() self:writeConfig() end,
            }
            meetingMenu[#meetingMenu + 1] = {
                title = '-',
            }
        end
    end

    for _, meeting in ipairs(self.meetings) do
        local disp = meeting.title or meeting.url or meeting.id

        -- Menu entry
        local m = {
            title = disp,
            fn = launchMeeting,
            meeting = meeting,
        }

        -- Chooser entry
        local c = {
            text = disp,
            entry = meeting,
        }

        if (meeting.title ~= meeting.url) and (meeting.title ~= meeting.id) then
            m.tooltip = meeting.url or meeting.id
            c.subText = meeting.url or meeting.id
        end

        meetingMenu[#meetingMenu + 1] = m

        -- Don't include separator entries in the chooser
        if disp ~= '-' then
            chooserChoices[#chooserChoices + 1] = c
        end
    end

    zoommenu:setMenu(meetingMenu)

    removechooser:choices(chooserChoices)
end

--- zoomjoin:addMeeting()
--- Method
--- Prompt to add a meeting to the configured meeting definitions.
---
--- Parameters:
---  * None
---
--- Returns:
---  * `true` if a new entry was added
---
--- Notes:
---  * zoomjoin:makeMenu must be called to update the menu
---  * zoomjoin:writeConfig must be called to save added meeting
function obj:addMeeting()
    hs.focus()

    local button, response = hs.dialog.textPrompt('Add a new Zoom meeting', '', '', 'Add Meeting', 'Cancel')

    if button == 'Cancel' then
        return
    end

    if response == '' then
        return
    elseif response == '-' then
        if self.meetings[#self.meetings].title ~= '-' then
            self.meetings[#self.meetings + 1] = {title = '-'}
            return true
        end
        return
    end

    local newMeeting = {}

    if response:match('^https://') then
        -- We got a zoom URL
        newMeeting.url = response
    else
        -- We got a meeting ID and need to prompt for a password
        local _, password = hs.dialog.textPrompt('Enter meeting password', 'Leave blank if none', '', 'Continue')

        newMeeting.id = response
        newMeeting.password = password
    end

    local _, title = hs.dialog.textPrompt('Enter meeting title', '', newMeeting.url or newMeeting.id, 'Add')
    newMeeting.title = title

    self.meetings[#self.meetings + 1] = newMeeting
    return true
end

--- zoomjoin:loadConfig()
--- Method
--- Load the zoom meeting definition file and recreate the menu
---
--- Parameters:
---  * None
---
--- Notes:
---  * Called automatically by pathwatcher and start method. Only needed if start() is not called or to manually reload the configuration file.
function obj:loadConfig()
    self.meetings = hs.json.read(self.meetingfile) or {}
end

--- zoomjoin:writeConfig()
--- Method
--- Write the zoom meeting definition file
---
--- Parameters:
---  * None
---
--- Returns:
---  * Result from calling hs.json.write
---
--- Notes:
---  * Called automatically when Add Meeting is used if autosave is on.
function obj:writeConfig()
    return hs.json.write(self.meetings, self.meetingfile, true, true)
end

--- zoomjoin:start()
--- Method
--- Loads the meeting definition file and creates the menu.
---
--- Parameters:
---  * None
---
--- Returns:
---  * The zoomjoin object
function obj:start()
    zoommenu = hs.menubar.new():setTitle('Zoom')

    removechooser = newChooser(removeMeetingCB, 'Select meeting to remove')

    self:loadConfig()
    self:makeMenu()

    return self
end

--- zoomjoin:stop()
--- Method
--- Stops the pathwatcher for zoom meeting configuration changes. Deletes the menu.
---
--- Parameters:
---  * None
---
--- Returns:
---  * The zoomjoin object
function obj:stop()
    zoommenu:delete()

    return self
end

return obj
