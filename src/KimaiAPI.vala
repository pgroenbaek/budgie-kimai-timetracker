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
    private bool is_connection_valid = false;

    public KimaiAPI(string base_url, string api_token) {
        if (base_url.has_suffix("/")) {
            this.base_url = base_url.substring(0, base_url.length - 1);
        }
        else {
            this.base_url = base_url;
        }

        this.session = new Soup.Session();
        this.auth_header = "Bearer " + api_token;
    }

    public void validate_connection() throws GLib.Error {
        try {
            GLib.Uri.parse(base_url, GLib.UriFlags.NONE);
        } catch (GLib.Error e) {
            is_connection_valid = false;
            throw new GLib.Error(GLib.Quark.from_string("KimaiAPIError"), 1, "Invalid base URL (please adjust it in settings).");
        }

        if (base_url.length < 8 || base_url.substring(0, 8) != "https://") {
            is_connection_valid = false;
            throw new GLib.Error(GLib.Quark.from_string("KimaiAPIError"), 1, "Invalid base URL (please adjust it in settings).");
        }

        if (base_url.length < 4 || base_url.substring(base_url.length - 4, 4) != "/api") {
            is_connection_valid = false;
            throw new GLib.Error(GLib.Quark.from_string("KimaiAPIError"), 1, "Invalid base URL (please adjust it in settings).");
        }

        var message = new Soup.Message("GET", base_url + "/customers");
        message.request_headers.append("Authorization", this.auth_header);
        this.session.send_message(message);

        if (message.status_code == Soup.Status.UNAUTHORIZED) {
            is_connection_valid = false;
            throw new GLib.Error(GLib.Quark.from_string("KimaiAPIError"), 2, "Invalid API token (please adjust it in settings).");
        }

        if (message.status_code == Soup.Status.OK) {
            is_connection_valid = true;
            return;
        }

        is_connection_valid = false;
        throw new GLib.Error(
            GLib.Quark.from_string("KimaiAPIError"),
            (int) message.status_code,
            "API validation failed: %d %s".printf((int) message.status_code, message.reason_phrase)
        );
    }

    private async string request(string method, string endpoint, string? body = null) throws GLib.Error {
        if (!is_connection_valid) {
            return "{}";
        }

        string url = this.base_url + endpoint;
        var message = new Soup.Message(method, url);
        message.request_headers.append("Authorization", this.auth_header);

        if (body != null) {
            message.request_headers.append("Content-Type", "application/json");
            var body_bytes = (uint8[]) body.data;
            message.set_request("application/json", Soup.MemoryUse.COPY, body_bytes);
        }

        string response = null;

        var loop = new GLib.MainLoop();
        this.session.queue_message(message, (session, message) => {
            if (message.status_code != Soup.Status.OK &&
                message.status_code != Soup.Status.CREATED) 
            {
                loop.quit();
                throw new GLib.Error(
                    GLib.Quark.from_string("KimaiAPIError"),
                    (int) message.status_code,
                    "HTTP request failed: %d %s".printf((int) message.status_code, message.reason_phrase)
                );
            }

            response = (string) message.response_body.data;
            loop.quit();
        });

        loop.run();
        return response;
    }

    private async KimaiCustomer parse_customer_object(Json.Object obj) throws GLib.Error {
        return new KimaiCustomer() {
            id = (int) obj.get_int_member("id"),
            name = obj.get_string_member("name")
        };
    }

    private async KimaiProject parse_project_object(Json.Object obj) throws GLib.Error {
        var project = new KimaiProject() {
            id = (int) obj.get_int_member("id"),
            name = obj.get_string_member("name")
        };

        if (obj.has_member("customer")) {
            var customer_node = obj.get_member("customer");
            if (customer_node.get_node_type() == Json.NodeType.OBJECT) {
                project.customer = yield parse_customer_object(obj.get_object_member("customer"));
            } else {
                project.customer = yield get_customer((int) obj.get_int_member("customer"));
            }
        }

        return project;
    }

    private async KimaiActivity parse_activity_object(Json.Object obj) throws GLib.Error {
        return new KimaiActivity() {
            id = (int) obj.get_int_member("id"),
            name = obj.get_string_member("name")
        };
    }

    private async KimaiTimesheet parse_timesheet_object(Json.Object obj) throws GLib.Error {
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
                timesheet.project = yield parse_project_object(obj.get_object_member("project"));
            } else {
                timesheet.project = yield get_project((int) obj.get_int_member("project"));
            }
        }

        if (obj.has_member("activity")) {
            var activity_node = obj.get_member("activity");
            if (activity_node.get_node_type() == Json.NodeType.OBJECT) {
                timesheet.activity = yield parse_activity_object(obj.get_object_member("activity"));
            } else {
                timesheet.activity = yield get_activity((int) obj.get_int_member("activity"));
            }
        }

        return timesheet;
    }

    private async List<KimaiCustomer> parse_customers_array(Json.Array arr) throws GLib.Error {
        var result = new List<KimaiCustomer>();
        for (uint i = 0; i < arr.get_length(); i++) {
            result.append(yield parse_customer_object(arr.get_element(i).get_object()));
        }
        return result;
    }

    private async List<KimaiProject> parse_projects_array(Json.Array arr) throws GLib.Error {
        var result = new List<KimaiProject>();
        for (uint i = 0; i < arr.get_length(); i++) {
            result.append(yield parse_project_object(arr.get_element(i).get_object()));
        }
        return result;
    }

    private async List<KimaiActivity> parse_activities_array(Json.Array arr) throws GLib.Error {
        var result = new List<KimaiActivity>();
        for (uint i = 0; i < arr.get_length(); i++) {
            result.append(yield parse_activity_object(arr.get_element(i).get_object()));
        }
        return result;
    }

    private async List<KimaiTimesheet> parse_timesheets_array(Json.Array arr) throws GLib.Error {
        var result = new List<KimaiTimesheet>();
        for (uint i = 0; i < arr.get_length(); i++) {
            result.append(yield parse_timesheet_object(arr.get_element(i).get_object()));
        }
        return result;
    }

    public async List<KimaiCustomer> get_customers() throws GLib.Error {
        if (!is_connection_valid) {
            return new List<KimaiCustomer>();
        }

        string response = yield request("GET", "/customers");
        if (response == null || response.length == 0) {
            warning("Empty response from /customers");
            return new List<KimaiCustomer>();
        }

        var parser = new Json.Parser();
        try {
            parser.load_from_data(response, -1);
            var root = parser.get_root();
            if (root == null || root.get_node_type() != Json.NodeType.ARRAY) {
                warning("Invalid JSON structure from /customers");
                return new List<KimaiCustomer>();
            }
            return yield parse_customers_array(root.get_array());
        } catch (GLib.Error e) {
            warning("Failed to parse JSON from /customers: %s".printf(e.message));
            return new List<KimaiCustomer>();
        }
    }

    public async List<KimaiProject> get_projects(int? customer_id = null) throws GLib.Error {
        if (!is_connection_valid) {
            return new List<KimaiProject>();
        }

        string endpoint = "/projects";
        if (customer_id != null) endpoint += "?customer=" + customer_id.to_string();

        string response = yield request("GET", endpoint);
        if (response == null || response.length == 0) {
            warning("Empty response from " + endpoint);
            return new List<KimaiProject>();
        }

        var parser = new Json.Parser();
        try {
            parser.load_from_data(response, -1);
            var root = parser.get_root();
            if (root == null || root.get_node_type() != Json.NodeType.ARRAY) {
                warning("Invalid JSON structure from " + endpoint);
                return new List<KimaiProject>();
            }
            return yield parse_projects_array(root.get_array());
        } catch (GLib.Error e) {
            warning("Failed to parse JSON from " + endpoint + ": %s".printf(e.message));
            return new List<KimaiProject>();
        }
    }

    public async List<KimaiActivity> get_activities(int? project_id = null) throws GLib.Error {
        if (!is_connection_valid) {
            return new List<KimaiActivity>();
        }

        string endpoint = "/activities";
        if (project_id != null) endpoint += "?project=" + project_id.to_string();

        string response = yield request("GET", endpoint);
        if (response == null || response.length == 0) {
            warning("Empty response from " + endpoint);
            return new List<KimaiActivity>();
        }

        var parser = new Json.Parser();
        try {
            parser.load_from_data(response, -1);
            var root = parser.get_root();
            if (root == null || root.get_node_type() != Json.NodeType.ARRAY) {
                warning("Invalid JSON structure from " + endpoint);
                return new List<KimaiActivity>();
            }
            return yield parse_activities_array(root.get_array());
        } catch (GLib.Error e) {
            warning("Failed to parse JSON from " + endpoint + ": %s".printf(e.message));
            return new List<KimaiActivity>();
        }
    }

    public async KimaiCustomer? get_customer(int customer_id) throws GLib.Error {
        if (!is_connection_valid) {
            return null;
        }

        string endpoint = "/customers/%d".printf(customer_id);
        string response = yield request("GET", endpoint);
        if (response == null || response.length == 0) {
            warning("Empty response from " + endpoint);
            return null;
        }

        var parser = new Json.Parser();
        try {
            parser.load_from_data(response, -1);
            var root = parser.get_root();
            if (root == null || root.get_node_type() != Json.NodeType.OBJECT) {
                warning("Invalid JSON structure from " + endpoint);
                return null;
            }
            return yield parse_customer_object(root.get_object());
        } catch (GLib.Error e) {
            warning("Failed to parse JSON from " + endpoint + ": %s".printf(e.message));
            return null;
        }
    }

    public async KimaiProject? get_project(int project_id) throws GLib.Error {
        if (!is_connection_valid) {
            return null;
        }

        string endpoint = "/projects/%d".printf(project_id);
        string response = yield request("GET", endpoint);
        if (response == null || response.length == 0) {
            warning("Empty response from " + endpoint);
            return null;
        }

        var parser = new Json.Parser();
        try {
            parser.load_from_data(response, -1);
            var root = parser.get_root();
            if (root == null || root.get_node_type() != Json.NodeType.OBJECT) {
                warning("Invalid JSON structure from " + endpoint);
                return null;
            }
            return yield parse_project_object(root.get_object());
        } catch (GLib.Error e) {
            warning("Failed to parse JSON from " + endpoint + ": %s".printf(e.message));
            return null;
        }
    }

    public async KimaiActivity? get_activity(int activity_id) throws GLib.Error {
        if (!is_connection_valid) {
            return null;
        }

        string endpoint = "/activities/%d".printf(activity_id);
        string response = yield request("GET", endpoint);
        if (response == null || response.length == 0) {
            warning("Empty response from " + endpoint);
            return null;
        }

        var parser = new Json.Parser();
        try {
            parser.load_from_data(response, -1);
            var root = parser.get_root();
            if (root == null || root.get_node_type() != Json.NodeType.OBJECT) {
                warning("Invalid JSON structure from " + endpoint);
                return null;
            }
            return yield parse_activity_object(root.get_object());
        } catch (GLib.Error e) {
            warning("Failed to parse JSON from " + endpoint + ": %s".printf(e.message));
            return null;
        }
    }

    public async List<KimaiTimesheet> get_active_timesheets() throws GLib.Error {
        if (!is_connection_valid) {
            return new List<KimaiTimesheet>();
        }

        string response = yield request("GET", "/timesheets/active");
        if (response == null || response.length == 0) {
            warning("Empty response from /timesheets/active");
            return new List<KimaiTimesheet>();
        }

        var parser = new Json.Parser();
        try {
            parser.load_from_data(response, -1);
            var root = parser.get_root();
            if (root == null || root.get_node_type() != Json.NodeType.ARRAY) {
                warning("Invalid JSON structure from /timesheets/active");
                return new List<KimaiTimesheet>();
            }
            return yield parse_timesheets_array(root.get_array());
        } catch (GLib.Error e) {
            warning("Failed to parse JSON from /timesheets/active: %s".printf(e.message));
            return new List<KimaiTimesheet>();
        }
    }

    public async KimaiTimesheet? start_timer(int project_id, int activity_id, string description) throws GLib.Error {
        if (!is_connection_valid) {
            return null;
        }

        string json_body = "{ \"project\": %d, \"activity\": %d, \"description\": \"%s\" }".printf(project_id, activity_id, description);
        string response = yield request("POST", "/timesheets", json_body);
        if (response == null || response.length == 0) {
            warning("Empty response from POST /timesheets");
            return null;
        }

        var parser = new Json.Parser();
        try {
            parser.load_from_data(response, -1);
            var root = parser.get_root();
            if (root == null || root.get_node_type() != Json.NodeType.OBJECT) {
                warning("Invalid JSON structure from POST /timesheets");
                return null;
            }
            return yield parse_timesheet_object(root.get_object());
        } catch (GLib.Error e) {
            warning("Failed to parse JSON from POST /timesheets: %s".printf(e.message));
            return null;
        }
    }

    public async KimaiTimesheet? stop_timer(int timesheet_id) throws GLib.Error {
        if (!is_connection_valid) {
            return null;
        }

        var now = new DateTime.now_local();
        string timestamp = now.format("%Y-%m-%dT%H:%M:%S");

        string json_body = "{ \"end\": \"%s\" }".printf(timestamp);
        string url = "/timesheets/%d".printf(timesheet_id);

        string response = yield request("PATCH", url, json_body);
        if (response == null || response.length == 0) {
            warning("Empty response from PATCH " + url);
            return null;
        }

        var parser = new Json.Parser();
        try {
            parser.load_from_data(response, -1);
            var root = parser.get_root();
            if (root == null || root.get_node_type() != Json.NodeType.OBJECT) {
                warning("Invalid JSON structure from PATCH " + url);
                return null;
            }
            return yield parse_timesheet_object(root.get_object());
        } catch (GLib.Error e) {
            warning("Failed to parse JSON from PATCH " + url + ": %s".printf(e.message));
            return null;
        }
    }
}
