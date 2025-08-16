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
using Gdk;
using Gtk;
using Budgie;

// TODO: token storage
//  var schema = new Secret.Schema ("io.grnbk.kimaitimetracker",
//      Secret.SchemaFlags.NONE,
//      "api-token", Secret.SchemaAttributeType.STRING);

//  Secret.password_store_sync(schema, null, "Kimai API token",
//                             api_token, null,
//                             "api-token", "kimai", null);

//  var token = Secret.password_lookup_sync(schema, null,
//                                          "api-token", "kimai", null);

public class KimaiTimetrackerWindow : Budgie.Popover {
    private Gtk.Label label_customer_content;
    private Gtk.Label label_project_content;
    private Gtk.Label label_task_content;
    private Gtk.Label label_description_content;
    private Gtk.Label label_duration_content;

    private Gtk.Button button_start;
    private Gtk.Button button_stop;
    private Gtk.Button button_new_timer;
    private Gtk.Button button_settings;

    private Gtk.ComboBoxText combo_costumer;
    private Gtk.ComboBoxText combo_project;
    private Gtk.ComboBoxText combo_task;
    private Gtk.Entry entry_description;

    private Gtk.Box main_view;
    private Gtk.Box form_view;

    private Gtk.Box main_warning_box;
    private Gtk.Box form_warning_box;

    private KimaiAPI api;
    private KimaiTimerManager timer_manager;

    private unowned GLib.Settings? settings;

    public KimaiTimetrackerWindow(Gtk.Widget? c_parent, GLib.Settings? c_settings) {
        Object(relative_to: c_parent);
        settings = c_settings;
        get_style_context().add_class("kimaitimetracker-popover");

        api = new KimaiAPI("https://demo.kimai.org/api", "8e981f387f8d7a1931790cc26");
        timer_manager = new KimaiTimerManager(api);

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

        timer_manager.updated.connect(update_labels);
        timer_manager.stopped.connect(() => label_duration_content.set_text("-"));
        timer_manager.refresh_from_server();

        this.show_all();
    }

    private Gtk.Box build_warning_box() {
        var css_provider = new Gtk.CssProvider();
        css_provider.load_from_data(".warning { color: #f27835; }");

        Gtk.StyleContext.add_provider_for_screen(
            Gdk.Screen.get_default(),
            css_provider,
            Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
        );

        var box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6);
        box.set_halign(Gtk.Align.START);

        var icon = new Gtk.Image.from_icon_name("dialog-warning-symbolic", Gtk.IconSize.BUTTON);
        icon.get_style_context().add_class("warning");
        box.pack_start(icon, false, false, 0);

        var label = new Gtk.Label(null);
        label.set_halign(Gtk.Align.START);
        label.set_justify(Gtk.Justification.LEFT);
        box.pack_start(label, true, true, 0);

        box.hide();
        return box;
    }

    private Gtk.Label? get_warning_label(Gtk.Box warning_box) {
        var children = warning_box.get_children();
        if (children != null) {
            unowned GLib.List<weak Gtk.Widget> node = children;
            while (node.next != null) {
                node = node.next;
            }
            return node.data as Gtk.Label;
        }
        return null;
    }

    private Gtk.Box build_main_view() {
        var box = new Gtk.Box(Gtk.Orientation.VERTICAL, 6);

        main_warning_box = build_warning_box();
        box.pack_start(main_warning_box, false, false, 0);

        var label_customer = new Gtk.Label("Customer:");
        label_customer.set_halign(Gtk.Align.END);
        var label_project = new Gtk.Label("Project:");
        label_project.set_halign(Gtk.Align.END);
        var label_task = new Gtk.Label("Task:");
        label_task.set_halign(Gtk.Align.END);
        var label_duration = new Gtk.Label("Duration:");
        label_duration.set_halign(Gtk.Align.END);
        var label_description = new Gtk.Label("Description:");
        label_description.set_halign(Gtk.Align.END);

        label_customer_content = new Gtk.Label("-");
        label_customer_content.set_halign(Gtk.Align.START);
        label_project_content = new Gtk.Label("-");
        label_project_content.set_halign(Gtk.Align.START);
        label_task_content = new Gtk.Label("-");
        label_task_content.set_halign(Gtk.Align.START);
        label_description_content = new Gtk.Label("-");
        label_description_content.set_halign(Gtk.Align.START);
        label_duration_content = new Gtk.Label("-");
        label_duration_content.set_halign(Gtk.Align.START);

        var grid = new Gtk.Grid();
        grid.set_row_spacing(6);
        grid.set_column_spacing(6);
        grid.attach(label_customer, 0, 0, 1, 1);
        grid.attach(label_customer_content, 1, 0, 1, 1);
        grid.attach(label_project, 0, 1, 1, 1);
        grid.attach(label_project_content, 1, 1, 1, 1);
        grid.attach(label_task, 0, 2, 1, 1);
        grid.attach(label_task_content, 1, 2, 1, 1);
        grid.attach(label_description, 0, 3, 1, 1);
        grid.attach(label_description_content, 1, 3, 1, 1);
        grid.attach(label_duration, 0, 4, 1, 1);
        grid.attach(label_duration_content, 1, 4, 1, 1);
        box.add(grid);

        var hbox_buttons = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6);
        button_start = new Gtk.Button.with_label("▶ Start");
        button_stop  = new Gtk.Button.with_label("■ Stop");
        hbox_buttons.add(button_start);
        hbox_buttons.add(button_stop);
        box.add(hbox_buttons);

        var vbox_bottom = new Gtk.Box(Gtk.Orientation.VERTICAL, 6);
        button_new_timer = new Gtk.Button.with_label("+ New Timer");
        button_settings = new Gtk.Button.with_label("Settings");
        vbox_bottom.add(button_new_timer);
        vbox_bottom.add(button_settings);
        box.add(vbox_bottom);

        button_start.clicked.connect(() => {
            if (timer_manager.active_timesheet == null) switch_to_form();
            else timer_manager.refresh_from_server();
        });
        button_stop.clicked.connect(() => timer_manager.stop_timer());
        button_new_timer.clicked.connect(() => switch_to_form());

        return box;
    }

    private Gtk.Box build_form_view() {
        var box = new Gtk.Box(Gtk.Orientation.VERTICAL, 6);

        form_warning_box = build_warning_box();
        box.pack_start(form_warning_box, false, false, 0);

        var grid = new Gtk.Grid();
        grid.set_row_spacing(6);
        grid.set_column_spacing(6);

        var label_customer = new Gtk.Label("Customer:");
        label_customer.set_halign(Gtk.Align.END);
        var label_project = new Gtk.Label("Project:");
        label_project.set_halign(Gtk.Align.END);
        var label_task = new Gtk.Label("Task:");
        label_task.set_halign(Gtk.Align.END);
        var label_description = new Gtk.Label("Description:");
        label_description.set_halign(Gtk.Align.END);

        combo_costumer = new Gtk.ComboBoxText();
        combo_project = new Gtk.ComboBoxText();
        combo_task = new Gtk.ComboBoxText();
        entry_description = new Gtk.Entry();

        try {
            var customers = api.list_customers();
            foreach (var customer in customers) {
                combo_costumer.append(customer.id.to_string(), customer.name);
            }
        } catch (Error e) {
            show_warning("Could not fetch customers: %s".printf(e.message), true);
        }

        combo_costumer.changed.connect(() => {
            combo_project.remove_all();
            combo_task.remove_all();
            var sel = combo_costumer.get_active_id();
            if (sel != null) {
                int cid = int.parse(sel);
                try {
                    var projects = api.list_projects(cid);
                    foreach (var proj in projects) {
                        combo_project.append(proj.id.to_string(), proj.name);
                    }
                } catch (Error e) {
                    show_warning("Could not fetch projects: %s".printf(e.message), true);
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
                    show_warning("Could not fetch activities: %s".printf(e.message), true);
                }
            }
        });

        grid.attach(label_customer, 0, 0, 1, 1);
        grid.attach(combo_costumer, 1, 0, 1, 1);
        grid.attach(label_project, 0, 1, 1, 1);
        grid.attach(combo_project, 1, 1, 1, 1);
        grid.attach(label_task, 0, 2, 1, 1);
        grid.attach(combo_task, 1, 2, 1, 1);
        grid.attach(label_description, 0, 3, 1, 1);
        grid.attach(entry_description, 1, 3, 1, 1);
        box.add(grid);

        var vbox_bottom = new Gtk.Box(Gtk.Orientation.VERTICAL, 6);
        var button_start_new = new Gtk.Button.with_label("Start Timer");
        var button_back = new Gtk.Button.with_label("Back");
        vbox_bottom.add(button_start_new);
        vbox_bottom.add(button_back);
        box.add(vbox_bottom);

        button_back.clicked.connect(() => switch_to_main());
        button_start_new.clicked.connect(() => {
            var project_id_str = combo_project.get_active_id();
            var activity_id_str = combo_task.get_active_id();
            if (project_id_str == null || activity_id_str == null) return;

            var project_id = int.parse(project_id_str);
            var activity_id = int.parse(activity_id_str);
            var description = entry_description.get_text();

            timer_manager.start_timer(project_id, activity_id, description);
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
        label_customer_content.set_text(timer_manager.customer);
        label_project_content.set_text(timer_manager.project);
        label_task_content.set_text(timer_manager.task);
        label_description_content.set_text(timer_manager.description);
        int hours = timer_manager.elapsed_seconds / 3600;
        int minutes = (timer_manager.elapsed_seconds % 3600) / 60;
        string hour_str = hours == 1 ? "hour" : "hours";
        string minute_str = minutes == 1 ? "minute" : "minutes";
        label_duration_content.set_text("%d %s, %d %s".printf(hours, hour_str, minutes, minute_str));
    }

    private void show_warning(string message, bool in_form = false) {
        Gtk.Box box = in_form ? form_warning_box : main_warning_box;
        var label = get_warning_label(box);
        if (label != null) {
            label.set_text(message);
            label.get_style_context().add_class("warning");
            box.show();
        }
    }

    private void hide_warning(bool in_form = false) {
        Gtk.Box box = in_form ? form_warning_box : main_warning_box;
        box.hide();
    }
}
