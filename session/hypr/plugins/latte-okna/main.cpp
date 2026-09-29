// latte-okna — Hyprland plugin LatteOS (alfatest 1): pošle do Lua udalosti ťahania okna, aby latte/prichytenie.lua
// vedelo prichytiť okno k okraju ako Windows (hore = maximalizovať, bok = polovica, roh = štvrtina).
// Hyprland 0.56.2 na to udalosť nemá: plugin sleduje pohyb a tlačidlá myši na zbernici udalostí a pýta sa
// DragStateController, či sa práve presúva plávajúce okno (ťahanie za titulok, Super + ťahanie, ťahanie CSD hlavičky).
//   hl.on("latte.drag_motion", function(window, x, y) … end)   presun plávajúceho okna myšou (x, y = kurzor)
//   hl.on("latte.drag_end",    function(window, x, y) … end)   pustenie tlačidla
// SPDX-License-Identifier: MIT
#define WLR_USE_UNSTABLE

#include <hyprland/src/plugins/PluginAPI.hpp>
#include <hyprland/src/event/EventBus.hpp>
#include <hyprland/src/layout/LayoutManager.hpp>
#include <hyprland/src/layout/supplementary/DragController.hpp>
#include <hyprland/src/layout/target/Target.hpp>
#include <hyprland/src/managers/input/InputManager.hpp>
#include <hyprland/src/desktop/view/Window.hpp>

using CCustomEvent = Event::CEventBus::CCustomEvent;

static HANDLE                           g_handle = nullptr;
static SP<CCustomEvent>                 g_motion, g_end;
static CHyprSignalListener              g_moveListener, g_buttonListener;
static PHLWINDOWREF                     g_dragged;

APICALL EXPORT std::string PLUGIN_API_VERSION() {
    return HYPRLAND_API_VERSION;
}

static void onMotion(const Vector2D& mouse) {
    const auto& dc = g_layoutManager->dragController();
    if (!dc || dc->mode() != MBIND_MOVE)
        return;
    const auto target = dc->target();
    const auto w      = target ? target->window() : nullptr;
    if (!w || !w->m_isFloating)
        return;
    g_dragged = w;
    (void)g_motion->emit({PHLWINDOWREF{w}, mouse.x, mouse.y});
}

static void onEnd() {
    const auto w = g_dragged.lock();
    g_dragged.reset();
    if (!w)
        return;
    const auto mouse = g_pInputManager->getMouseCoordsInternal();
    (void)g_end->emit({PHLWINDOWREF{w}, mouse.x, mouse.y});
}

APICALL EXPORT PLUGIN_DESCRIPTION_INFO PLUGIN_INIT(HANDLE handle) {
    g_handle = handle;
    using T  = CCustomEvent::eType;
    g_motion = makeShared<CCustomEvent>("latte.drag_motion", std::vector<T>{T::TYPE_WINDOW, T::TYPE_DOUBLE, T::TYPE_DOUBLE});
    g_end    = makeShared<CCustomEvent>("latte.drag_end", std::vector<T>{T::TYPE_WINDOW, T::TYPE_DOUBLE, T::TYPE_DOUBLE});
    HyprlandAPI::addEvent(handle, g_motion);
    HyprlandAPI::addEvent(handle, g_end);
    g_moveListener   = Event::bus()->m_events.input.mouse.move.listen([](Vector2D pos, Event::SCallbackInfo&) { onMotion(pos); });
    g_buttonListener = Event::bus()->m_events.input.mouse.button.listen([](IPointer::SButtonEvent e, Event::SCallbackInfo&) {
        if (e.state == WL_POINTER_BUTTON_STATE_RELEASED && g_dragged.lock())
            onEnd();
    });
    return {"latte-okna", "LatteOS: udalosti ťahania okien pre prichytenie k okrajom", "LatteOS", "0.1"};
}

APICALL EXPORT void PLUGIN_EXIT() {
    g_moveListener.reset();
    g_buttonListener.reset();
    HyprlandAPI::removeEvent(g_handle, "latte.drag_motion");
    HyprlandAPI::removeEvent(g_handle, "latte.drag_end");
}
