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
            message.request_headers.append("Accept", "application/json");
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
    
    private KimaiCustomer parse_customer_object(Json.Object obj) throws GLib.Error {
        var c = new KimaiCustomer();
        c.id = (int) obj.get_int_member("id");
        c.name = obj.get_string_member("name");
        return c;
    }

    private KimaiProject parse_project_object(Json.Object obj) throws GLib.Error {
        var p = new KimaiProject();
        p.id = (int) obj.get_int_member("id");
        p.name = obj.get_string_member("name");

        if (obj.has_member("customer")) {
            var node = obj.get_member("customer");

            if (node.get_node_type() == Json.NodeType.VALUE) {
                p.customerId = (int) obj.get_int_member("customer");
            }
            else {
                var c = obj.get_object_member("customer");
                p.customerId = (int) c.get_int_member("id");
            }
        }

        return p;
    }

    private KimaiActivity parse_activity_object(Json.Object obj) throws GLib.Error {
        var a = new KimaiActivity();
        a.id = (int) obj.get_int_member("id");
        a.name = obj.get_string_member("name");
        return a;
    }

    private KimaiTimesheet parse_timesheet_object(Json.Object obj) throws GLib.Error {
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
            }
            else {
                var p = obj.get_object_member("project");
                t.projectId = (int) p.get_int_member("id");
            }
        }

        if (obj.has_member("activity")) {
            var node = obj.get_member("activity");

            if (node.get_node_type() == Json.NodeType.VALUE) {
                t.activityId = (int) obj.get_int_member("activity");
            }
            else {
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
                result(false, (GLib.List<KimaiCustomer>?) null, "Network error: Cannot reach server.");
                return;
            }

            if (message.status_code != Soup.Status.OK) {
                connection_valid = false;
                result(false, (GLib.List<KimaiCustomer>?) null, message.reason_phrase);
                return;
            }

            try {
                var parser = new Json.Parser();
                parser.load_from_data(get_json(message), -1);

                var root = parser.get_root();

                if (root == null || root.get_node_type() != Json.NodeType.ARRAY) {
                    GLib.warning("Invalid JSON structure from /timesheets/active");
                    result(false, null, "Unexpected JSON response from API, was not an array.");
                    return;
                }

                var arr = root.get_array();
                var list = new GLib.List<KimaiCustomer>();

                for (uint i = 0; i < arr.get_length(); i++) {
                    var node = arr.get_element(i);

                    if (node == null || node.get_node_type() != Json.NodeType.OBJECT) {
                        continue;
                    }

                    list.append(parse_customer_object(node.get_object()));
                }

                result(true, list, null);

            } catch (Error e) {
                result(false, (GLib.List<KimaiCustomer>?) null, e.message);
            }
        });
    }

    public void get_projects(int? customer_id, owned ResultList<KimaiProject> result) {
        string endpoint = "/projects";

        if (customer_id != null) {
            endpoint += "?customer=" + customer_id.to_string();
        }

        request("GET", endpoint, null, (session, message) => {
            if (message.status_code == Soup.Status.CANT_RESOLVE ||
                message.status_code == Soup.Status.CANT_CONNECT ||
                message.status_code == Soup.Status.SSL_FAILED ||
                message.status_code == Soup.Status.IO_ERROR)
            {
                connection_valid = false;
                result(false, (GLib.List<KimaiProject>?) null, "Network error: Cannot reach server.");
                return;
            }

            if (message.status_code != Soup.Status.OK) {
                connection_valid = false;
                result(false, (GLib.List<KimaiProject>?) null, message.reason_phrase);
                return;
            }

            try {
                var parser = new Json.Parser();
                parser.load_from_data(get_json(message), -1);

                var root = parser.get_root();

                if (root == null || root.get_node_type() != Json.NodeType.ARRAY) {
                    GLib.warning("Invalid JSON structure from /timesheets/active");
                    result(false, null, "Unexpected JSON response from API, was not an array.");
                    return;
                }

                var arr = root.get_array();
                var list = new GLib.List<KimaiProject>();

                for (uint i = 0; i < arr.get_length(); i++) {
                    var node = arr.get_element(i);

                    if (node == null || node.get_node_type() != Json.NodeType.OBJECT) {
                        continue;
                    }

                    list.append(parse_project_object(node.get_object()));
                }

                result(true, list, null);

            } catch (Error e) {
                result(false, (GLib.List<KimaiProject>?) null, e.message);
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
                result(false, (GLib.List<KimaiActivity>?) null, "Network error: Cannot reach server.");
                return;
            }

            if (message.status_code != Soup.Status.OK) {
                connection_valid = false;
                result(false, (GLib.List<KimaiActivity>?) null, message.reason_phrase);
                return;
            }

            try {
                var parser = new Json.Parser();
                parser.load_from_data(get_json(message), -1);

                var root = parser.get_root();

                if (root == null || root.get_node_type() != Json.NodeType.ARRAY) {
                    GLib.warning("Invalid JSON structure from /timesheets/active");
                    result(false, null, "Unexpected JSON response from API, was not an array.");
                    return;
                }

                var arr = root.get_array();
                var list = new GLib.List<KimaiActivity>();

                for (uint i = 0; i < arr.get_length(); i++) {
                    var node = arr.get_element(i);

                    if (node == null || node.get_node_type() != Json.NodeType.OBJECT) {
                        continue;
                    }

                    list.append(parse_activity_object(node.get_object()));
                }

                result(true, list, null);

            } catch (Error e) {
                result(false, (GLib.List<KimaiActivity>?) null, e.message);
            }
        });
    }

    public void get_active_timesheets(owned ResultList<KimaiTimesheet?> result) {
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
                connection_valid = false;
                result(false, null, message.reason_phrase);
                return;
            }

            string response = get_json(message);

            if (response == null || response.length == 0) {
                GLib.warning("Empty response from /timesheets/active");
                result(true, new GLib.List<KimaiTimesheet>(), null);
                return;
            }

            try {
                var parser = new Json.Parser();
                parser.load_from_data(response, -1);

                var root = parser.get_root();

                if (root == null || root.get_node_type() != Json.NodeType.ARRAY) {
                    GLib.warning("Invalid JSON structure from /timesheets/active");
                    result(false, null, "Unexpected JSON response from API, was not an array.");
                    return;
                }

                var arr = root.get_array();
                var list = new GLib.List<KimaiTimesheet>();

                for (uint i = 0; i < arr.get_length(); i++) {
                    var node = arr.get_element(i);

                    if (node == null || node.get_node_type() != Json.NodeType.OBJECT) {
                        continue;
                    }

                    list.append(parse_timesheet_object(node.get_object()));
                }

                result(true, list, null);

            } catch (Error e) {
                GLib.warning("Failed to parse JSON: %s".printf(e.message));
                result(false, null, e.message);
            }
        });
    }

    public void start_timer(int project_id, int activity_id, string description, owned Result<KimaiTimesheet?> result) {

        string json_body = "{ \"project\": %d, \"activity\": %d, \"description\": \"%s\" }"
            .printf(project_id, activity_id, description);

        request("POST", "/timesheets", json_body, (session, message) => {
            if (message.status_code == Soup.Status.CANT_RESOLVE ||
                message.status_code == Soup.Status.CANT_CONNECT ||
                message.status_code == Soup.Status.SSL_FAILED ||
                message.status_code == Soup.Status.IO_ERROR)
            {
                connection_valid = false;
                result(false, (KimaiTimesheet?) null, "Network error: Cannot reach server.");
                return;
            }

            if (message.status_code != Soup.Status.OK &&
                message.status_code != Soup.Status.CREATED)
            {
                connection_valid = false;
                result(false, (KimaiTimesheet?) null, message.reason_phrase);
                return;
            }

            try {

                var parser = new Json.Parser();
                parser.load_from_data(get_json(message), -1);

                var root = parser.get_root();

                if (root == null || root.get_node_type() != Json.NodeType.OBJECT) {
                    GLib.warning("Invalid JSON structure from /timesheets/active");
                    result(false, null, "Unexpected JSON response from API, was not an object.");
                    return;
                }

                var obj = root.get_object();

                result(true, parse_timesheet_object(obj), null);

            } catch (Error e) {
                result(false, (KimaiTimesheet?) null, e.message);
            }
        });
    }

    public void stop_timer(int timesheet_id, owned Result<KimaiTimesheet?> result) {
        request("PATCH", "/timesheets/%d/stop".printf(timesheet_id), null, (session, message) => {
            if (message.status_code == Soup.Status.CANT_RESOLVE ||
                message.status_code == Soup.Status.CANT_CONNECT ||
                message.status_code == Soup.Status.SSL_FAILED ||
                message.status_code == Soup.Status.IO_ERROR)
            {
                connection_valid = false;
                result(false, (KimaiTimesheet?) null, "Network error: Cannot reach server.");
                return;
            }

            if (message.status_code != Soup.Status.OK) {
                connection_valid = false;
                result(false, (KimaiTimesheet?) null, message.reason_phrase);
                return;
            }

            try {
                var parser = new Json.Parser();
                parser.load_from_data(get_json(message), -1);

                var root = parser.get_root();

                if (root == null || root.get_node_type() != Json.NodeType.OBJECT) {
                    GLib.warning("Invalid JSON structure from /timesheets/active");
                    result(false, null, "Unexpected JSON response from API, was not an object.");
                    return;
                }

                var obj = root.get_object();

                result(true, parse_timesheet_object(obj), null);

            } catch (Error e) {
                result(false, (KimaiTimesheet?) null, e.message);
            }
        });
    }
}
