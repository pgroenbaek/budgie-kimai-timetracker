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

using GLib;
using Gtk;
using Budgie;

public class KimaiTimetrackerWindow : Budgie.Popover {
    private Gtk.Label lbl_client;
    private Gtk.Label lbl_project;
    private Gtk.Label lbl_task;
    private Gtk.Label lbl_duration;

    private Gtk.Button btn_start;
    private Gtk.Button btn_stop;
    private Gtk.Button btn_new_timer;
    private Gtk.Button btn_settings;

    private Gtk.ComboBoxText combo_client;
    private Gtk.ComboBoxText combo_project;
    private Gtk.ComboBoxText combo_task;
    private Gtk.Entry entry_desc;

    private Gtk.Box main_view;
    private Gtk.Box form_view;

    private KimaiAPI api;
    private KimaiTimerManager timer_mgr;

    private unowned GLib.Settings? settings;

    public KimaiTimetrackerWindow(Gtk.Widget? c_parent, GLib.Settings? c_settings) {
        Object(relative_to: c_parent);
        settings = c_settings;
        get_style_context().add_class("kimaitimetracker-popover");

        api = new KimaiAPI("https://demo.kimai.org/api", "");
        timer_mgr = new KimaiTimerManager(api);

        var vbox = new Gtk.Box(Gtk.Orientation.VERTICAL, 6);
        vbox.set_margin_top(6);
        vbox.set_margin_bottom(6);
        vbox.set_margin_start(6);
        vbox.set_margin_end(6);
        vbox.set_size_request(300, -1);
        add(vbox);

        main_view = build_main_view();
        form_view = build_form_view();
        vbox.add(main_view);

        timer_mgr.updated.connect(update_labels);
        timer_mgr.stopped.connect(() => lbl_duration.set_text("Duration: 00:00:00"));
        timer_mgr.refresh_from_server();

        this.show_all();
    }

    private Gtk.Box build_main_view() {
        var box = new Gtk.Box(Gtk.Orientation.VERTICAL, 6);

        lbl_client = new Gtk.Label("Client: -");
        lbl_project = new Gtk.Label("Project: -");
        lbl_task = new Gtk.Label("Task: -");
        lbl_duration = new Gtk.Label("Duration: 00:00:00");
        box.add(lbl_client);
        box.add(lbl_project);
        box.add(lbl_task);
        box.add(lbl_duration);

        var hbox_buttons = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6);
        btn_start = new Gtk.Button.with_label("▶ Start");
        btn_stop  = new Gtk.Button.with_label("■ Stop");
        hbox_buttons.add(btn_start);
        hbox_buttons.add(btn_stop);
        box.add(hbox_buttons);

        var vbox_bottom = new Gtk.Box(Gtk.Orientation.VERTICAL, 6);
        btn_new_timer = new Gtk.Button.with_label("+ New Timer");
        btn_settings = new Gtk.Button.with_label("Settings");
        vbox_bottom.add(btn_new_timer);
        vbox_bottom.add(btn_settings);
        box.add(vbox_bottom);

        btn_start.clicked.connect(() => {
            if (timer_mgr.active_timesheet == null) switch_to_form();
            else timer_mgr.refresh_from_server();
        });
        btn_stop.clicked.connect(() => timer_mgr.stop_timer());
        btn_new_timer.clicked.connect(() => switch_to_form());

        return box;
    }

    private Gtk.Box build_form_view() {
        var box = new Gtk.Box(Gtk.Orientation.VERTICAL, 6);
        var grid = new Gtk.Grid();
        grid.set_row_spacing(6);
        grid.set_column_spacing(6);

        combo_client = new Gtk.ComboBoxText();
        combo_project = new Gtk.ComboBoxText();
        combo_task = new Gtk.ComboBoxText();
        entry_desc = new Gtk.Entry();

        try {
            var clients = api.list_customers();
            foreach (var cust in clients) {
                combo_client.append(cust.id.to_string(), cust.name);
            }
        } catch (Error e) {
            warning("Could not fetch customers: %s", e.message);
        }

        combo_client.changed.connect(() => {
            combo_project.remove_all();
            combo_task.remove_all();
            var sel = combo_client.get_active_id();
            if (sel != null) {
                int cid = int.parse(sel);
                try {
                    var projects = api.list_projects(cid);
                    foreach (var proj in projects) {
                        combo_project.append(proj.id.to_string(), proj.name);
                    }
                } catch (Error e) {
                    warning("Could not fetch projects: %s", e.message);
                }
            }
        });

        combo_project.changed.connect(() => {
            combo_task.remove_all();
            var selp = combo_project.get_active_id();
            if (selp != null) {
                int pid = int.parse(selp);
                try {
                    var acts = api.list_activities(pid);
                    foreach (var act in acts) {
                        combo_task.append(act.id.to_string(), act.name);
                    }
                } catch (Error e) {
                    warning("Could not fetch activities: %s", e.message);
                }
            }
        });

        grid.attach(new Gtk.Label("Client:"), 0, 0, 1, 1);
        grid.attach(combo_client, 1, 0, 1, 1);
        grid.attach(new Gtk.Label("Project:"), 0, 1, 1, 1);
        grid.attach(combo_project, 1, 1, 1, 1);
        grid.attach(new Gtk.Label("Task:"), 0, 2, 1, 1);
        grid.attach(combo_task, 1, 2, 1, 1);
        grid.attach(new Gtk.Label("Description:"), 0, 3, 1, 1);
        grid.attach(entry_desc, 1, 3, 1, 1);

        box.add(grid);

        var vbox_bottom = new Gtk.Box(Gtk.Orientation.VERTICAL, 6);
        var btn_start_new = new Gtk.Button.with_label("Start Timer");
        var btn_back = new Gtk.Button.with_label("Back");
        vbox_bottom.add(btn_start_new);
        vbox_bottom.add(btn_back);
        box.add(vbox_bottom);

        btn_back.clicked.connect(() => switch_to_main());
        btn_start_new.clicked.connect(() => {
            var proj_id_str = combo_project.get_active_id();
            var act_id_str  = combo_task.get_active_id();
            if (proj_id_str == null || act_id_str == null) return;

            var proj_id = int.parse(proj_id_str);
            var act_id  = int.parse(act_id_str);
            var desc    = entry_desc.get_text();

            timer_mgr.start_timer(proj_id, act_id, desc);
            switch_to_main();
        });

        return box;
    }

    private void switch_to_form() {
        var parent = (Gtk.Box) main_view.get_parent();
        parent.remove(main_view);
        parent.add(form_view);
        this.show_all();
    }

    private void switch_to_main() {
        var parent = (Gtk.Box) form_view.get_parent();
        parent.remove(form_view);
        parent.add(main_view);
        this.show_all();
    }

    private void update_labels() {
        lbl_client.set_text("Client: " + timer_mgr.client);
        lbl_project.set_text("Project: " + timer_mgr.project);
        lbl_task.set_text("Task: " + timer_mgr.task);
        int h = timer_mgr.elapsed_seconds / 3600;
        int m = (timer_mgr.elapsed_seconds % 3600) / 60;
        string hour_str = hours == 1 ? "hour" : "hours";
        string minute_str = minutes == 1 ? "minute" : "minutes";
        lbl_duration.set_text("Duration: %d %s, %d %s".printf(h, hour_str, m, minute_str));
    }
}
