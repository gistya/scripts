--@module = true
--@enable = true

local argparse = require('argparse')
local eventful = require('plugins.eventful')
local repeatutil = require("repeat-util")
local utils = require('utils')

-- set to verbosity level
-- 1: dev warning messages
-- 2: timeskip tracing
-- 3: coverage tracing
DEBUG = DEBUG or 0

------------------------------------
-- state management

local GLOBAL_KEY = 'timestream'

local SETTINGS = {
    {
        name='fps',
        validate=function(arg)
            local val = argparse.positiveInt(arg, 'fps')
            if val < 10 then qerror('target fps must be at least 10') end
            return val
        end,
        default=function() return df.global.init.fps_cap end,
    },
}

local function get_default_state()
    local settings = {}
    for _, v in ipairs(SETTINGS) do
        settings[v.internal_name or v.name] = utils.getval(v.default)
    end
    return {
        enabled=false,
        settings=settings,
    }
end

state = state or get_default_state()

function isEnabled()
    return state.enabled
end

local function persist_state()
    dfhack.persistent.saveSiteData(GLOBAL_KEY, state)
end

------------------------------------
-- business logic

-- ensure we never skip over cur_year_tick values that match this list
local TICK_TRIGGERS = {
    {mod=10, rem={0}},           -- 0: season ticks (and lots of other stuff)
                                 -- 0 mod 100: crop growth, strange mood, minimap update, rot
                                 -- 20 mod 100: building updates
                                 -- 40 mod 100: assign tombs to newly tomb-eligible corpses
                                 -- 80 mod 100: incarceration updates
                                 -- 40 mod 1000: remove excess seeds
    {mod=50, rem={25, 35, 45}},  -- 25: stockpile updates
                                 -- 35: check bags
                                 -- 35 mod 100: job auction
                                 -- 45: stockpile updates
    {mod=100, rem={99}},         -- 99: new job creation
}

-- "owed" ticks we would like to skip at the next opportunity
timeskip_deficit = timeskip_deficit or 0.0

-- birthday_triggers is a dense sequence of cur_year_tick values -> next unit birthday
-- the sequence covers 0 .. greatest unit birthday value
-- this cache is augmented when new units appear (as per the new unit event) and is cleared and
-- refreshed from scratch once a year to evict data for units that are no longer active.
birthday_triggers = birthday_triggers or {}

-- coverage record for cur_year_tick % 50 so we can be sure that all items are being scanned
-- (DF scans 1/50th of items every tick based on cur_year_tick % 50)
-- we want every section hit at least once every 1000 ticks
tick_coverage = tick_coverage or {}

-- only throttle due to tick_coverage at most once per season tick to avoid clustering
season_tick_throttled = season_tick_throttled or false

local function register_birthday(unit)
    local btick = unit.birth_time
    if btick < 0 then return end
    for tick=btick,0,-1 do
        if (birthday_triggers[tick] or math.huge) > btick then
            birthday_triggers[tick] = btick
        else
            break
        end
    end
end

local function check_new_unit(unit_id)
    local unit = df.unit.find(unit_id)
    if not unit then return end
    if DEBUG >= 3 then
        print('registering new unit', unit.id, dfhack.units.getReadableName(unit))
    end
    register_birthday(unit)
end

local function refresh_birthday_triggers()
    birthday_triggers = {}
    for _,unit in ipairs(df.global.world.units.active) do
        if dfhack.units.isActive(unit) and not dfhack.units.isDead(unit) then
            register_birthday(unit)
        end
    end
end

local function reset_ephemeral_state()
    timeskip_deficit = 0.0
    refresh_birthday_triggers()
    tick_coverage = {}
    season_tick_throttled = false
end

local function get_desired_timeskip(real_fps, desired_fps)
    -- minus 1 to account for the current frame
    return (desired_fps / real_fps) - 1
end

local function clamp_coverage(timeskip)
    if season_tick_throttled then return timeskip end
    for val=1,timeskip do
        local coverage_slot = (df.global.cur_year_tick+val) % 50
        if not tick_coverage[coverage_slot] then
            season_tick_throttled = true
            return val-1
        end
    end
    return timeskip
end

local function record_coverage()
    local coverage_slot = df.global.cur_year_tick % 50
    if DEBUG >= 3 and not tick_coverage[coverage_slot] then
        print('recording coverage for slot:', coverage_slot)
    end
    tick_coverage[coverage_slot] = true
end

local function get_next_birthday(next_tick)
    return birthday_triggers[next_tick] or math.huge
end

local function get_next_trigger_year_tick(next_tick)
    local next_trigger_tick = math.huge
    for _, trigger in ipairs(TICK_TRIGGERS) do
        local cur_rem = next_tick % trigger.mod
        for _, rem in ipairs(trigger.rem) do
            if cur_rem <= rem then
                next_trigger_tick = math.min(next_trigger_tick, next_tick + (rem - cur_rem))
                goto continue
            end
        end
        next_trigger_tick = math.min(next_trigger_tick, next_tick + trigger.mod - cur_rem + trigger.rem[#trigger.rem])
        ::continue::
    end
    return next_trigger_tick
end

local function clamp_timeskip(timeskip)
    timeskip = math.floor(timeskip)
    if timeskip <= 0 then return 0 end
    local next_tick = df.global.cur_year_tick + 1
    timeskip = math.min(timeskip, get_next_trigger_year_tick(next_tick)-next_tick)
    timeskip = math.min(timeskip, get_next_birthday(next_tick)-next_tick)
    return clamp_coverage(timeskip)
end

local function increment_counter(obj, counter_name, timeskip)
    if obj[counter_name] <= 0 then return end
    obj[counter_name] = obj[counter_name] + timeskip
end

local function decrement_counter(obj, counter_name, timeskip)
    if obj[counter_name] <= 0 then return end
    obj[counter_name] = math.max(1, obj[counter_name] - timeskip)
end

local function adjust_unit_counters(unit, timeskip)
    local c1 = unit.counters
    decrement_counter(c1, 'think_counter', timeskip)
    decrement_counter(c1, 'job_counter', timeskip)
    decrement_counter(c1, 'swap_counter', timeskip)
    decrement_counter(c1, 'winded', timeskip)
    decrement_counter(c1, 'stunned', timeskip)
    decrement_counter(c1, 'unconscious', timeskip)
    decrement_counter(c1, 'suffocation', timeskip)
    decrement_counter(c1, 'webbed', timeskip)
    decrement_counter(c1, 'soldier_mood_countdown', timeskip)
    decrement_counter(c1, 'pain', timeskip)
    decrement_counter(c1, 'nausea', timeskip)
    decrement_counter(c1, 'dizziness', timeskip)
    local c2 = unit.counters2
    decrement_counter(c2, 'paralysis', timeskip)
    decrement_counter(c2, 'numbness', timeskip)
    decrement_counter(c2, 'fever', timeskip)
    decrement_counter(c2, 'exhaustion', timeskip * 3)
    increment_counter(c2, 'hunger_timer', timeskip)
    increment_counter(c2, 'thirst_timer', timeskip)
    local job = unit.job.current_job
    if job and job.job_type == df.job_type.Rest then
        decrement_counter(c2, 'sleepiness_timer', timeskip * 200)
    elseif job and job.job_type == df.job_type.Sleep then
        decrement_counter(c2, 'sleepiness_timer', timeskip * 19)
    else
        increment_counter(c2, 'sleepiness_timer', timeskip)
    end
    decrement_counter(c2, 'stomach_content', timeskip * 5)
    decrement_counter(c2, 'stomach_food', timeskip * 5)
    decrement_counter(c2, 'vomit_timeout', timeskip)
    -- stored_fat wanders about based on other state; we can likely leave it alone and
    -- not materially affect gameplay
end

-- need to manually adjust job completion_timer values for jobs that are controlled by unit actions
-- with a timer of 1, which are destroyed immediately after they are created. longer-lived unit
-- actions are already sufficiently handled by dfhack.units.subtractGroupActionTimers().
-- this will also decrement timers for jobs with actions that have just expired, but on average, this
-- should balance out to be correct, since we're losing time when we subtract from the action timers
-- and cap the value so it never drops below 1.
local function adjust_job_counter(unit, timeskip)
    local job = unit.job.current_job
    if not job then return end
    for _,action in ipairs(unit.actions) do
        if action.type == df.unit_action_type.Job or action.type == df.unit_action_type.JobRecover then
            return
        end
    end
    decrement_counter(job, 'completion_timer', timeskip)
end

-- unit needs appear to be incremented on season ticks, so we don't need to worry about those
-- since the TICK_TRIGGERS check makes sure that we never skip season ticks
local function adjust_units(timeskip)
    for _, unit in ipairs(df.global.world.units.active) do
        if not dfhack.units.isActive(unit) then goto continue end
        decrement_counter(unit, 'pregnancy_timer', timeskip)
        dfhack.units.subtractGroupActionTimers(unit, timeskip, df.unit_action_type_group.All)
        if not dfhack.units.isOwnGroup(unit) then goto continue end
        adjust_unit_counters(unit, timeskip)
        adjust_job_counter(unit, timeskip)
        ::continue::
    end
end

-- behavior ascertained from in-game observation
local function adjust_activities(timeskip)
    for i, act in ipairs(df.global.world.activities.all) do
        for _, ev in ipairs(act.events) do
            if df.activity_event_training_sessionst:is_instance(ev) then
                -- no counters
            elseif df.activity_event_combat_trainingst:is_instance(ev) then
                -- has organize_counter at a non-zero value, but it doesn't seem to move
            elseif df.activity_event_skill_demonstrationst:is_instance(ev) then
                -- can be negative or positive, but always counts towards 0
                if ev.organize_counter < 0 then
                    ev.organize_counter = math.min(-1, ev.organize_counter + timeskip)
                else
                    decrement_counter(ev, 'organize_counter', timeskip)
                end
                decrement_counter(ev, 'train_countdown', timeskip)
            elseif df.activity_event_fill_service_orderst:is_instance(ev) then
                -- no counters
            elseif df.activity_event_individual_skill_drillst:is_instance(ev) then
                -- only counts down on season ticks, nothing to do here
            elseif df.activity_event_sparringst:is_instance(ev) then
                decrement_counter(ev, 'countdown', timeskip * 2)
            elseif df.activity_event_ranged_practicest:is_instance(ev) then
                -- countdown appears to never move from 0
                decrement_counter(ev, 'countdown', timeskip)
            elseif df.activity_event_harassmentst:is_instance(ev) then
                if DEBUG >= 1 then
                    print('activity_event_harassmentst ready for analysis at index', i)
                end
            elseif df.activity_event_encounterst:is_instance(ev) then
                if DEBUG >= 1 then
                    print('activity_event_encounterst ready for analysis at index', i)
                end
            elseif df.activity_event_reunionst:is_instance(ev) then
                if DEBUG >= 1 then
                    print('activity_event_reunionst ready for analysis at index', i)
                end
            elseif df.activity_event_conversationst:is_instance(ev) then
                increment_counter(ev, 'pause', timeskip)
            elseif df.activity_event_guardst:is_instance(ev) then
                -- no counters
            elseif df.activity_event_conflictst:is_instance(ev) then
                increment_counter(ev, 'inactivity_timer', timeskip)
                increment_counter(ev, 'attack_inactivity_timer', timeskip)
                increment_counter(ev, 'stop_fort_fights_timer', timeskip)
            elseif df.activity_event_prayerst:is_instance(ev) then
                decrement_counter(ev, 'timer', timeskip)
            elseif df.activity_event_researchst:is_instance(ev) then
                -- no counters
            elseif df.activity_event_playst:is_instance(ev) then
                increment_counter(ev, 'down_time_counter', timeskip)
            elseif df.activity_event_worshipst:is_instance(ev) then
                increment_counter(ev, 'down_time_counter', timeskip)
            elseif df.activity_event_socializest:is_instance(ev) then
                increment_counter(ev, 'down_time_counter', timeskip)
            elseif df.activity_event_ponder_topicst:is_instance(ev) then
                decrement_counter(ev, 'timer', timeskip)
            elseif df.activity_event_discuss_topicst:is_instance(ev) then
                decrement_counter(ev, 'timer', timeskip)
            elseif df.activity_event_teach_topicst:is_instance(ev) then
                decrement_counter(ev, 'time_left', timeskip)
            elseif df.activity_event_readst:is_instance(ev) then
                decrement_counter(ev, 'timer', timeskip)
            elseif df.activity_event_writest:is_instance(ev) then
                decrement_counter(ev, 'timer', timeskip)
            elseif df.activity_event_copy_written_contentst:is_instance(ev) then
                decrement_counter(ev, 'timer', timeskip)
            elseif df.activity_event_make_believest:is_instance(ev) then
                decrement_counter(ev, 'time_left', timeskip)
            elseif df.activity_event_play_with_toyst:is_instance(ev) then
                decrement_counter(ev, 'time_left', timeskip)
            elseif df.activity_event_performancest:is_instance(ev) then
                increment_counter(ev, 'current_position', timeskip)
            elseif df.activity_event_store_objectst:is_instance(ev) then
                if DEBUG >= 1 then
                    print('activity_event_store_objectst ready for analysis at index', i)
                end
            end
        end
    end
end

local function on_tick()
    record_coverage()

    if df.global.cur_year_tick % 10 == 0 then
        season_tick_throttled = false
        if df.global.cur_year_tick % 1000 == 0 then
            if DEBUG >= 1 then
                if DEBUG >= 3 then
                    print('checking coverage')
                end
                for coverage_slot=0,49 do
                    if not tick_coverage[coverage_slot] then
                        print('coverage slot not covered:', coverage_slot)
                    end
                end
            end
            tick_coverage = {}
        end
        if df.global.cur_year_tick == 0 then
            refresh_birthday_triggers()
        end
    end

    local real_fps = math.max(1, dfhack.internal.getUnpausedFps())
    if real_fps >= state.settings.fps then
        timeskip_deficit = 0.0
        return
    end

    local desired_timeskip = get_desired_timeskip(real_fps, state.settings.fps) + timeskip_deficit
    local timeskip = math.max(0, clamp_timeskip(desired_timeskip))

    -- don't let our deficit grow unbounded if we can never catch up
    timeskip_deficit = math.min(desired_timeskip - timeskip, 100.0)

    if DEBUG >= 2 then
        print(('cur_year_tick: %d, real_fps: %d, timeskip: (%d, +%.2f)'):format(
            df.global.cur_year_tick, real_fps, timeskip, timeskip_deficit))
    end
    if timeskip <= 0 then return end

    df.global.cur_year_tick = df.global.cur_year_tick + timeskip
    df.global.cur_year_tick_advmode = df.global.cur_year_tick_advmode + timeskip*144

    adjust_units(timeskip)
    adjust_activities(timeskip)
end

------------------------------------
-- hook management

local function do_enable()
    reset_ephemeral_state()
    eventful.enableEvent(eventful.eventType.UNIT_NEW_ACTIVE, 10)
    eventful.onUnitNewActive[GLOBAL_KEY] = check_new_unit
    state.enabled = true
    repeatutil.scheduleEvery(GLOBAL_KEY, 1, 'ticks', on_tick)
end

local function do_disable()
    state.enabled = false
    eventful.onUnitNewActive[GLOBAL_KEY] = nil
    repeatutil.cancel(GLOBAL_KEY)
end

dfhack.onStateChange[GLOBAL_KEY] = function(sc)
    if sc == SC_MAP_UNLOADED then
        do_disable()
        return
    end
    if sc ~= SC_MAP_LOADED or not dfhack.world.isFortressMode() then
        return
    end
    state = get_default_state()
    utils.assign(state, dfhack.persistent.getSiteData(GLOBAL_KEY, state))
    if state.enabled then
        do_enable()
    end
end

------------------------------------
-- interface

if dfhack_flags.module then
    return
end

if not dfhack.world.isFortressMode() or not dfhack.isMapLoaded() then
    qerror('needs a loaded fortress map to work')
end

local function print_status()
    print(GLOBAL_KEY .. ' is ' .. (state.enabled and 'enabled' or 'not enabled'))
    print()
    print('settings:')
    for _,v in ipairs(SETTINGS) do
        print(('  %15s: %s'):format(v.name, state.settings[v.internal_name or v.name]))
    end
    if DEBUG < 2 then return end
    print()
    print(('cur_year_tick:    %d'):format(df.global.cur_year_tick))
    print(('timeskip_deficit: %.2f'):format(timeskip_deficit))
    if DEBUG < 3 then return end
    print()
    print('tick coverage:')
    for coverage_slot=0,49 do
        print(('  slot %2d: %scovered'):format(coverage_slot, tick_coverage[coverage_slot] and '' or 'NOT '))
    end
    print()
    local bdays, bdays_list = {}, {}
    for _, next_bday in pairs(birthday_triggers) do
        if not bdays[next_bday] then
            bdays[next_bday] = true
            table.insert(bdays_list, next_bday)
        end
    end
    print(('%d birthdays:'):format(#bdays_list))
    table.sort(bdays_list)
    for _,bday in ipairs(bdays_list) do
        print(('  year tick: %d'):format(bday))
    end
end

local function do_set(setting_name, arg)
    if not setting_name or not arg then
        qerror('must specify setting and value')
    end
    local _, setting = utils.linear_index(SETTINGS, setting_name, 'name')
    if not setting then
        qerror('setting not found: ' .. setting_name)
    end
    state.settings[setting.internal_name or setting.name] = setting.validate(arg)
    print(('set %s to %s'):format(setting_name, state.settings[setting.internal_name or setting.name]))
end

local function do_reset()
    state = get_default_state()
end

local args = {...}
local command = table.remove(args, 1)

if dfhack_flags and dfhack_flags.enable then
    if dfhack_flags.enable_state then do_enable()
    else do_disable()
    end
elseif command == 'set' then
    do_set(args[1], args[2])
elseif command == 'reset' then
    do_reset()
elseif not command or command == 'status' then
    print_status()
    return
else
    print(dfhack.script_help())
    return
end

persist_state()
