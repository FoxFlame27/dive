#!/usr/bin/env python3
"""Dive first-run setup: Welcome → Bring Windows over → You → Ready."""
import json, os, subprocess, sys, threading
from pathlib import Path

import gi
gi.require_version('Gtk', '4.0'); gi.require_version('Adw', '1')
from gi.repository import Adw, Gtk, GLib, Gio, Gdk

DONE = Path.home() / '.config/dive/setup-done'
FORCE = '--again' in sys.argv

CSS = b"""
.dive-title { font-size: 26pt; font-weight: 700; }
.dive-lead  { font-size: 12pt; color: alpha(@window_fg_color, .7); }
.dive-side  { background: alpha(@window_fg_color, .04); }
.dive-step  { padding: 8px 12px; border-radius: 8px; color: alpha(@window_fg_color, .5); }
.dive-step.current { background: alpha(@window_fg_color, .08); color: @window_fg_color; font-weight: 600; }
.dive-step.done { color: @accent_color; }
"""

class Welcome(Adw.Application):
    def __init__(self):
        super().__init__(application_id='sh.dive.Welcome', flags=Gio.ApplicationFlags.FLAGS_NONE)
        self.scan = {}

    def do_activate(self):
        if DONE.exists() and not FORCE:
            return
        prov = Gtk.CssProvider(); prov.load_from_data(CSS)
        Gtk.StyleContext.add_provider_for_display(Gdk.Display.get_default(), prov, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)
        self.win = Adw.ApplicationWindow(application=self, title='Welcome to Dive', default_width=980, default_height=640)
        self.win.set_resizable(False)
        outer = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL)
        self.win.set_content(outer)

        side = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6, width_request=230, margin_top=28, margin_bottom=28, margin_start=20, margin_end=20)
        side.add_css_class('dive-side')
        logo = Gtk.Image.new_from_file('/usr/share/dive/dive-logo.svg'); logo.set_pixel_size(44); logo.set_halign(Gtk.Align.START)
        side.append(logo)
        side.append(Gtk.Label(label='Dive', xalign=0, css_classes=['title-2'], margin_bottom=18))
        self.step_labels = []
        for i, t in enumerate(('Welcome', 'Bring Windows over', 'You', 'Ready')):
            l = Gtk.Label(label=f'{i + 1}   {t}', xalign=0); l.add_css_class('dive-step'); side.append(l); self.step_labels.append(l)
        outer.append(side)

        main = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, margin_top=36, margin_bottom=28, margin_start=40, margin_end=40, hexpand=True)
        outer.append(main)
        self.stack = Gtk.Stack(transition_type=Gtk.StackTransitionType.SLIDE_LEFT_RIGHT, vexpand=True)
        main.append(self.stack)
        nav = Gtk.Box(spacing=8, margin_top=16)
        self.back = Gtk.Button(label='Back'); self.back.connect('clicked', lambda *_: self.go(self.i - 1))
        self.next = Gtk.Button(label='Continue', css_classes=['suggested-action', 'pill']); self.next.connect('clicked', self.on_next)
        nav.append(self.back); nav.append(Gtk.Box(hexpand=True)); nav.append(self.next)
        main.append(nav)

        self.stack.add_named(self.page_welcome(), 'welcome')
        self.stack.add_named(self.page_import(), 'import')
        self.stack.add_named(self.page_you(), 'you')
        self.stack.add_named(self.page_ready(), 'ready')
        self.i = 0; self.go(0)
        self.win.present()
        threading.Thread(target=self.do_scan, daemon=True).start()

    # ---- pages
    def header(self, box, title, lead):
        t = Gtk.Label(label=title, xalign=0, wrap=True); t.add_css_class('dive-title'); box.append(t)
        l = Gtk.Label(label=lead, xalign=0, wrap=True, max_width_chars=60); l.add_css_class('dive-lead'); l.set_margin_bottom(20); box.append(l)

    def page_welcome(self):
        b = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        self.header(b, 'Welcome to Dive.', 'The comfort of Windows with the calm of GNOME. This takes about a minute, and nothing here is permanent.')
        g = Adw.PreferencesGroup(); b.append(g)
        r = Adw.ActionRow(title='Language and keyboard', subtitle='Change them any time in Settings → System → Region & Language')
        btn = Gtk.Button(label='Open Settings', valign=Gtk.Align.CENTER); btn.connect('clicked', lambda *_: subprocess.Popen(['gnome-control-center', 'region']))
        r.add_suffix(btn); g.add(r)
        r2 = Adw.ActionRow(title='Shortcuts you will use', subtitle='Super opens the Dive menu · Super+Shift+S screenshots · Super+V clipboard · hover the top edge for the bar'); g.add(r2)
        return b

    def page_import(self):
        b = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        self.header(b, 'Bring your Windows over.', 'Looking for your Windows install on this disk. Nothing is moved, so Windows keeps working as before.')
        self.import_group = Adw.PreferencesGroup(); b.append(self.import_group)
        self.checks = {}
        for key, title, sub in (
            ('files', 'Desktop, Documents, Pictures, Downloads', 'Linked into your Dive folders'),
            ('apps', 'Apps', 'Native versions where they exist, the rest through Dive Bridge'),
            ('browser', 'Browser bookmarks and settings', 'Chrome, Edge, Brave and Firefox'),
            ('wifi', 'Wi‑Fi networks', 'Saved networks with passwords'),
        ):
            r = Adw.SwitchRow(title=title, subtitle=sub, active=True); self.import_group.add(r); self.checks[key] = r
        self.import_status = Gtk.Label(label='Scanning…', xalign=0, margin_top=12); self.import_status.add_css_class('dim-label'); b.append(self.import_status)
        return b

    def page_you(self):
        b = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        import pwd
        name = pwd.getpwuid(os.getuid()).pw_gecos.split(',')[0] or os.getlogin()
        self.header(b, f'Hi {name}.', 'This account was made during install. Your picture and password live in Settings → System → Users.')
        g = Adw.PreferencesGroup(); b.append(g)
        r = Adw.ActionRow(title='Account picture and password')
        btn = Gtk.Button(label='Open Users', valign=Gtk.Align.CENTER); btn.connect('clicked', lambda *_: subprocess.Popen(['gnome-control-center', 'user-accounts'])); r.add_suffix(btn); g.add(r)
        r = Adw.SwitchRow(title='Dark look', subtitle='Dive is designed dark. Turn this off for the light look.', active=True)
        r.connect('notify::active', lambda w, _: subprocess.Popen(['gsettings', 'set', 'org.gnome.desktop.interface', 'color-scheme', 'prefer-dark' if w.get_active() else 'default'])); g.add(r)
        return b

    def page_ready(self):
        b = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        self.header(b, 'Diving in.', 'Your stuff is being brought over. You can close this and keep using Dive; it finishes in the background.')
        self.progress = Gtk.ProgressBar(margin_bottom=12); b.append(self.progress)
        sc = Gtk.ScrolledWindow(vexpand=True); b.append(sc)
        self.log = Gtk.TextView(editable=False, monospace=True, cursor_visible=False); sc.set_child(self.log)
        return b

    # ---- logic
    def do_scan(self):
        try:
            out = subprocess.run(['dive-migrate', 'scan'], capture_output=True, text=True, timeout=120).stdout
            self.scan = json.loads(out or '{}')
        except Exception as e:
            self.scan = {'error': str(e)}
        GLib.idle_add(self.scan_done)

    def scan_done(self):
        s = self.scan
        if not s.get('windows'):
            self.import_status.set_label('No Windows installation found on this disk. You can skip this step.')
            for r in self.checks.values(): r.set_active(False)
            return
        users = ', '.join(s.get('users', [])) or 'unknown user'
        sizes = s.get('sizes', {})
        total = sum(sum(v.values()) for v in sizes.values())
        parts = [f'Windows found at {s["windows"]} ({users}).', f'{total / 1e9:.1f} GB of personal files.']
        if 'apps' in s: parts.append(f'{s["apps"]} apps and {s.get("wifi", 0)} Wi‑Fi networks exported by the installer.')
        else: parts.append('No app or Wi‑Fi export found: apps and Wi‑Fi will be skipped.'); self.checks['apps'].set_active(False); self.checks['wifi'].set_active(False)
        self.import_status.set_label(' '.join(parts))

    def go(self, i):
        self.i = max(0, min(3, i))
        self.stack.set_visible_child_name(['welcome', 'import', 'you', 'ready'][self.i])
        for k, l in enumerate(self.step_labels):
            l.remove_css_class('current'); l.remove_css_class('done')
            if k < self.i: l.add_css_class('done')
            if k == self.i: l.add_css_class('current')
        self.back.set_visible(self.i > 0)
        self.next.set_label('Start using Dive' if self.i == 3 else 'Continue')
        if self.i == 3: self.run_migrate()

    def on_next(self, *_):
        if self.i < 3: self.go(self.i + 1); return
        DONE.parent.mkdir(parents=True, exist_ok=True); DONE.write_text('1\n')
        self.win.close()

    def run_migrate(self):
        flags = [f'--{k}' for k, r in self.checks.items() if r.get_active()]
        if not flags or not self.scan.get('windows'):
            self.progress.set_fraction(1); self.append_log('Nothing to bring over. Enjoy Dive.\n'); return
        self.progress.pulse()
        def work():
            p = subprocess.Popen(['dive-migrate', 'run', *flags], stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
            for line in p.stdout:
                GLib.idle_add(self.append_log, line); GLib.idle_add(self.progress.pulse)
            p.wait()
            GLib.idle_add(self.progress.set_fraction, 1.0)
        threading.Thread(target=work, daemon=True).start()

    def append_log(self, text):
        buf = self.log.get_buffer(); buf.insert(buf.get_end_iter(), text.replace('[dive-migrate] ', ''))

if __name__ == '__main__':
    sys.exit(Welcome().run([a for a in sys.argv if a != '--again']))
