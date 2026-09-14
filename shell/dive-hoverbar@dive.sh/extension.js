// Dive Hover Bar — GNOME Shell extension.
// The top bar slides away and comes back when the pointer touches the top edge.
// Windows are allowed to use the space underneath it.

import Clutter from 'gi://Clutter';
import GLib from 'gi://GLib';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';

const SLIDE_MS = 180;
const HIDE_DELAY_MS = 350;

export default class DiveHoverBar extends Extension {
    enable() {
        this._panelBox = Main.layoutManager.panelBox;
        this._signals = [];
        this._hideTimeout = 0;
        this._menuSignal = null;

        // Re-register the panel so it no longer reserves screen space (struts).
        Main.layoutManager.removeChrome(this._panelBox);
        Main.layoutManager.addChrome(this._panelBox, {affectsStruts: false, trackFullscreen: true});

        // A one-pixel strip along the top edge that wakes the bar.
        this._edge = new Clutter.Actor({reactive: true, name: 'dive-hover-edge'});
        Main.layoutManager.addChrome(this._edge, {affectsInputRegion: true, trackFullscreen: true});
        // Keep it under the panel so the panel gets the pointer while visible.
        Main.layoutManager.uiGroup.set_child_below_sibling(this._edge, this._panelBox);
        this._placeEdge();

        this._connect(this._edge, 'enter-event', () => { this._show(); return Clutter.EVENT_PROPAGATE; });
        this._connect(this._panelBox, 'leave-event', () => { this._scheduleHide(); return Clutter.EVENT_PROPAGATE; });
        this._connect(this._panelBox, 'enter-event', () => { this._cancelHide(); return Clutter.EVENT_PROPAGATE; });
        this._connect(Main.layoutManager, 'monitors-changed', () => this._placeEdge());
        this._connect(Main.overview, 'showing', () => this._show());
        this._connect(Main.overview, 'hidden', () => this._scheduleHide());

        // Start hidden, unless the overview is open.
        if (!Main.overview.visible)
            this._hide(false);
    }

    disable() {
        this._cancelHide();
        if (this._menuSignal) {
            this._menuSignal.menu.disconnect(this._menuSignal.id);
            this._menuSignal = null;
        }
        for (const [obj, id] of this._signals)
            obj.disconnect(id);
        this._signals = [];

        if (this._edge) {
            Main.layoutManager.removeChrome(this._edge);
            this._edge.destroy();
            this._edge = null;
        }
        this._panelBox.remove_all_transitions();
        this._panelBox.translation_y = 0;
        Main.layoutManager.removeChrome(this._panelBox);
        Main.layoutManager.addChrome(this._panelBox, {affectsStruts: true, trackFullscreen: true});
        this._panelBox = null;
    }

    _connect(obj, signal, cb) {
        this._signals.push([obj, obj.connect(signal, cb)]);
    }

    _placeEdge() {
        const m = Main.layoutManager.primaryMonitor;
        if (!m || !this._edge) return;
        this._edge.set_position(m.x, m.y);
        this._edge.set_size(m.width, 1);
    }

    _show() {
        this._cancelHide();
        this._panelBox.remove_all_transitions();
        this._panelBox.ease({
            translation_y: 0,
            duration: SLIDE_MS,
            mode: Clutter.AnimationMode.EASE_OUT_QUAD,
        });
    }

    _hide(animate = true) {
        const h = this._panelBox.height || Main.panel.height;
        this._panelBox.remove_all_transitions();
        if (animate) {
            this._panelBox.ease({
                translation_y: -h,
                duration: SLIDE_MS,
                mode: Clutter.AnimationMode.EASE_IN_QUAD,
            });
        } else {
            this._panelBox.translation_y = -h;
        }
    }

    _scheduleHide() {
        this._cancelHide();
        this._hideTimeout = GLib.timeout_add(GLib.PRIORITY_DEFAULT, HIDE_DELAY_MS, () => {
            this._hideTimeout = 0;
            this._hideIfIdle();
            return GLib.SOURCE_REMOVE;
        });
    }

    _cancelHide() {
        if (this._hideTimeout) {
            GLib.source_remove(this._hideTimeout);
            this._hideTimeout = 0;
        }
    }

    _hideIfIdle() {
        if (Main.overview.visible) return;
        // Keep the bar while one of its menus (clock, quick settings, Dive menu…) is open.
        const menu = Main.panel.menuManager.activeMenu;
        if (menu) {
            if (this._menuSignal) return;
            const id = menu.connect('open-state-changed', (_m, open) => {
                if (open) return;
                menu.disconnect(id);
                this._menuSignal = null;
                this._scheduleHide();
            });
            this._menuSignal = {menu, id};
            return;
        }
        // Pointer still on the bar? Then stay.
        const [, y] = global.get_pointer();
        const m = Main.layoutManager.primaryMonitor;
        if (m && y <= m.y + this._panelBox.height) return;
        this._hide(true);
    }
}
