local common = reqscript('internal/control-panel/common')
local dialogs = require('gui.dialogs')
local gui = require('gui')
local textures = require('gui.textures')
local helpdb = require('helpdb')
local overlay = require('plugins.overlay')
local registry = reqscript('internal/control-panel/registry')
local utils = require('utils')
local widgets = require('gui.widgets')

local function get_icon_pens()
    local enabled_pen_left = dfhack.pen.parse{fg=COLOR_CYAN,
            tile=curry(textures.tp_control_panel, 1), ch=string.byte('[')}
    local enabled_pen_center = dfhack.pen.parse{fg=COLOR_LIGHTGREEN,
            tile=curry(textures.tp_control_panel, 2) or nil, ch=251} -- check
    local enabled_pen_right = dfhack.pen.parse{fg=COLOR_CYAN,
            tile=curry(textures.tp_control_panel, 3) or nil, ch=string.byte(']')}
    local disabled_pen_left = dfhack.pen.parse{fg=COLOR_CYAN,
            tile=curry(textures.tp_control_panel, 4) or nil, ch=string.byte('[')}
    local disabled_pen_center = dfhack.pen.parse{fg=COLOR_RED,
            tile=curry(textures.tp_control_panel, 5) or nil, ch=string.byte('x')}
    local disabled_pen_right = dfhack.pen.parse{fg=COLOR_CYAN,
            tile=curry(textures.tp_control_panel, 6) or nil, ch=string.byte(']')}
    local button_pen_left = dfhack.pen.parse{fg=COLOR_CYAN,
            tile=curry(textures.tp_control_panel, 7) or nil, ch=string.byte('[')}
    local button_pen_right = dfhack.pen.parse{fg=COLOR_CYAN,
            tile=curry(textures.tp_control_panel, 8) or nil, ch=string.byte(']')}
    local help_pen_center = dfhack.pen.parse{
            tile=curry(textures.tp_control_panel, 9) or nil, ch=string.byte('?')}
    local configure_pen_center = dfhack.pen.parse{
            tile=curry(textures.tp_control_panel, 10) or nil, ch=15} -- gear/masterwork symbol
    return enabled_pen_left, enabled_pen_center, enabled_pen_right,
            disabled_pen_left, disabled_pen_center, disabled_pen_right,
            button_pen_left, button_pen_right,
            help_pen_center, configure_pen_center
end
local ENABLED_PEN_LEFT, ENABLED_PEN_CENTER, ENABLED_PEN_RIGHT,
        DISABLED_PEN_LEFT, DISABLED_PEN_CENTER, DISABLED_PEN_RIGHT,
        BUTTON_PEN_LEFT, BUTTON_PEN_RIGHT,
        HELP_PEN_CENTER, CONFIGURE_PEN_CENTER = get_icon_pens()

--
-- ConfigPanel
--

-- provides common structure across control panel tabs
ConfigPanel = defclass(ConfigPanel, widgets.Panel)
ConfigPanel.ATTRS{
    intro_text=DEFAULT_NIL,
}

function ConfigPanel:init()
    local main_panel = widgets.Panel{
        frame={t=0, b=7},
        autoarrange_subviews=true,
        autoarrange_gap=1,
        subviews={
            widgets.WrappedLabel{
                frame={t=0},
                text_to_wrap=self.intro_text,
            },
            -- extended by subclasses
        },
    }
    self:init_main_panel(main_panel)

    local footer = widgets.Panel{
        view_id='footer',
        frame={b=0, h=3},
        -- extended by subclasses
    }
    self:init_footer(footer)

    self:addviews{
        main_panel,
        widgets.WrappedLabel{
            view_id='desc',
            frame={b=4, h=2},
            auto_height=false,
        },
        footer,
    }
end

-- overridden by subclasses
function ConfigPanel:init_main_panel(panel)
end

-- overridden by subclasses
function ConfigPanel:init_footer(panel)
end

-- overridden by subclasses
function ConfigPanel:refresh()
end

-- attach to lists in subclasses
-- choice.data is an entry from one of the registry tables
function ConfigPanel:on_select(_, choice)
    local desc = self.subviews.desc
    desc.text_to_wrap = choice and common.get_description(choice.data) or ''
    if desc.frame_body then
        desc:updateLayout()
    end
end

--[[
--
-- Services
--

Services = defclass(Services, ConfigPanel)
Services.ATTRS{
    group=DEFAULT_NIL,
}

function Services:init()
    self:addviews{
        widgets.TabBar{
            frame={t=0},
            labels={
                'Automation',
                'Bug Fixes',
                'Gameplay',
            },
            on_select=function(val) self.subpage = val self:refresh() end,
            get_cur_page=function() return self.subpage end,
        },

        widgets.Panel{
            frame={t=0, b=7},
            autoarrange_subviews=true,
            autoarrange_gap=1,
            subviews={
                widgets.WrappedLabel{
                    frame={t=0},
                    text_to_wrap=self.intro_text,
                },
                widgets.FilteredList{
                    frame={t=5},
                    view_id='list',
                    on_select=self:callback('on_select'),
                    on_double_click=self:callback('on_submit'),
                    on_double_click2=self:callback('launch_config'),
                    row_height=2,
                },
            },
        },
        widgets.WrappedLabel{
            view_id='desc',
            frame={b=4, h=2},
            auto_height=false,
        },
        widgets.HotkeyLabel{
            frame={b=2, l=0},
            label=self.select_label,
            key='SELECT',
            enabled=self.is_enableable,
            on_activate=self:callback('on_submit')
        },
        widgets.HotkeyLabel{
            view_id='show_help_label',
            frame={b=1, l=0},
            label='Show tool help or run custom command',
            key='CUSTOM_CTRL_H',
            on_activate=self:callback('show_help')
        },
        widgets.HotkeyLabel{
            view_id='launch',
            frame={b=0, l=0},
            label='Launch tool-specific config UI',
            key='CUSTOM_CTRL_G',
            enabled=self.is_configurable,
            on_activate=self:callback('launch_config'),
        },
    }
end

function Services:get_choices()
    local enabled_map = common.get_enabled_map()
    local choices = {}
    for _,data in ipairs(registry.COMMANDS_BY_IDX) do
        if command_passes_filters(data, self.group) then
            table.insert(choices, {data=data, enabled=enabled_map[data.command]})
        end
    end
    return choices
end

function Services:onInput(keys)
    local handled = ConfigPanel.super.onInput(self, keys)
    if keys._MOUSE_L then
        local list = self.subviews.list.list
        local idx = list:getIdxUnderMouse()
        if idx then
            local x = list:getMousePos()
            if x <= 2 then
                self:on_submit()
            elseif x >= 4 and x <= 6 then
                self:show_help()
            elseif x >= 8 and x <= 10 then
                self:launch_config()
            end
        end
    end
    return handled
end



local COMMAND_REGEX = '^([%w/_-]+)'

function Services:refresh()
    local choices = {}
    for _,choice in ipairs(self:get_choices()) do
        local command = choice.target or choice.command
        command = command:match(COMMAND_REGEX)
        local gui_config = 'gui/' .. command
        local want_gui_config = utils.getval(self.is_configurable, gui_config)
                and helpdb.is_entry(gui_config)
        local enabled = choice.enabled
        local function get_enabled_pen(enabled_pen, disabled_pen)
            if not utils.getval(self.is_enableable) then
                return gui.CLEAR_PEN
            end
            return enabled and enabled_pen or disabled_pen
        end
        local text = {
            {tile=get_enabled_pen(ENABLED_PEN_LEFT, DISABLED_PEN_LEFT)},
            {tile=get_enabled_pen(ENABLED_PEN_CENTER, DISABLED_PEN_CENTER)},
            {tile=get_enabled_pen(ENABLED_PEN_RIGHT, DISABLED_PEN_RIGHT)},
            ' ',
            {tile=BUTTON_PEN_LEFT},
            {tile=HELP_PEN_CENTER},
            {tile=BUTTON_PEN_RIGHT},
            ' ',
            {tile=want_gui_config and BUTTON_PEN_LEFT or gui.CLEAR_PEN},
            {tile=want_gui_config and CONFIGURE_PEN_CENTER or gui.CLEAR_PEN},
            {tile=want_gui_config and BUTTON_PEN_RIGHT or gui.CLEAR_PEN},
            ' ',
            choice.target,
        }
        local desc = helpdb.is_entry(command) and
                helpdb.get_entry_short_help(command) or ''
        table.insert(choices,
                {text=text, command=choice.command, target=choice.target, desc=desc,
                 search_key=choice.target, enabled=enabled,
                 gui_config=want_gui_config and gui_config})
    end
    local list = self.subviews.list
    local filter = list:getFilter()
    local selected = list:getSelected()
    list:setChoices(choices)
    list:setFilter(filter, selected)
    list.edit:setFocus(true)
end

function Services:on_select(idx, choice)
    local desc = self.subviews.desc
    desc.text_to_wrap = choice and choice.desc or ''
    if desc.frame_body then
        desc:updateLayout()
    end
    if choice then
        self.subviews.launch.enabled = utils.getval(self.is_configurable)
                and not not choice.gui_config
    end
end

function Services:on_submit()
    if not utils.getval(self.is_enableable) then return false end
    _,choice = self.subviews.list:getSelected()
    if not choice then return end
    local tokens = {}
    table.insert(tokens, choice.command)
    table.insert(tokens, choice.enabled and 'disable' or 'enable')
    table.insert(tokens, choice.target)
    dfhack.run_command(tokens)
    self:refresh()
end

function Services:show_help()
    _,choice = self.subviews.list:getSelected()
    if not choice then return end
    local command = choice.target:match(COMMAND_REGEX)
    dfhack.run_command('gui/launcher', command .. ' ')
end

function Services:launch_config()
    if not utils.getval(self.is_configurable) then return false end
    _,choice = self.subviews.list:getSelected()
    if not choice or not choice.gui_config then return end
    dfhack.run_command(choice.gui_config)
end


--
-- AutomationServices
--

AutomationServices = defclass(AutomationServices, Services)
AutomationServices.ATTRS{
    intro_text='These tools can only be enabled when you have a fort loaded,'..
                ' but once you enable them, they will stay enabled when you'..
                ' save and reload your fort. If you want them to be'..
                ' auto-enabled for new forts, please see the "Autostart" tab.',
    group='automation',
}

--
-- BugfixServices
--

BugfixServices = defclass(BugfixServices, Services)
BugfixServices.ATTRS{
    intro_text='Tools that are enabled on this page will be auto-enabled for'..
                ' you when you start a new fort, using the default'..
                ' configuration. To see tools that are enabled right now in'..
                ' an active fort, please see the "Fort" tab.',
    group='bugfix',
}

--
-- BugfixServices
--

GameplayServices = defclass(GameplayServices, Services)
GameplayServices.ATTRS{
    intro_text='Tools that are enabled on this page will be auto-enabled for'..
                ' you when you start a new fort, using the default'..
                ' configuration. To see tools that are enabled right now in'..
                ' an active fort, please see the "Fort" tab.',
    group='gameplay',
}

--
-- Overlays
--

Overlays = defclass(Overlays, ConfigPanel)
Overlays.ATTRS{
    is_enableable=true,
    is_configurable=false,
    intro_text='These are DFHack overlays that add information and'..
                ' functionality to various native DF screens.',
}

function Overlays:init()
    self.subviews.launch.visible = false
    self:addviews{
        widgets.HotkeyLabel{
            frame={b=0, l=0},
            label='Launch overlay widget repositioning UI',
            key='CUSTOM_CTRL_G',
            on_activate=function() dfhack.run_script('gui/overlay') end,
        },
    }
end

function Overlays:get_choices()
    local choices = {}
    local state = overlay.get_state()
    for _,name in ipairs(state.index) do
        table.insert(choices, {command='overlay',
                               target=name,
                               enabled=state.config[name].enabled})
    end
    return choices
end
]]
--
-- PreferencesTab
--

IntegerInputDialog = defclass(IntegerInputDialog, widgets.Window)
IntegerInputDialog.ATTRS{
    visible=false,
    frame={w=50, h=11},
    frame_title='Edit setting',
    frame_style=gui.PANEL_FRAME,
    on_hide=DEFAULT_NIL,
}

function IntegerInputDialog:init()
    self:addviews{
        widgets.Label{
            frame={t=0, l=0},
            text={
                'Please enter a new value for ', NEWLINE,
                {
                    gap=4,
                    text=function() return self.id or '' end,
                },
                NEWLINE,
                {text=self:callback('get_spec_str')},
            },
        },
        widgets.EditField{
            view_id='input_edit',
            frame={t=4, l=0},
            on_char=function(ch) return ch:match('%d') end,
        },
        widgets.HotkeyLabel{
            frame={b=0, l=0},
            label='Save',
            key='SELECT',
            on_activate=function() self:hide(self.subviews.input_edit.text) end,
        },
        widgets.HotkeyLabel{
            frame={b=0, r=0},
            label='Reset to default',
            key='CUSTOM_CTRL_G',
            auto_width=true,
            on_activate=function() self.subviews.input_edit:setText(tostring(self.data.default)) end,
        },
    }
end

function IntegerInputDialog:get_spec_str()
    local data = self.data
    local strs = {
        ('default: %d'):format(data.default),
    }
    if data.min then
        table.insert(strs, ('at least %d'):format(data.min))
    end
    if data.max then
        table.insert(strs, ('at most %d'):format(data.max))
    end
    return ('(%s)'):format(table.concat(strs, ', '))
end

function IntegerInputDialog:show(id, data, initial)
    self.visible = true
    self.id, self.data = id, data
    local edit = self.subviews.input_edit
    edit:setText(tostring(initial))
    edit:setFocus(true)
    self:updateLayout()
end

function IntegerInputDialog:hide(val)
    self.visible = false
    self.on_hide(tonumber(val))
end

function IntegerInputDialog:onInput(keys)
    if IntegerInputDialog.super.onInput(self, keys) then
        return true
    end
    if keys.LEAVESCREEN or keys._MOUSE_R then
        self:hide()
        return true
    end
end

PreferencesTab = defclass(PreferencesTab, ConfigPanel)
PreferencesTab.ATTRS{
    intro_text='These are the customizable DFHack system settings.',
}

function PreferencesTab:init_main_panel(panel)
    panel:addviews{
        widgets.FilteredList{
            frame={t=5},
            view_id='list',
            on_select=self:callback('on_select'),
            on_double_click=self:callback('on_submit'),
            row_height=2,
        },
        IntegerInputDialog{
            view_id='input_dlg',
            on_hide=self:callback('set_val'),
        },
    }
end

function PreferencesTab:init_footer(panel)
    panel:addviews{
        widgets.HotkeyLabel{
            frame={t=0, l=0},
            label='Toggle/edit setting',
            key='SELECT',
            on_activate=self:callback('on_submit')
        },
        widgets.HotkeyLabel{
            frame={t=2, l=0},
            label='Restore defaults',
            key='CUSTOM_CTRL_G',
            on_activate=self:callback('restore_defaults')
        },
    }
end

function PreferencesTab:onInput(keys)
    if self.subviews.input_dlg.visible then
        self.subviews.input_dlg:onInput(keys)
        return true
    end
    local handled = PreferencesTab.super.onInput(self, keys)
    if keys._MOUSE_L then
        local list = self.subviews.list.list
        local idx = list:getIdxUnderMouse()
        if idx then
            local x = list:getMousePos()
            if x <= 2 then
                self:on_submit()
            end
        end
    end
    return handled
end

local function make_preference_text(label, value)
    return {
        {tile=BUTTON_PEN_LEFT},
        {tile=CONFIGURE_PEN_CENTER},
        {tile=BUTTON_PEN_RIGHT},
        ' ',
        ('%s (%s)'):format(label, value),
    }
end

function PreferencesTab:refresh()
    if self.subviews.input_dlg.visible then return end
    local choices = {}
    for _, data in ipairs(registry.PREFERENCES_BY_IDX) do
        local text = make_preference_text(data.label, data.get_fn())
        table.insert(choices, {
            text=text,
            search_key=text[#text],
            data=data
        })
    end
    local list = self.subviews.list
    local filter = list:getFilter()
    local selected = list:getSelected()
    list:setChoices(choices)
    list:setFilter(filter, selected)
    list.edit:setFocus(true)
end

local function preferences_set_and_save(self, data, val)
    common.set_preference(data, val)
    common.config:write()
    self:refresh()
end

function PreferencesTab:on_submit()
    _,choice = self.subviews.list:getSelected()
    if not choice then return end
    local data = choice.data
    local cur_val = data.get_fn()
    local data_type = type(data.default)
    if data_type == 'boolean' then
        preferences_set_and_save(self, data, not cur_val)
    elseif data_type == 'number' then
        self.subviews.input_dlg:show(data.label, data, cur_val)
    end
end

function PreferencesTab:set_val(val)
    _,choice = self.subviews.list:getSelected()
    if not choice or not val then return end
    preferences_set_and_save(self, choice.data, val)
end

function PreferencesTab:restore_defaults()
    for _,data in ipairs(registry.PREFERENCES_BY_IDX) do
        common.set_preference(data, data.default)
    end
    common.config:write()
    self:refresh()
    dialogs.showMessage('Success', 'Default preferences restored.')
end

--
-- ControlPanel
--

ControlPanel = defclass(ControlPanel, widgets.Window)
ControlPanel.ATTRS {
    frame_title='DFHack Control Panel',
    frame={w=61, h=36},
    resizable=true,
    resize_min={h=28},
    autoarrange_subviews=true,
    autoarrange_gap=1,
}

function ControlPanel:init()
    self:addviews{
        widgets.TabBar{
            frame={t=0},
            labels={
                --'Enabled',
                --'Autostart',
                --'UI Overlays',
                'Preferences',
            },
            on_select=self:callback('set_page'),
            get_cur_page=function() return self.subviews.pages:getSelected() end,
        },
        widgets.Pages{
            view_id='pages',
            frame={t=5, l=0, b=0, r=0},
            subviews={
                --EnabledTab{},
                --AutostartTab{},
                --OverlaysTab{},
                PreferencesTab{},
            },
        },
    }

    self:refresh_page()
end

function ControlPanel:refresh_page()
    self.subviews.pages:getSelectedPage():refresh()
end

function ControlPanel:set_page(val)
    self.subviews.pages:setSelected(val)
    self:refresh_page()
    self:updateLayout()
end

--
-- ControlPanelScreen
--

ControlPanelScreen = defclass(ControlPanelScreen, gui.ZScreen)
ControlPanelScreen.ATTRS {
    focus_path='control-panel',
}

function ControlPanelScreen:init()
    self:addviews{ControlPanel{}}
end

function ControlPanelScreen:onDismiss()
    view = nil
end

view = view and view:raise() or ControlPanelScreen{}:show()
