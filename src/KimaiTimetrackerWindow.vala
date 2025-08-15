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

public class KimaiTimetrackerWindow : Budgie.Popover {
    private unowned Settings? settings;

    private Gtk.Label lbl_client;
    private Gtk.Label lbl_project;
    private Gtk.Label lbl_task;
    private Gtk.Label lbl_duration;

    private Gtk.Button btn_start;
    private Gtk.Button btn_stop;
    private Gtk.Button btn_new_timer;

    private uint timer_id = 0;
    private int elapsed_seconds = 0;

    public KimaiTimetrackerWindow(Gtk.Widget? parent, Settings? c_settings) {
        Object(relative_to: parent);
        settings = c_settings;

        var vbox = new Gtk.Box(Orientation.VERTICAL, 6);
        vbox.set_margin_top(6);
        vbox.set_margin_bottom(6);
        vbox.set_margin_start(6);
        vbox.set_margin_end(6);
        add(vbox);

        lbl_client = new Gtk.Label("Client: -"); vbox.add(lbl_client);
        lbl_project = new Gtk.Label("Project: -"); vbox.add(lbl_project);
        lbl_task = new Gtk.Label("Task: -"); vbox.add(lbl_task);
        lbl_duration = new Gtk.Label("Duration: 00:00:00"); vbox.add(lbl_duration);

        var hbox_buttons = new Gtk.Box(Orientation.HORIZONTAL, 6);
        btn_start = new Gtk.Button.with_label("▶ Start"); hbox_buttons.add(btn_start);
        btn_stop  = new Gtk.Button.with_label("■ Stop"); hbox_buttons.add(btn_stop);
        vbox.add(hbox_buttons);

        btn_new_timer = new Gtk.Button.with_label("+ New Timer"); vbox.add(btn_new_timer);

        btn_start.clicked.connect(() => start_timer());
        btn_stop.clicked.connect(() => stop_timer());
        btn_new_timer.clicked.connect(() => show_new_timer_dialog());

        this.show_all();
    }

    private void start_timer() {
        if (timer_id == 0) {
            timer_id = GLib.Timeout.add_seconds(1, () => {
                elapsed_seconds++;
                int h = elapsed_seconds / 3600;
                int m = (elapsed_seconds % 3600) / 60;
                int s = elapsed_seconds % 60;
                lbl_duration.text = "Duration: %02d:%02d:%02d".printf(h, m, s);
                return true;
            });
        }
    }

    private void stop_timer() {
        if (timer_id != 0) {
            GLib.Source.remove(timer_id);
            timer_id = 0;
        }
    }

    private void show_new_timer_dialog() {
        var dialog = new Gtk.Dialog("New Timer", this, Gtk.DialogFlags.MODAL);
        var content = dialog.get_content_area();
        var grid = new Gtk.Grid();
        grid.set_row_spacing(6);
        grid.set_column_spacing(6);
        content.add(grid);

        var lbl_client = new Gtk.Label("Client:"); var combo_client = new Gtk.ComboBoxText(); combo_client.append_text("ACME Corp"); combo_client.append_text("Globex Inc");
        var lbl_project = new Gtk.Label("Project:"); var combo_project = new Gtk.ComboBoxText(); combo_project.append_text("Website Redesign"); combo_project.append_text("Mobile App");
        var lbl_task = new Gtk.Label("Task:"); var combo_task = new Gtk.ComboBoxText(); combo_task.append_text("Coding Applet"); combo_task.append_text("Design UI");
        var lbl_desc = new Gtk.Label("Description:"); var entry_desc = new Gtk.Entry();

        grid.attach(lbl_client, 0, 0, 1, 1); grid.attach(combo_client, 1, 0, 1, 1);
        grid.attach(lbl_project, 0, 1, 1, 1); grid.attach(combo_project, 1, 1, 1, 1);
        grid.attach(lbl_task, 0, 2, 1, 1); grid.attach(combo_task, 1, 2, 1, 1);
        grid.attach(lbl_desc, 0, 3, 1, 1); grid.attach(entry_desc, 1, 3, 1, 1);

        dialog.add_button("Start Timer", Gtk.ResponseType.OK);
        dialog.add_button("Cancel", Gtk.ResponseType.CANCEL);

        dialog.show_all();
        if (dialog.run() == Gtk.ResponseType.OK) {
            lbl_client.text = "Client: " + combo_client.get_active_text();
            lbl_project.text = "Project: " + combo_project.get_active_text();
            lbl_task.text = "Task: " + combo_task.get_active_text();
            elapsed_seconds = 0;
            lbl_duration.text = "Duration: 00:00:00";
            start_timer();
        }
        dialog.destroy();
    }
}