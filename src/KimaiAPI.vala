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

using Soup;
using Json;
using GLib;

public class KimaiAPI : GLib.Object {

    private Soup.Session session;
    private string base_url;
    private string auth_header;
    private bool connection_valid = false;

    private delegate void RequestCallback(Soup.Session session, Soup.Message msg);

    public delegate void ValidationCallback(bool valid, string? error);
    public delegate void CustomersCallback(bool success, List<KimaiCustomer>? customers, string? error);
    public delegate void ProjectsCallback(bool success, List<KimaiProject>? projects, string? error);
    public delegate void ActivitiesCallback(bool success, List<KimaiActivity>? activities, string? error);
    public delegate void TimesheetsCallback(bool success, List<KimaiTimesheet>? timesheets, string? error);
    public delegate void CustomerCallback(bool success, KimaiCustomer? customer, string? error);
    public delegate void ProjectCallback(bool success, KimaiProject? project, string? error);
    public delegate void ActivityCallback(bool success, KimaiActivity? activity, string? error);
    public delegate void TimesheetCallback(bool success, KimaiTimesheet? timesheet, string? error);

    public KimaiAPI(string base_url, string api_token) {
        if (base_url.has_suffix("/")) {
            this.base_url = base_url.substring(0, base_url.length - 1);
        }
        else {
            this.base_url = base_url;
        }

        session = new Soup.Session();
        auth_header = "Bearer " + api_token;
    }

    private void request(string method, string endpoint, string? body, owned RequestCallback callback) {
        var message = new Soup.Message(method, base_url + endpoint);
        message.request_headers.append("Authorization", auth_header);

        if (body != null) {
            message.request_headers.append("Content-Type", "application/json");
            message.set_request("application/json", Soup.MemoryUse.COPY, (uint8[]) body.data);
        }

        session.queue_message(message, (session, response) => {
            callback(session, response);
        });
    }

    private string get_json(Soup.Message message) {
        Soup.Buffer buffer = message.response_body.flatten();
        return (string) buffer.data;
    }

    public bool is_connection_valid() {
        return connection_valid;
    }

    public void validate_connection(owned ValidationCallback callback) {
        if (base_url == "") {
            connection_valid = false;
            callback(false, "Base URL not set.");
            return;
        }

        try {
            GLib.Uri.parse(base_url, GLib.UriFlags.NONE);
        } catch (Error e) {
            connection_valid = false;
            callback(false, "Invalid base URL.");
            return;
        }

        if (!base_url.has_prefix("https://")) {
            connection_valid = false;
            callback(false, "Base URL must start with https://");
            return;
        }

        if (!base_url.has_suffix("/api")) {
            connection_valid = false;
            callback(false, "Base URL must end with /api");
            return;
        }

        request("GET", "/customers", null, (session, message) => {
            if (message.status_code == Soup.Status.UNAUTHORIZED) {
                connection_valid = false;
                callback(false, "Invalid API token.");
                return;
            }

            if (message.status_code == Soup.Status.OK) {
                connection_valid = true;
                callback(true, null);
                return;
            }

            connection_valid = false;

            callback(false, "API validation failed: %d %s".printf(
                (int) message.status_code,
                message.reason_phrase
            ));
        });
    }

    private KimaiCustomer parse_customer(Json.Object obj) {
        return new KimaiCustomer() {
            id = (int) obj.get_int_member("id"),
            name = obj.get_string_member("name")
        };
    }

    private KimaiProject parse_project(Json.Object obj) {
        return new KimaiProject() {
            id = (int) obj.get_int_member("id"),
            name = obj.get_string_member("name")
        };
    }

    private KimaiActivity parse_activity(Json.Object obj) {
        return new KimaiActivity() {
            id = (int) obj.get_int_member("id"),
            name = obj.get_string_member("name")
        };
    }

    private KimaiTimesheet parse_timesheet(Json.Object obj) {
        var t = new KimaiTimesheet();

        t.id = (int) obj.get_int_member("id");
        t.description = obj.get_string_member("description");
        t.begin = new DateTime.from_iso8601(obj.get_string_member("begin"), null);

        if (obj.has_member("end")) {
            var end = obj.get_string_member("end");
            if (end != null && end != "")
                t.end = new DateTime.from_iso8601(end, null);
        }

        if (obj.has_member("project"))
            t.project = parse_project(obj.get_object_member("project"));

        if (obj.has_member("activity"))
            t.activity = parse_activity(obj.get_object_member("activity"));

        return t;
    }

    public void get_customers(owned CustomersCallback callback) {
        request("GET", "/customers", null, (session, message) => {

            if (message.status_code != Soup.Status.OK) {
                callback(false, null, message.reason_phrase);
                return;
            }

            try {

                var parser = new Json.Parser();
                parser.load_from_data(get_json(message), -1);

                var arr = parser.get_root().get_array();

                var list = new List<KimaiCustomer>();

                for (uint i = 0; i < arr.get_length(); i++)
                    list.append(parse_customer(arr.get_element(i).get_object()));

                callback(true, list, null);

            } catch (Error e) {
                callback(false, null, e.message);
            }
        });
    }

    public void get_projects(int? customer_id, owned ProjectsCallback callback) {
        string endpoint = "/projects";

        if (customer_id != null)
            endpoint += "?customer=" + customer_id.to_string();

        request("GET", endpoint, null, (session, message) => {

            if (message.status_code != Soup.Status.OK) {
                callback(false, null, message.reason_phrase);
                return;
            }

            try {

                var parser = new Json.Parser();
                parser.load_from_data(get_json(message), -1);

                var arr = parser.get_root().get_array();

                var list = new List<KimaiProject>();

                for (uint i = 0; i < arr.get_length(); i++)
                    list.append(parse_project(arr.get_element(i).get_object()));

                callback(true, list, null);

            } catch (Error e) {
                callback(false, null, e.message);
            }
        });
    }

    public void get_activities(int? project_id, owned ActivitiesCallback callback) {
        string endpoint = "/activities";

        if (project_id != null)
            endpoint += "?project=" + project_id.to_string();

        request("GET", endpoint, null, (session, message) => {

            if (message.status_code != Soup.Status.OK) {
                callback(false, null, message.reason_phrase);
                return;
            }

            try {

                var parser = new Json.Parser();
                parser.load_from_data(get_json(message), -1);

                var arr = parser.get_root().get_array();

                var list = new List<KimaiActivity>();

                for (uint i = 0; i < arr.get_length(); i++)
                    list.append(parse_activity(arr.get_element(i).get_object()));

                callback(true, list, null);

            } catch (Error e) {
                callback(false, null, e.message);
            }
        });
    }

    public void get_active_timesheets(owned TimesheetsCallback callback) {
        request("GET", "/timesheets/active", null, (session, message) => {

            if (message.status_code != Soup.Status.OK) {
                callback(false, null, message.reason_phrase);
                return;
            }

            try {

                var parser = new Json.Parser();
                parser.load_from_data(get_json(message), -1);

                var arr = parser.get_root().get_array();

                var list = new List<KimaiTimesheet>();

                for (uint i = 0; i < arr.get_length(); i++)
                    list.append(parse_timesheet(arr.get_element(i).get_object()));

                callback(true, list, null);

            } catch (Error e) {
                callback(false, null, e.message);
            }
        });
    }

    public void start_timer(int project_id, int activity_id, string description, owned TimesheetCallback callback) {

        string json_body = "{ \"project\": %d, \"activity\": %d, \"description\": \"%s\" }"
            .printf(project_id, activity_id, description);

        request("POST", "/timesheets", json_body, (session, message) => {

            if (message.status_code != Soup.Status.OK &&
                message.status_code != Soup.Status.CREATED)
            {
                callback(false, null, message.reason_phrase);
                return;
            }

            try {

                var parser = new Json.Parser();
                parser.load_from_data(get_json(message), -1);

                var obj = parser.get_root().get_object();

                callback(true, parse_timesheet(obj), null);

            } catch (Error e) {
                callback(false, null, e.message);
            }
        });
    }

    public void stop_timer(int timesheet_id, owned TimesheetCallback callback) {
        var now = new DateTime.now_local();
        string timestamp = now.format("%Y-%m-%dT%H:%M:%S");

        string json_body = "{ \"end\": \"%s\" }".printf(timestamp);

        request("PATCH", "/timesheets/%d".printf(timesheet_id), json_body, (session, message) => {

            if (message.status_code != Soup.Status.OK) {
                callback(false, null, message.reason_phrase);
                return;
            }

            try {

                var parser = new Json.Parser();
                parser.load_from_data(get_json(message), -1);

                var obj = parser.get_root().get_object();

                callback(true, parse_timesheet(obj), null);

            } catch (Error e) {
                callback(false, null, e.message);
            }
        });
    }
}
