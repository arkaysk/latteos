// latte-okna — Hyprland plugin LatteOS (alfatest 1): pošle do Lua udalosti ťahania okna, aby latte/prichytenie.lua
// vedelo prichytiť okno k okraju ako Windows (hore = maximalizovať, bok = polovica, roh = štvrtina).
// Hyprland 0.56.2 na to udalosť nemá: plugin sleduje pohyb a tlačidlá myši na zbernici udalostí a pýta sa
// DragStateController, či sa práve presúva plávajúce okno (ťahanie za titulok, Super + ťahanie, ťahanie CSD hlavičky).
//   hl.on("latte.drag_motion", function(window, x, y) … end)   presun plávajúceho okna myšou (x, y = kurzor)
//   hl.on("latte.drag_end",    function(window, x, y) … end)   pustenie tlačidla
// Ďalej: žiadosť aplikácie o minimalizáciu (tlačidlo „–“ v jej vlastnom titulku, napr. Steam, GTK/CSD aplikácie).
// Hyprland 0.56 ju prijme (xdg_toplevel.set_minimized, X11 WM_CHANGE_STATE), ale nič s ňou nerobí:
//   hl.on("latte.minimize_request", function(window) … end)
// SPDX-License-Identifier: MIT
#define WLR_USE_UNSTABLE

#include <hyprland/src/plugins/PluginAPI.hpp>
#include <hyprland/src/event/EventBus.hpp>
#include <hyprland/src/layout/LayoutManager.hpp>
#include <hyprland/src/layout/supplementary/DragController.hpp>
#include <hyprland/src/layout/target/Target.hpp>
#include <hyprland/src/managers/input/InputManager.hpp>
#include <hyprland/src/desktop/view/Window.hpp>
#include <hyprland/src/protocols/XDGShell.hpp>
#include <hyprland/src/xwayland/XSurface.hpp>
#include <hyprland/src/Compositor.hpp>
#include <unordered_map>

using CCustomEvent = Event::CEventBus::CCustomEvent;

static HANDLE                           g_handle = nullptr;
static SP<CCustomEvent>                 g_motion, g_end, g_minimize;
static CHyprSignalListener              g_moveListener, g_buttonListener, g_openListener, g_destroyListener;
static std::unordered_map<Desktop::View::CWindow*, CHyprSignalListener> g_stateListeners;   // stateChanged povrchu každého okna
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

// stav („volatile“) platí počas emitu stateChanged — Hyprland ho vynuluje až po všetkých poslucháčoch
static void watchMinimize(PHLWINDOW w) {
    if (!w || g_stateListeners.contains(w.get()))
        return;
    PHLWINDOWREF ref{w};
    if (const auto xw = w->m_xwaylandSurface.lock()) {
        g_stateListeners[w.get()] = xw->m_events.stateChanged.listen([ref, xwr = WP<CXWaylandSurface>{xw}] {
            const auto s = xwr.lock();
            if (s && s->m_state.requestsMinimize.value_or(false) && ref.lock())
                (void)g_minimize->emit({ref});
        });
    } else if (const auto xdg = w->m_xdgSurface.lock(); xdg && xdg->m_toplevel.lock()) {
        const auto tl = xdg->m_toplevel.lock();
        g_stateListeners[w.get()] = tl->m_events.stateChanged.listen([ref, tlr = WP<CXDGToplevelResource>{tl}] {
            const auto t = tlr.lock();
            if (t && t->m_state.requestsMinimize.value_or(false) && ref.lock())
                (void)g_minimize->emit({ref});
        });
    }
}

APICALL EXPORT PLUGIN_DESCRIPTION_INFO PLUGIN_INIT(HANDLE handle) {
    g_handle = handle;
    using T  = CCustomEvent::eType;
    g_motion = makeShared<CCustomEvent>("latte.drag_motion", std::vector<T>{T::TYPE_WINDOW, T::TYPE_DOUBLE, T::TYPE_DOUBLE});
    g_end    = makeShared<CCustomEvent>("latte.drag_end", std::vector<T>{T::TYPE_WINDOW, T::TYPE_DOUBLE, T::TYPE_DOUBLE});
    HyprlandAPI::addEvent(handle, g_motion);
    HyprlandAPI::addEvent(handle, g_end);
    g_minimize = makeShared<CCustomEvent>("latte.minimize_request", std::vector<T>{T::TYPE_WINDOW});
    HyprlandAPI::addEvent(handle, g_minimize);
    g_openListener    = Event::bus()->m_events.window.open.listen([](PHLWINDOW w) { watchMinimize(w); });
    // pri zatvorení (okno ešte žije) — nový objekt na tej istej adrese by inak watchMinimize preskočil
    g_destroyListener = Event::bus()->m_events.window.close.listen([](PHLWINDOW w) { if (w) g_stateListeners.erase(w.get()); });
    for (const auto& w : Desktop::windowState()->windows())   // okná otvorené pred načítaním pluginu
        if (w->m_isMapped) watchMinimize(w);
    g_moveListener   = Event::bus()->m_events.input.mouse.move.listen([](Vector2D pos, Event::SCallbackInfo&) { onMotion(pos); });
    g_buttonListener = Event::bus()->m_events.input.mouse.button.listen([](IPointer::SButtonEvent e, Event::SCallbackInfo&) {
        if (e.state == WL_POINTER_BUTTON_STATE_RELEASED && g_dragged.lock())
            onEnd();
    });
    return {"latte-okna", "LatteOS: ťahanie okien (prichytenie k okrajom) a žiadosti o minimalizáciu", "LatteOS", "0.2"};
}

APICALL EXPORT void PLUGIN_EXIT() {
    g_moveListener.reset();
    g_buttonListener.reset();
    g_openListener.reset();
    g_destroyListener.reset();
    g_stateListeners.clear();
    HyprlandAPI::removeEvent(g_handle, "latte.minimize_request");
    HyprlandAPI::removeEvent(g_handle, "latte.drag_motion");
    HyprlandAPI::removeEvent(g_handle, "latte.drag_end");
}
