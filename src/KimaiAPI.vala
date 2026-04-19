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
    private string api_token;
    private bool connection_valid = false;

    private delegate void ResponseHandler(Soup.Session session, Soup.Message msg);

    public delegate void ValidationResult(bool success, string? error_message);
    public delegate void Result<T>(bool success, T? item, string? error_message);
    public delegate void ResultList<T>(bool success, GLib.List<T>? items, string? error_message);

    public KimaiAPI(string base_url, string api_token) {
        if (base_url.has_suffix("/")) {
            this.base_url = base_url.substring(0, base_url.length - 1);
        }
        else {
            this.base_url = base_url;
        }

        this.session = new Soup.Session();
        this.api_token = api_token;
    }

    private void request(string method, string endpoint, string? body, owned ResponseHandler handler) {
        var message = new Soup.Message(method, base_url + endpoint);
        message.request_headers.append("Authorization", "Bearer " + api_token);

        if (body != null) {
            message.request_headers.append("Content-Type", "application/json");
            message.set_request("application/json", Soup.MemoryUse.COPY, (uint8[]) body.data);
        }

        session.queue_message(message, (session, response) => {
            handler(session, response);
        });
    }

    private string get_json(Soup.Message message) {
        Soup.Buffer buffer = message.response_body.flatten();
        return (string) buffer.data;
    }

    public bool is_connection_valid() {
        return connection_valid;
    }

    public void validate_connection(owned ValidationResult result) {
        if (base_url == "") {
            connection_valid = false;
            result(false, "Base URL not set.");
            return;
        }

        if (api_token == "") {
            connection_valid = false;
            result(false, "API key not set.");
            return;
        }

        try {
            GLib.Uri.parse(base_url, GLib.UriFlags.NONE);
        } catch (GLib.Error e) {
            connection_valid = false;
            result(false, "Invalid base URL: Not an URL.");
            return;
        }

        if (!base_url.has_prefix("https://")) {
            connection_valid = false;
            result(false, "Invalid base URL: Must start with 'https://'.");
            return;
        }

        if (!base_url.has_suffix("/api")) {
            connection_valid = false;
            result(false, "Invalid base URL: Must end with '/api'.");
            return;
        }

        request("GET", "/customers", null, (session, message) => {
            if (message.status_code == Soup.Status.CANT_RESOLVE ||
                message.status_code == Soup.Status.CANT_CONNECT ||
                message.status_code == Soup.Status.SSL_FAILED ||
                message.status_code == Soup.Status.IO_ERROR)
            {
                connection_valid = false;
                result(false, "Network error: Cannot reach server.");
                return;
            }

            if (message.status_code == Soup.Status.UNAUTHORIZED) {
                connection_valid = false;
                result(false, "Invalid API token.");
                return;
            }

            if (message.status_code == Soup.Status.OK) {
                connection_valid = true;
                result(true, null);
                return;
            }

            connection_valid = false;

            result(false, "API validation failed: %d %s".printf(
                (int) message.status_code,
                message.reason_phrase
            ));
        });
    }

    /*
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
    }*/

    /*private KimaiCustomer parse_customer_object(Json.Object obj) {
        return new KimaiCustomer() {
            id = (int) obj.get_int_member("id"),
            name = obj.get_string_member("name")
        };
    }

    private KimaiProject parse_project_object(Json.Object obj) {
        var project = new KimaiProject() {
            id = (int) obj.get_int_member("id"),
            name = obj.get_string_member("name")
        };

        if (obj.has_member("customer")) {
            var customer_node = obj.get_member("customer");

            if (customer_node.get_node_type() == Json.NodeType.OBJECT) {
                project.customer = parse_customer_object(obj.get_object_member("customer"));
            } else {
                project.customer = get_customer((int) obj.get_int_member("customer"));
            }
        }

        return project;
    }

    private KimaiActivity parse_activity_object(Json.Object obj) {
        return new KimaiActivity() {
            id = (int) obj.get_int_member("id"),
            name = obj.get_string_member("name")
        };
    }

    private KimaiTimesheet parse_timesheet_object(Json.Object obj) {
        var timesheet = new KimaiTimesheet();

        timesheet.id = (int) obj.get_int_member("id");
        timesheet.description = obj.get_string_member("description");
        timesheet.begin = new DateTime.from_iso8601(obj.get_string_member("begin"), null);

        if (obj.has_member("end")) {
            var end_str = obj.get_string_member("end");
            if (end_str != null && end_str.length > 0) {
                timesheet.end = new DateTime.from_iso8601(end_str, null);
            }
        }

        if (obj.has_member("project")) {
            var project_node = obj.get_member("project");

            if (project_node.get_node_type() == Json.NodeType.OBJECT) {
                timesheet.project = parse_project_object(obj.get_object_member("project"));
            } else {
                timesheet.project = get_project((int) obj.get_int_member("project"));
            }
        }

        if (obj.has_member("activity")) {
            var activity_node = obj.get_member("activity");

            if (activity_node.get_node_type() == Json.NodeType.OBJECT) {
                timesheet.activity = parse_activity_object(obj.get_object_member("activity"));
            } else {
                timesheet.activity = get_activity((int) obj.get_int_member("activity"));
            }
        }

        return timesheet;
    }

    private List<KimaiCustomer> parse_customers_array(Json.Array arr) {
        var result = new List<KimaiCustomer>();

        for (uint i = 0; i < arr.get_length(); i++) {
            result.append(parse_customer_object(arr.get_element(i).get_object()));
        }

        return result;
    }

    private List<KimaiProject> parse_projects_array(Json.Array arr) {
        var result = new List<KimaiProject>();

        for (uint i = 0; i < arr.get_length(); i++) {
            result.append(parse_project_object(arr.get_element(i).get_object()));
        }

        return result;
    }

    private List<KimaiActivity> parse_activities_array(Json.Array arr) {
        var result = new List<KimaiActivity>();

        for (uint i = 0; i < arr.get_length(); i++) {
            result.append(parse_activity_object(arr.get_element(i).get_object()));
        }

        return result;
    }

    private List<KimaiTimesheet> parse_timesheets_array(Json.Array arr) {
        var result = new List<KimaiTimesheet>();

        for (uint i = 0; i < arr.get_length(); i++) {
            result.append(parse_timesheet_object(arr.get_element(i).get_object()));
        }

        return result;
    }*/

    private KimaiCustomer parse_customer_object(Json.Object obj) {
        var c = new KimaiCustomer();
        c.id = (int) obj.get_int_member("id");
        c.name = obj.get_string_member("name");
        return c;
    }

    private KimaiProject parse_project_object(Json.Object obj) {
        var p = new KimaiProject();
        p.id = (int) obj.get_int_member("id");
        p.name = obj.get_string_member("name");

        if (obj.has_member("customer")) {
            var node = obj.get_member("customer");

            if (node.get_node_type() == Json.NodeType.VALUE) {
                p.customerId = (int) obj.get_int_member("customer");
            } else {
                var c = obj.get_object_member("customer");
                p.customerId = (int) c.get_int_member("id");
            }
        }

        return p;
    }

    private KimaiActivity parse_activity_object(Json.Object obj) {
        var a = new KimaiActivity();
        a.id = (int) obj.get_int_member("id");
        a.name = obj.get_string_member("name");
        return a;
    }

    private KimaiTimesheet parse_timesheet_object(Json.Object obj) {
        var t = new KimaiTimesheet();

        t.id = (int) obj.get_int_member("id");
        t.description = obj.get_string_member("description");
        t.begin = new DateTime.from_iso8601(obj.get_string_member("begin"), null);

        if (obj.has_member("end")) {
            var end_str = obj.get_string_member("end");
            if (end_str != null && end_str.length > 0) {
                t.end = new DateTime.from_iso8601(end_str, null);
            }
        }

        if (obj.has_member("project")) {
            var node = obj.get_member("project");

            if (node.get_node_type() == Json.NodeType.VALUE) {
                t.projectId = (int) obj.get_int_member("project");
            } else {
                var p = obj.get_object_member("project");
                t.projectId = (int) p.get_int_member("id");
            }
        }

        if (obj.has_member("activity")) {
            var node = obj.get_member("activity");

            if (node.get_node_type() == Json.NodeType.VALUE) {
                t.activityId = (int) obj.get_int_member("activity");
            } else {
                var a = obj.get_object_member("activity");
                t.activityId = (int) a.get_int_member("id");
            }
        }

        return t;
    }

    public void get_customers(owned ResultList<KimaiCustomer> result) {
        request("GET", "/customers", null, (session, message) => {
            if (message.status_code == Soup.Status.CANT_RESOLVE ||
                message.status_code == Soup.Status.CANT_CONNECT ||
                message.status_code == Soup.Status.SSL_FAILED ||
                message.status_code == Soup.Status.IO_ERROR)
            {
                connection_valid = false;
                result(false, null, "Network error: Cannot reach server.");
                return;
            }

            if (message.status_code != Soup.Status.OK) {
                result(false, null, message.reason_phrase);
                return;
            }

            try {

                var parser = new Json.Parser();
                parser.load_from_data(get_json(message), -1);

                var arr = parser.get_root().get_array();

                var list = new List<KimaiCustomer>();

                for (uint i = 0; i < arr.get_length(); i++)
                    list.append(parse_customer_object(arr.get_element(i).get_object()));

                result(true, list, null);

            } catch (Error e) {
                result(false, null, e.message);
            }
        });
    }

    public void get_projects(int? customer_id, owned ResultList<KimaiProject> result) {
        string endpoint = "/projects";

        if (customer_id != null)
            endpoint += "?customer=" + customer_id.to_string();

        request("GET", endpoint, null, (session, message) => {
            if (message.status_code == Soup.Status.CANT_RESOLVE ||
                message.status_code == Soup.Status.CANT_CONNECT ||
                message.status_code == Soup.Status.SSL_FAILED ||
                message.status_code == Soup.Status.IO_ERROR)
            {
                connection_valid = false;
                result(false, null, "Network error: Cannot reach server.");
                return;
            }

            if (message.status_code != Soup.Status.OK) {
                result(false, null, message.reason_phrase);
                return;
            }

            try {

                var parser = new Json.Parser();
                parser.load_from_data(get_json(message), -1);

                var arr = parser.get_root().get_array();

                var list = new List<KimaiProject>();

                for (uint i = 0; i < arr.get_length(); i++)
                    list.append(parse_project_object(arr.get_element(i).get_object()));

                result(true, list, null);

            } catch (Error e) {
                result(false, null, e.message);
            }
        });
    }

    public void get_activities(int? project_id, owned ResultList<KimaiActivity> result) {
        string endpoint = "/activities";

        if (project_id != null)
            endpoint += "?project=" + project_id.to_string();

        request("GET", endpoint, null, (session, message) => {
            if (message.status_code == Soup.Status.CANT_RESOLVE ||
                message.status_code == Soup.Status.CANT_CONNECT ||
                message.status_code == Soup.Status.SSL_FAILED ||
                message.status_code == Soup.Status.IO_ERROR)
            {
                connection_valid = false;
                result(false, null, "Network error: Cannot reach server.");
                return;
            }

            if (message.status_code != Soup.Status.OK) {
                result(false, null, message.reason_phrase);
                return;
            }

            try {
                var parser = new Json.Parser();
                parser.load_from_data(get_json(message), -1);

                var arr = parser.get_root().get_array();

                var list = new List<KimaiActivity>();

                for (uint i = 0; i < arr.get_length(); i++)
                    list.append(parse_activity_object(arr.get_element(i).get_object()));

                result(true, list, null);

            } catch (Error e) {
                result(false, null, e.message);
            }
        });
    }

    public void get_customer(int customer_id, owned Result<KimaiCustomer> result) {
        string endpoint = "/customers/%d".printf(customer_id);

        request("GET", endpoint, null, (session, message) => {
            if (message.status_code == Soup.Status.CANT_RESOLVE ||
                message.status_code == Soup.Status.CANT_CONNECT ||
                message.status_code == Soup.Status.SSL_FAILED ||
                message.status_code == Soup.Status.IO_ERROR)
            {
                connection_valid = false;
                result(false, null, "Network error: Cannot reach server.");
                return;
            }

            if (message.status_code != Soup.Status.OK) {
                result(false, null, message.reason_phrase);
                return;
            }

            try {

                var parser = new Json.Parser();
                parser.load_from_data(get_json(message), -1);

                var obj = parser.get_root().get_object();

                result(true, parse_customer_object(obj), null);

            } catch (Error e) {
                result(false, null, e.message);
            }
        });
    }


    public void get_project(int project_id, owned Result<KimaiProject> result) {
        string endpoint = "/projects/%d".printf(project_id);

        request("GET", endpoint, null, (session, message) => {
            if (message.status_code == Soup.Status.CANT_RESOLVE ||
                message.status_code == Soup.Status.CANT_CONNECT ||
                message.status_code == Soup.Status.SSL_FAILED ||
                message.status_code == Soup.Status.IO_ERROR)
            {
                connection_valid = false;
                result(false, null, "Network error: Cannot reach server.");
                return;
            }

            if (message.status_code != Soup.Status.OK) {
                result(false, null, message.reason_phrase);
                return;
            }

            try {

                var parser = new Json.Parser();
                parser.load_from_data(get_json(message), -1);

                var obj = parser.get_root().get_object();

                result(true, parse_project_object(obj), null);

            } catch (Error e) {
                result(false, null, e.message);
            }
        });
    }


    public void get_activity(int activity_id, owned Result<KimaiActivity> result) {
        string endpoint = "/activities/%d".printf(activity_id);

        request("GET", endpoint, null, (session, message) => {
            if (message.status_code == Soup.Status.CANT_RESOLVE ||
                message.status_code == Soup.Status.CANT_CONNECT ||
                message.status_code == Soup.Status.SSL_FAILED ||
                message.status_code == Soup.Status.IO_ERROR)
            {
                connection_valid = false;
                result(false, null, "Network error: Cannot reach server.");
                return;
            }

            if (message.status_code != Soup.Status.OK) {
                result(false, null, message.reason_phrase);
                return;
            }

            try {

                var parser = new Json.Parser();
                parser.load_from_data(get_json(message), -1);

                var obj = parser.get_root().get_object();

                result(true, parse_activity_object(obj), null);

            } catch (Error e) {
                result(false, null, e.message);
            }
        });
    }

    public void get_active_timesheets(owned ResultList<KimaiTimesheet> result) {
        request("GET", "/timesheets/active", null, (session, message) => {
            if (message.status_code == Soup.Status.CANT_RESOLVE ||
                message.status_code == Soup.Status.CANT_CONNECT ||
                message.status_code == Soup.Status.SSL_FAILED ||
                message.status_code == Soup.Status.IO_ERROR)
            {
                connection_valid = false;
                result(false, null, "Network error: Cannot reach server.");
                return;
            }

            if (message.status_code != Soup.Status.OK) {
                result(false, null, message.reason_phrase);
                return;
            }

            try {

                var parser = new Json.Parser();
                parser.load_from_data(get_json(message), -1);

                var arr = parser.get_root().get_array();

                var list = new List<KimaiTimesheet>();

                for (uint i = 0; i < arr.get_length(); i++)
                    list.append(parse_timesheet_object(arr.get_element(i).get_object()));

                result(true, list, null);

            } catch (Error e) {
                result(false, null, e.message);
            }
        });
    }

    public void start_timer(int project_id, int activity_id, string description, owned Result<KimaiTimesheet> result) {

        string json_body = "{ \"project\": %d, \"activity\": %d, \"description\": \"%s\" }"
            .printf(project_id, activity_id, description);

        request("POST", "/timesheets", json_body, (session, message) => {
            if (message.status_code == Soup.Status.CANT_RESOLVE ||
                message.status_code == Soup.Status.CANT_CONNECT ||
                message.status_code == Soup.Status.SSL_FAILED ||
                message.status_code == Soup.Status.IO_ERROR)
            {
                connection_valid = false;
                result(false, null, "Network error: Cannot reach server.");
                return;
            }

            if (message.status_code != Soup.Status.OK &&
                message.status_code != Soup.Status.CREATED)
            {
                result(false, null, message.reason_phrase);
                return;
            }

            try {

                var parser = new Json.Parser();
                parser.load_from_data(get_json(message), -1);

                var obj = parser.get_root().get_object();

                result(true, parse_timesheet_object(obj), null);

            } catch (Error e) {
                result(false, null, e.message);
            }
        });
    }

    public void stop_timer(int timesheet_id, owned Result<KimaiTimesheet> result) {
        var now = new DateTime.now_local();
        string timestamp = now.format("%Y-%m-%dT%H:%M:%S");

        string json_body = "{ \"end\": \"%s\" }".printf(timestamp);

        request("PATCH", "/timesheets/%d".printf(timesheet_id), json_body, (session, message) => {
            if (message.status_code == Soup.Status.CANT_RESOLVE ||
                message.status_code == Soup.Status.CANT_CONNECT ||
                message.status_code == Soup.Status.SSL_FAILED ||
                message.status_code == Soup.Status.IO_ERROR)
            {
                connection_valid = false;
                result(false, null, "Network error: Cannot reach server.");
                return;
            }

            if (message.status_code != Soup.Status.OK) {
                result(false, null, message.reason_phrase);
                return;
            }

            try {

                var parser = new Json.Parser();
                parser.load_from_data(get_json(message), -1);

                var obj = parser.get_root().get_object();

                result(true, parse_timesheet_object(obj), null);

            } catch (Error e) {
                result(false, null, e.message);
            }
        });
    }
}
