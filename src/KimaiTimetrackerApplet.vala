/*
 * This file is part of the Budgie Desktop Kimai Timetracker Applet.
 *
 * Copyright (C) 2025 Peter Grønbæk Andersen <peter@grnbk.io>
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <https://www.gnu.org/licenses/>.
 */

using Budgie;
using Gtk;
using GLib;

public class KimaiTimetrackerPlugin : Budgie.Plugin, Peas.ExtensionBase {
    public Budgie.Applet get_panel_widget(string uuid) {
        return new KimaiTimetrackerApplet(uuid);
    }
}

public class KimaiTimetrackerApplet : Budgie.Applet {
    private Gtk.EventBox event_box;
    private Gtk.Image? applet_icon;

    private Budgie.Popover? popover = null;
    private unowned Budgie.PopoverManager? manager = null;

    private GLib.Settings? settings;

    public string uuid { public set; public get; }

    public KimaiTimetrackerApplet(string uuid) {
        Object(uuid: uuid);

        settings = new GLib.Settings("io.grnbk.kimaitimetracker");

        event_box = new Gtk.EventBox();
        this.add(event_box);
        applet_icon = new Gtk.Image.from_icon_name("appointment-new", Gtk.IconSize.MENU);
        event_box.add(applet_icon);

        popover = new KimaiTimetrackerWindow(event_box, settings);

        event_box.button_press_event.connect((e) => {
            if (e.button == 1) {
                if (popover.get_visible()) {
                    popover.hide();
                } else {
                    popover.show_all();
                    this.manager.show_popover(event_box);
                }
                return Gdk.EVENT_STOP;
            }
            return Gdk.EVENT_PROPAGATE;
        });

        this.show_all();
    }

    public override void update_popovers(Budgie.PopoverManager? manager) {
        manager.register_popover(event_box, popover);
        this.manager = manager;
    }

    public override bool supports_settings() {
        return true;
    }

    public override Gtk.Widget? get_settings_ui() {
        return new Label("No settings yet");
    }
}

[ModuleInit]
public void peas_register_types(TypeModule module) {
    var objmodule = module as Peas.ObjectModule;
    objmodule.register_extension_type(typeof(Budgie.Plugin), typeof(KimaiTimetrackerPlugin));
}