--@ module = true

local gui = require('gui')
local widgets = require('gui.widgets')
local textures = require('gui.textures')
local overlay = require('plugins.overlay')
local guidm = require('gui.dwarfmode')
local text_editor = reqscript('internal/journal/text_editor')

-- local green_pin = dfhack.textures.loadTileset('hack/data/art/green-pin.png', 8, 12, true),

-- NotesView = defclass(NotesView, gui.View)
-- NotesView.ATTRS{}

NotesOverlay = defclass(NotesOverlay, overlay.OverlayWidget)
NotesOverlay.ATTRS{
    desc='Render map notes.',
    viewscreens='dwarfmode',
    default_enabled=true,
    -- TODO increase to 30 seconds
    overlay_onupdate_max_freq_seconds=1,
    hotspot=true,
    fullscreen=true,
}

function NotesOverlay:init()
end

function NotesOverlay:onRenderFrame(dc)
    if not df.global.pause_state and not dfhack.screen.inGraphicsMode() then
        return
    end

    dc:map(true)
    -- local texpos = dfhack.textures.getTexposByHandle(green_pin[1])
    local texpos = textures.tp_green_pin(1)
    local color, ch = COLOR_RED, 'X'
    dc:pen({ch='X', fg=COLOR_GREEN, bg=COLOR_BLACK, tile=texpos})

    local viewport = guidm.Viewport.get()

    for _, point in ipairs(df.global.plotinfo.waypoints.points) do
        if viewport:isVisible(point.pos) then
            local pos = viewport:tileToScreen(point.pos)
            dc
                :seek(pos.x, pos.y)
                :tile()
        end
    end

    dc:map(false)

end

NoteManager = defclass(NoteManager, gui.ZScreen)
NoteManager.ATTRS{
    focus_path='hotspot/menu',
    hotspot_frame=DEFAULT_NIL,
}

function NoteManager:init()
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
                    frame_style_b=nil,NoteManager
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
                },
                widgets.Panel{
                    view_id='buttons',
                    frame={b=0,h=3},
                    autoarrange_subviews=true,
                    subviews={
                        widgets.TextButton{
                            view_id='Create',
                            frame={h=1},
                            label='Create',
                            key='CUSTOM_ALT_S',
                            on_activate=function() self:createNote() end,
                            enabled=function() return #self.subviews.name:getText() > 0 end,
                        },
                        widgets.TextButton{
                            view_id='cancel',
                            frame={h=1},
                            label='Cancel',
                            key='LEAVESCREEN'
                        },
                        widgets.TextButton{
                            view_id='delete',
                            frame={h=1},
                            label='Delete',
                            key='CUSTOM_ALT_D',
                        },
                    }
                }
            },
        },
    }
end

function NoteManager:createNote()
    local name = self.subviews.name:getText()
    local comment = self.subviews.comment:getText()

    if #name == 0 then
        print('Note need at least a name')
        return
    end

    local waypoints = df.global.plotinfo.waypoints
    local notes = df.global.plotinfo.waypoints.points

    local x, y, z = pos2xyz(df.global.cursor)
    if x == nil then
        print('Enable keyboard cursor to add a note.')
        return
    end

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
    self:dismiss()
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

        return NoteManager{}:show()
    end
end

if not dfhack_flags.module then
    main({...})
end
