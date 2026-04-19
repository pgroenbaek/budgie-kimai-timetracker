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
    public signal void show_warning(string message, bool persistent = false);
    public signal void hide_warning();

    public delegate void ResultList<T>(bool success, GLib.List<T>? items, string? error_message);

    public KimaiTimesheet? active_timesheet { get; private set; }
    public KimaiTimesheet? last_timesheet { get; private set; }
    public int elapsed_seconds { get; private set; }

    private uint tick_id = 0;
    private uint refresh_interval_ms = 5 * 1000;

    private unowned GLib.Settings? settings;

    public string customer {
        get {
            if (active_timesheet != null)
                return active_timesheet.project.customer.name;
            else if (last_timesheet != null)
                return last_timesheet.project.customer.name;
            return "N/A";
        }
    }

    public string project {
        get {
            if (active_timesheet != null)
                return active_timesheet.project.name;
            else if (last_timesheet != null)
                return last_timesheet.project.name;
            return "N/A";
        }
    }

    public string activity {
        get {
            if (active_timesheet != null)
                return active_timesheet.activity.name;
            else if (last_timesheet != null)
                return last_timesheet.activity.name;
            return "N/A";
        }
    }

    public string description {
        get {
            if (active_timesheet != null)
                return active_timesheet.description;
            else if (last_timesheet != null)
                return last_timesheet.description;
            return "N/A";
        }
    }

    public KimaiTimerManager(GLib.Settings? settings, string base_url, string api_token) {
        this.settings = settings;
        this.api = new KimaiAPI(base_url, api_token);

        refresh_from_server();

        Timeout.add(refresh_interval_ms, () => {
            refresh_from_server();
            return true;
        });
    }

    public void set_api_info(string base_url, string api_token) {
        settings?.set_string("kimai-api-baseurl", base_url);

        api = new KimaiAPI(base_url, api_token);

        api.validate_connection((valid, error_message) => {
            if (valid) {
                hide_warning();
            }
            else {
                show_warning(error_message, true);
            }
        });
    }

    public void refresh_from_server() {
        api.get_active_timesheets((success, timesheets, error) => {
            if (!success) {
                warning("Failed to refresh timers: %s", error);
                return;
            }

            if (timesheets != null && timesheets.length() > 0) {
                active_timesheet = timesheets.nth_data(0);

                elapsed_seconds =
                    (int)(new DateTime.now_utc().to_unix()
                    - active_timesheet.begin.to_unix());

                settings?.set_boolean("timetracker-running", true);

                start_tick();

            } else {
                clear_state();
            }

            updated();
        });
    }

    public void start_timer(int project_id, int activity_id, string description) {
        api.start_timer(project_id, activity_id, description, (success, timesheet, error) => {

            if (!success) {
                warning("Start failed: %s", error);
                return;
            }

            active_timesheet = timesheet;

            elapsed_seconds =
                (int)(new DateTime.now_utc().to_unix()
                - active_timesheet.begin.to_unix());

            settings?.set_boolean("timetracker-running", true);

            start_tick();
            updated();
        });
    }

    public void stop_timer() {
        if (active_timesheet == null)
            return;

        int id = active_timesheet.id;

        api.stop_timer(id, (success, timesheet, error) => {

            if (!success) {
                warning("Stop failed: %s", error);
                return;
            }

            clear_state();
        });
    }

    private void clear_state() {
        stop_tick();
        stopped();

        last_timesheet = active_timesheet;
        active_timesheet = null;

        elapsed_seconds = 0;

        settings?.set_boolean("timetracker-running", false);
        settings?.set_int("last-customer", last_timesheet?.project?.customer?.id ?? -1);
        settings?.set_int("last-project", last_timesheet?.project?.id ?? -1);
        settings?.set_int("last-activity", last_timesheet?.activity?.id ?? -1);
        settings?.set_string("last-description", last_timesheet?.description ?? "");
    }

    private void start_tick() {
        if (tick_id != 0) {
            return;
        }

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

    public void load_customers(owned ResultList<KimaiCustomer> result) {
        api.get_customers((success, customers, error) => {
            if (!success) {
                result(false, (GLib.List<KimaiCustomer>?) null, error);
                return;
            }
            result(true, customers, null);
        });
    }

    public void load_projects(int customer_id, owned ResultList<KimaiProject> result) {
        api.get_projects(customer_id, (success, projects, error) => {
            if (!success) {
                result(false, (GLib.List<KimaiProject>?) null, error);
                return;
            }
            result(true, projects, null);
        });
    }

    public void load_activities(int project_id, owned ResultList<KimaiActivity> result) {
        api.get_activities(project_id, (success, activities, error) => {
            if (!success) {
                result(false, (GLib.List<KimaiActivity>?) null, error);
                return;
            }
            result(true, activities, null);
        });
    }
}