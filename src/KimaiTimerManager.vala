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

    public signal void reconfigured();
    public signal void updated();
    public signal void stopped();
    public signal void show_warning(string message, bool persistent = false);
    public signal void hide_warning();

    public delegate void ResultList<T>(bool success, GLib.List<T>? items, string? error_message);

    public KimaiTimesheet? active_timesheet { get; private set; }
    public KimaiCustomer? active_customer { get; private set; }
    public KimaiProject? active_project { get; private set; }
    public KimaiActivity? active_activity { get; private set; }

    public KimaiTimesheet? last_timesheet { get; private set; }
    public KimaiCustomer? last_customer { get; private set; }
    public KimaiProject? last_project { get; private set; }
    public KimaiActivity? last_activity { get; private set; }

    private GLib.HashTable<int, KimaiCustomer> customers_table =
        new GLib.HashTable<int, KimaiCustomer>(GLib.direct_hash, GLib.direct_equal);
    private GLib.HashTable<int, KimaiProject> projects_table =
        new GLib.HashTable<int, KimaiProject>(GLib.direct_hash, GLib.direct_equal);
    private GLib.HashTable<int, KimaiActivity> activities_table =
        new GLib.HashTable<int, KimaiActivity>(GLib.direct_hash, GLib.direct_equal);

    public int elapsed_seconds { get; private set; }

    private uint tick_id = 0;
    private uint refresh_interval = 5 * 1000;

    private unowned GLib.Settings? settings;

    public string customer {
        get {
            if (active_customer != null)
                return active_customer.name;
            else if (last_customer != null)
                return last_customer.name;
            return "N/A";
        }
    }

    public string project {
        get {
            if (active_project != null)
                return active_project.name;
            else if (last_project != null)
                return last_project.name;
            return "N/A";
        }
    }

    public string activity {
        get {
            if (active_activity != null)
                return active_activity.name;
            else if (last_activity != null)
                return last_activity.name;
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

        Timeout.add(refresh_interval, () => {
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
                reconfigured();
            }
            else {
                show_warning(error_message, true);
            }
        });
    }

    public void refresh_from_server() {
        if (!api.is_connection_valid()) {
            api.validate_connection((valid, error_message) => {
                if (valid) {
                    hide_warning();
                    reconfigured();
                }
                else {
                    show_warning(error_message, true);
                }
            });
            return;
        }

        api.get_active_timesheets((success, timesheets, error) => {
            if (!success) {
                warning("Failed to refresh timers: %s", error);
                return;
            }

            if (timesheets != null && timesheets.length() > 0) {
                active_timesheet = timesheets.nth_data(0);

                if (active_timesheet != null) {
                    populate_active_project_info((int?) null, active_timesheet.projectId);
                    populate_active_activity_info(active_timesheet.projectId, active_timesheet.activityId);

                    elapsed_seconds = (int)(new DateTime.now_utc().to_unix() - active_timesheet.begin.to_unix());

                    settings?.set_boolean("timetracker-running", true);

                    start_tick();
                }
            }
            else {
                clear_state();
            }

            updated();
        });
    }

    public void start_timer(int customer_id, int project_id, int activity_id, string description) {
        if (!api.is_connection_valid()) {
            return;
        }

        api.start_timer(project_id, activity_id, description, (success, timesheet, error) => {
            if (!success) {
                warning("Start failed: %s", error);
                return;
            }

            active_timesheet = timesheet;
            
            populate_active_project_info(customer_id, project_id);
            populate_active_activity_info(project_id, activity_id);

            var now = new DateTime.now_utc().to_unix();
            elapsed_seconds = (int) (now - active_timesheet.begin.to_unix());

            settings?.set_boolean("timetracker-running", true);

            start_tick();
            updated();
        });
    }

    public void stop_timer() {
        if (active_timesheet == null) {
            return;
        }

        int id = active_timesheet.id;

        if (!api.is_connection_valid()) {
            return;
        }

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

        if (active_timesheet != null) {
            last_timesheet = active_timesheet;
            last_customer = active_customer;
            last_project = active_project;
            last_activity = active_activity;

            settings?.set_int("last-customer", last_customer?.id ?? -1);
            settings?.set_int("last-project", last_project?.id ?? -1);
            settings?.set_int("last-activity", last_activity?.id ?? -1);
            settings?.set_string("last-description", last_timesheet?.description ?? "");
        }

        active_timesheet = null;
        active_customer = null;
        active_project = null;
        active_activity = null;

        elapsed_seconds = 0;

        settings?.set_boolean("timetracker-running", false);

        updated();
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

    private void populate_active_project_info(int? customer_id, int project_id)  {
        if (projects_table.contains(project_id)) {
            active_project = projects_table.lookup(project_id);
            populate_active_customer_info(active_project.customerId);
        }
        else {
            load_projects(customer_id, (success, projects, error) => {
                if (!success) {
                    show_warning("Could not fetch projects: %s".printf(error));
                    return;
                }
                if (projects_table.contains(project_id)) {
                    active_project = projects_table.lookup(project_id);
                    populate_active_customer_info(active_project.customerId);
                }
            });
        }
    }

    private void populate_active_activity_info(int project_id, int activity_id)  {
        if (activities_table.contains(activity_id)) {
            active_activity = activities_table.lookup(activity_id);
        }
        else
        {
            load_activities(project_id, (success, activities, error) => {
                if (!success) {
                    show_warning("Could not fetch projects: %s".printf(error));
                    return;
                }
                if (activities_table.contains(activity_id)) {
                    active_activity = activities_table.lookup(activity_id);
                }
            });
        }
    }

    private void populate_active_customer_info(int customer_id)  {
        if (customers_table.contains(customer_id)) {
            active_customer = customers_table.lookup(customer_id);
        }
        else {
            load_customers((success, customers, error) => {
                if (!success) {
                    show_warning("Could not fetch customers: %s".printf(error));
                    return;
                }
                if (customers_table.contains(customer_id)) {
                    active_customer = customers_table.lookup(customer_id);
                }
            });
        }
    }

    public void load_customers(owned ResultList<KimaiCustomer> result) {
        if (!api.is_connection_valid()) {
            return;
        }

        api.get_customers((success, customers, error) => {
            if (!success) {
                result(false, (GLib.List<KimaiCustomer>?) null, error);
                return;
            }
            customers_table.remove_all();
            foreach (var customer in customers) {
                customers_table.insert(customer.id, customer);
            }
            result(true, customers, null);
        });
    }

    public void load_projects(int? customer_id, owned ResultList<KimaiProject> result) {
        if (!api.is_connection_valid()) {
            return;
        }

        api.get_projects(customer_id, (success, projects, error) => {
            if (!success) {
                result(false, (GLib.List<KimaiProject>?) null, error);
                return;
            }
            projects_table.remove_all();
            foreach (var project in projects) {
                projects_table.insert(project.id, project);
            }
            result(true, projects, null);
        });
    }

    public void load_activities(int project_id, owned ResultList<KimaiActivity> result) {
        if (!api.is_connection_valid()) {
            return;
        }

        api.get_activities(project_id, (success, activities, error) => {
            if (!success) {
                result(false, (GLib.List<KimaiActivity>?) null, error);
                return;
            }
            activities_table.remove_all();
            foreach (var activity in activities) {
                activities_table.insert(activity.id, activity);
            }
            result(true, activities, null);
        });
    }
}