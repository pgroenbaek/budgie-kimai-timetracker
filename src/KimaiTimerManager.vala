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

    public signal void disconnected();
    public signal void connected();
    public signal void updated();
    public signal void stopped();

    public KimaiTimesheet? active_timesheet { get; private set; }
    public KimaiTimesheet? last_timesheet { get; private set; }
    public int elapsed_seconds { get; private set; }

    private uint tick_id = 0;
    private uint refresh_interval_ms = 5 * 1000; // 5 seconds in milliseconds
    private bool was_connected = true;

    private unowned GLib.Settings? settings;

    public string customer {
        get { 
            if (active_timesheet != null) {
                return active_timesheet.project.customer.name;
            }
            else if (last_timesheet != null) {
                return last_timesheet.project.customer.name;
            }
            return "N/A";
        }
    }

    public string project {
        get { 
            if (active_timesheet != null) {
                return active_timesheet.project.name;
            }
            else if (last_timesheet != null) {
                return last_timesheet.project.name;
            }
            return "N/A";
        }
    }

    public string activity {
        get { 
            if (active_timesheet != null) {
                return active_timesheet.activity.name;
            }
            else if (last_timesheet != null) {
                return last_timesheet.activity.name;
            }
            return "N/A";
        }
    }

    public string description {
        get { 
            if (active_timesheet != null) {
                return active_timesheet.description;
            }
            else if (last_timesheet != null) {
                return last_timesheet.description;
            }
            return "N/A";
        }
    }

    public KimaiTimerManager(KimaiAPI api, GLib.Settings? c_settings) {
        this.api = api;
        this.settings = c_settings;
        refresh_from_server();

        GLib.Timeout.add(refresh_interval_ms, () => {
            refresh_from_server();
            return true;
        });
    }

    public void set_api(KimaiAPI api) {
        this.api = api;
        refresh_from_server();
    }

    public void refresh_from_server() {
        api.get_active_timesheets.begin((obj, res) => {
            try {
                var active = api.get_active_timesheets.end(res);

                if (active != null && active.length() > 0) {
                    active_timesheet = active.nth_data(0);
                    elapsed_seconds = (int)(new DateTime.now_utc().to_unix() - active_timesheet.begin.to_unix());

                    settings.set_boolean("timetracker-running", true);

                    start_tick();
                } else {
                    clear_state();
                }

                updated();

                if (!was_connected) {
                    connected();
                    was_connected = true;
                }
            } catch (Error e) {
                if (e.domain == GLib.IOError.quark() ||
                    e.domain == GLib.ResolverError.quark()) {
                    warning("No internet connection: %s", e.message);
                    if (was_connected) {
                        disconnected();
                        was_connected = false;
                    }
                } else {
                    warning("Failed to refresh timers: %s", e.message);
                }
            }
        });
    }

    public void start_timer(int project_id, int activity_id, string description) {
        api.start_timer.begin(project_id, activity_id, description, (obj, res) => {
            try {
                active_timesheet = api.start_timer.end(res);
                elapsed_seconds = (int)(new DateTime.now_utc().to_unix() - active_timesheet.begin.to_unix());

                settings.set_boolean("timetracker-running", true);

                start_tick();
                updated();
            } catch (Error e) {
                warning("Start failed: %s", e.message);
            }
        });
    }

    public void stop_timer() {
        if (active_timesheet == null) {
            return;
        }

        api.stop_timer.begin(active_timesheet.id, (obj, res) => {
            try {
                api.stop_timer.end(res);
                clear_state();
            } catch (Error e) {
                warning("Stop failed: %s", e.message);
            }
        });
    }

    private void clear_state() {
        stop_tick();
        stopped();
        last_timesheet = active_timesheet;
        elapsed_seconds = 0;

        settings.set_boolean("timetracker-running", false);
        settings.set_int("last-customer", last_timesheet?.project?.customer?.id ?? -1);
        settings.set_int("last-project", last_timesheet?.project?.id ?? -1);
        settings.set_int("last-activity", last_timesheet?.activity?.id ?? -1);
        settings.set_string("last-description", last_timesheet?.description ?? "");
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
