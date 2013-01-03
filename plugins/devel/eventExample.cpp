
#include "Console.h"
#include "Core.h"
#include "Export.h"
#include "PluginManager.h"
#include "modules/EventManager.h"
#include "DataDefs.h"

#include "df/item.h"
#include "df/world.h"

#include <vector>

using namespace DFHack;
using namespace std;

DFHACK_PLUGIN("eventExample");

void jobInitiated(color_ostream& out, void* job);
void jobCompleted(color_ostream& out, void* job);
void timePassed(color_ostream& out, void* ptr);
void unitDeath(color_ostream& out, void* ptr);
void itemCreate(color_ostream& out, void* ptr);
void building(color_ostream& out, void* ptr);
void construction(color_ostream& out, void* ptr);
void syndrome(color_ostream& out, void* ptr);
void invasion(color_ostream& out, void* ptr);

command_result eventExample(color_ostream& out, vector<string>& parameters);

DFhackCExport command_result plugin_init(color_ostream &out, std::vector<PluginCommand> &commands) {
    commands.push_back(PluginCommand("eventExample", "Sets up a few event triggers.",eventExample));
    return CR_OK;
}

command_result eventExample(color_ostream& out, vector<string>& parameters) {
    EventManager::EventHandler initiateHandler(jobInitiated);
    EventManager::EventHandler completeHandler(jobCompleted);
    EventManager::EventHandler timeHandler(timePassed);
    EventManager::EventHandler deathHandler(unitDeath);
    EventManager::EventHandler itemHandler(itemCreate);
    EventManager::EventHandler buildingHandler(building);
    EventManager::EventHandler constructionHandler(construction);
    EventManager::EventHandler syndromeHandler(syndrome);
    EventManager::EventHandler invasionHandler(invasion);
    Plugin* me = Core::getInstance().getPluginManager()->getPluginByName("eventExample");
    EventManager::unregisterAll(me);

    EventManager::registerListener(EventManager::EventType::JOB_INITIATED, initiateHandler, 10, me);
    EventManager::registerListener(EventManager::EventType::JOB_COMPLETED, completeHandler, 5, me);
    EventManager::registerTick(timeHandler, 1, me);
    EventManager::registerTick(timeHandler, 2, me);
    EventManager::registerTick(timeHandler, 4, me);
    EventManager::registerTick(timeHandler, 8, me);
    EventManager::registerListener(EventManager::EventType::UNIT_DEATH, deathHandler, 500, me);
    EventManager::registerListener(EventManager::EventType::ITEM_CREATED, itemHandler, 1000, me);
    EventManager::registerListener(EventManager::EventType::BUILDING, buildingHandler, 500, me);
    EventManager::registerListener(EventManager::EventType::CONSTRUCTION, constructionHandler, 100, me);
    EventManager::registerListener(EventManager::EventType::SYNDROME, syndromeHandler, 1, me);
    EventManager::registerListener(EventManager::EventType::INVASION, invasionHandler, 1, me);
    out.print("Events registered.\n");
    return CR_OK;
}

void jobInitiated(color_ostream& out, void* job) {
    out.print("Job initiated! 0x%X\n", job);
}

void jobCompleted(color_ostream& out, void* job) {
    out.print("Job completed! 0x%X\n", job);
}

void timePassed(color_ostream& out, void* ptr) {
    out.print("Time: %d\n", (int32_t)(ptr));
}

void unitDeath(color_ostream& out, void* ptr) {
    out.print("Death: %d\n", (int32_t)(ptr));
}

void itemCreate(color_ostream& out, void* ptr) {
    int32_t item_index = df::item::binsearch_index(df::global::world->items.all, (int32_t)ptr);
    if ( item_index == -1 ) {
        out.print("%s, %d: Error.\n", __FILE__, __LINE__);
    }
    df::item* item = df::global::world->items.all[item_index];
    df::item_type type = item->getType();
    df::coord pos = item->pos;
    out.print("Item created: %d, %s, at (%d,%d,%d)\n", (int32_t)(ptr), ENUM_KEY_STR(item_type, type).c_str(), pos.x, pos.y, pos.z);
}

void building(color_ostream& out, void* ptr) {
    out.print("Building created/destroyed: %d\n", (int32_t)ptr);
}

void construction(color_ostream& out, void* ptr) {
    out.print("Construction created/destroyed: 0x%X\n", ptr);
}

void syndrome(color_ostream& out, void* ptr) {
    EventManager::SyndromeData* data = (EventManager::SyndromeData*)ptr;
    out.print("Syndrome started: unit %d, syndrome %d.\n", data->unitId, data->syndromeIndex);
}

void invasion(color_ostream& out, void* ptr) {
    out.print("New invasion! %d\n", (int32_t)ptr);
}

