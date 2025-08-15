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

public class KimaiTimerManager : Object {
    private KimaiAPI api;
    private uint poll_id = 0;
    private uint timer_id = 0;
    private int elapsed_seconds = 0;
    private int current_timesheet_id = -1;

    public string client { get; private set; } = "-";
    public string project { get; private set; } = "-";
    public string task { get; private set; } = "-";

    public signal void updated();
    public signal void stopped();

    public KimaiTimerManager(KimaiAPI api_instance) {
        api = api_instance;
        start_polling();
    }

    private void start_polling() {
        poll_id = GLib.Timeout.add_seconds(5, () => {
            try {
                sync_with_api();
            } catch (Error e) {
                warning("Failed to sync with Kimai: %s", e.message);
            }
            return true; // continue polling
        });
    }

    private void sync_with_api() throws Error {
        var active_timesheets = api.list_active_timesheets();
        if (active_timesheets.get_length() > 0) {
            var ts = active_timesheets.get_element(0).get_object();
            current_timesheet_id = ts["id"].get_int();
            client = ts["project"]["customer"]["name"].get_string();
            project = ts["project"]["name"].get_string();
            task = ts["activity"]["name"].get_string();
            elapsed_seconds = ts["duration"].get_int();

            start_local_timer();
            updated.emit();
        } else {
            stop_local_timer();
            stopped.emit();
        }
    }

    private void start_local_timer() {
        if (timer_id == 0) {
            timer_id = GLib.Timeout.add_seconds(1, () => {
                elapsed_seconds++;
                updated.emit();
                return true;
            });
        }
    }

    private void stop_local_timer() {
        if (timer_id != 0) {
            GLib.Source.remove(timer_id);
            timer_id = 0;
        }
        current_timesheet_id = -1;
    }

    public void start_timer(int project_id, int activity_id, string description) {
        try {
            var ts = api.start_timer(project_id, activity_id, description);
            current_timesheet_id = ts["id"].get_int();
            client = ts["project"]["customer"]["name"].get_string();
            project = ts["project"]["name"].get_string();
            task = ts["activity"]["name"].get_string();
            elapsed_seconds = 0;
            start_local_timer();
            updated.emit();
        } catch (Error e) {
            warning("Failed to start timer: %s", e.message);
        }
    }

    public void stop_timer() {
        if (current_timesheet_id != -1) {
            try {
                api.stop_timer(current_timesheet_id);
            } catch (Error e) {
                warning("Failed to stop timer: %s", e.message);
            }
        }
        stop_local_timer();
        stopped.emit();
    }
}