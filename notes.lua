--@ module = true

local gui = require('gui')
local widgets = require('gui.widgets')
local textures = require('gui.textures')
local overlay = require('plugins.overlay')
local guidm = require('gui.dwarfmode')
local text_editor = reqscript('internal/journal/text_editor')

local green_pin = dfhack.textures.loadTileset('hack/data/art/note-green-pin.png', 32, 32, true)

NotesOverlay = defclass(NotesOverlay, overlay.OverlayWidget)
NotesOverlay.ATTRS{
    desc='Render map notes.',
    viewscreens='dwarfmode',
    default_enabled=true,
    overlay_onupdate_max_freq_seconds=30,
    fullscreen=true,
}

function NotesOverlay:init()
    self.notes = {}
    self.note_manager = nil
    self.last_click_pos = {}
    self:reloadVisibleNotes()
end

function NotesOverlay:overlay_onupdate()
    self:reloadVisibleNotes()
end

function NotesOverlay:overlay_trigger(args)
    return self:showNoteManager()
end

function NotesOverlay:onInput(keys)
    if keys._MOUSE_L then
        local pos = dfhack.gui.getMousePos()

        local note = self:clickedNote(pos)
        if note ~= nil then
            self:showNoteManager(note)
        end
    end
end

function NotesOverlay:clickedNote(click_pos)
    local pos_curr_note = same_xyz(self.last_click_pos, click_pos)
        and self.note_manager
        and self.note_manager.note
        or nil

    self.last_click_pos = click_pos

    local notes = df.global.plotinfo.waypoints.points

    local last_note_on_pos = nil
    local first_note_on_pos = nil
    for _, note in pairs(notes) do
        if same_xyz(note.pos, click_pos) then
            if last_note_on_pos == pos_curr_note then
                return note
            end

            first_note_on_pos = first_note_on_pos or note
            last_note_on_pos = note
        end
    end

    return first_note_on_pos
end

function NotesOverlay:showNoteManager(note)
    if self.note_manager ~= nil then
        self.note_manager:dismiss()
    end

    self.note_manager = NoteManager{
        note=note,
        on_update=function() self:reloadVisibleNotes() end
    }

    return self.note_manager:show()
end

function NotesOverlay:viewportChanged()
    return self.viewport_pos.x ~=  df.global.window_x or
        self.viewport_pos.y ~=  df.global.window_y or
        self.viewport_pos.z ~=  df.global.window_z
end

function NotesOverlay:onRenderFrame(dc)
    if not df.global.pause_state and not dfhack.screen.inGraphicsMode() then
        return
    end

    if self:viewportChanged() then
        self:reloadVisibleNotes()
    end

    dc:map(true)

    local texpos = dfhack.textures.getTexposByHandle(green_pin[1])
    dc:pen({fg=COLOR_BLACK, bg=COLOR_LIGHTCYAN, tile=texpos})

    for _, note in pairs(self.notes) do
        dc
            :seek(note.screen_pos.x, note.screen_pos.y)
            :char('N')
    end

    dc:map(false)
end

function NotesOverlay:reloadVisibleNotes()
    self.notes = {}

    local viewport = guidm.Viewport.get()
    self.viewport_pos = {
        x=df.global.window_x,
        y=df.global.window_y,
        z=df.global.window_z
    }

    for _, point in ipairs(df.global.plotinfo.waypoints.points) do
        if viewport:isVisible(point.pos) then
            local pos = viewport:tileToScreen(point.pos)
            table.insert(self.notes, {
                point=point,
                screen_pos=pos
            })
        end
    end
end

NoteManager = defclass(NoteManager, gui.ZScreen)
NoteManager.ATTRS{
    focus_path='hotspot/menu',
    hotspot_frame=DEFAULT_NIL,
    note=DEFAULT_NIL,
    on_update=DEFAULT_NIL,
}

function NoteManager:init()
    local edit_mode = self.note ~= nil

    self:addviews{
        widgets.Window{
            frame={w=35,h=20},
            frame_inset={t=1},
            autoarrange_subviews=false,
            subviews={
                widgets.HotkeyLabel {
                    key='CUSTOM_ALT_N',
                    label='Name',
                    frame={t=0},
                    on_activate=function() self.subviews.name:setFocus(true) end,
                },
                text_editor.TextEditor{
                    view_id='name',
                    focus_path='notes/name',
                    frame={t=1,h=3},
                    frame_style=gui.FRAME_INTERIOR,
                    frame_style_b=nil,
                    init_text=self.note and self.note.name or ''
                },
                widgets.HotkeyLabel {
                    key='CUSTOM_ALT_C',
                    label='Comment',
                    frame={t=4},
                    on_activate=function() self.subviews.comment:setFocus(true) end,
                },
                text_editor.TextEditor{
                    view_id='comment',
                    frame={t=5,b=3},
                    focus_path='notes/comment',
                    frame_style=gui.FRAME_INTERIOR,
                    init_text=self.note and self.note.comment or ''
                },
                widgets.Panel{
                    view_id='buttons',
                    frame={b=0,h=3},
                    autoarrange_subviews=true,
                    subviews={
                        edit_mode and widgets.TextButton{
                            view_id='Save',
                            frame={h=1},
                            label='Save',
                            key='CUSTOM_ALT_S',
                            on_activate=function() self:saveNote() end,
                            enabled=function() return #self.subviews.name:getText() > 0 end,
                        } or widgets.TextButton{
                            view_id='Create',
                            frame={h=1},
                            label='Create',
                            key='CUSTOM_ALT_S',
                            on_activate=function() self:createNote() end,
                            enabled=function() return #self.subviews.name:getText() > 0 end,
                        },
                        edit_mode and widgets.TextButton{
                            view_id='delete',
                            frame={h=1},
                            label='Delete',
                            key='CUSTOM_ALT_D',
                            on_activate=function() self:deleteNote() end,
                        } or nil,
                    }
                }
            },
        },
    }
end

function NoteManager:createNote()
    local x, y, z = pos2xyz(df.global.cursor)
    if x == nil then
        print('Enable keyboard cursor to add a note.')
        return
    end

    local name = self.subviews.name:getText()
    local comment = self.subviews.comment:getText()

    if #name == 0 then
        print('Note need at least a name')
        return
    end

    local waypoints = df.global.plotinfo.waypoints
    local notes = df.global.plotinfo.waypoints.points

    notes:insert("#", {
        new=true,

        id = waypoints.next_point_id,
        tile=88,
        fg_color=7,
        bg_color=0,
        name=name,
        comment=comment,
        pos=xyz2pos(x, y, z)
    })
    waypoints.next_point_id = waypoints.next_point_id + 1

    if self.on_update then
        self.on_update()
    end

    self:dismiss()
end

function NoteManager:saveNote()
    if self.note == nil then
        return
    end

    local name = self.subviews.name:getText()
    local comment = self.subviews.comment:getText()

    if #name == 0 then
        print('Note need at least a name')
        return
    end

    local notes = df.global.plotinfo.waypoints.points
    self.note.name = name
    self.note.comment = comment

    if self.on_update then
        self.on_update()
    end

    self:dismiss()
end

function NoteManager:deleteNote()
    if self.note == nil then
        return
    end

    for ind, note in pairs(df.global.plotinfo.waypoints.points) do
        if note == self.note then
            df.global.plotinfo.waypoints.points:erase(ind)
            break
        end
    end

    if self.on_update then
        self.on_update()
    end

    self:dismiss()
end

function NoteManager:onDismiss()
    self.note = nil
end

-- register widgets
OVERLAY_WIDGETS = {
    map_notes=NotesOverlay
}

local function main(args)
    if #args == 0 then
        return
    end

    if args[1] == 'add' then
        local x = pos2xyz(df.global.cursor)
        if x == nil then
            print('Enable keyboard cursor to add a note.')
            return
        end

        return dfhack.internal.runCommand('overlay trigger notes.map_notes')
    end
end

if not dfhack_flags.module then
    main({...})
end
