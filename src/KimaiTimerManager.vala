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

public class KimaiTimerManager : GLib.Object {
    private KimaiAPI api;

    public signal void updated();
    public signal void stopped();

    public KimaiTimesheet? active_timesheet { get; private set; }
    public int elapsed_seconds { get; private set; }
    private uint tick_id = 0;
    private uint refresh_interval_ms = 5 * 1000; // 5 seconds in milliseconds

    public string customer {
        get { return active_timesheet != null ? active_timesheet.project.customer.name : "-"; }
    }
    public string project {
        get { return active_timesheet != null ? active_timesheet.project.name : "-"; }
    }
    public string task {
        get { return active_timesheet != null ? active_timesheet.activity.name : "-"; }
    }
    public string description {
        get { return active_timesheet != null ? active_timesheet.description : "-"; }
    }

    public KimaiTimerManager(KimaiAPI api) {
        this.api = api;
        refresh_from_server();

        GLib.Timeout.add(refresh_interval_ms, () => {
            refresh_from_server();
            return true;
        });
    }

    public void set_api(KimaiAPI api) {
        this.api = api;
    }

    public void refresh_from_server() {
        try {
            var active = api.list_active_timesheets();
            if (active != null && active.length() > 0) {
                active_timesheet = active.nth_data(0);
                elapsed_seconds = (int)(new DateTime.now_utc().to_unix() - active_timesheet.begin.to_unix());
                start_tick();
            } else {
                clear_state();
            }
            updated();
        } catch (Error e) {
            warning("Failed to refresh timers: %s", e.message);
        }
    }

    public void start_timer(int project_id, int activity_id, string description) {
        try {
            active_timesheet = api.start_timer(project_id, activity_id, description);
            elapsed_seconds = (int)(new DateTime.now_utc().to_unix() - active_timesheet.begin.to_unix());
            start_tick();
            updated();
        } catch (Error e) {
            warning("Start failed: %s", e.message);
        }
    }

    public void stop_timer() {
        if (active_timesheet == null) return;
        try {
            api.stop_timer(active_timesheet.id);
            clear_state();
            stopped();
        } catch (Error e) {
            warning("Stop failed: %s", e.message);
        }
    }

    private void clear_state() {
        stop_tick();
        active_timesheet = null;
        elapsed_seconds = 0;
    }

    private void start_tick() {
        if (tick_id != 0) return;
        tick_id = Timeout.add_seconds(1, () => {
            elapsed_seconds++;
            updated();
            return true;
        });
    }

    private void stop_tick() {
        if (tick_id != 0) {
            Source.remove(tick_id);
            tick_id = 0;
        }
    }
}
