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
            throw new GLib.Error(GLib.Quark.from_string("KimaiAPIError"), 1, "Invalid base URL (please adjust it in settings)." + base_url);
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

    private string request(string method, string endpoint, string? body = null) throws GLib.Error {
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

        this.session.send_message(message);

        if (message.status_code != Soup.Status.OK && message.status_code != Soup.Status.CREATED) {
            throw new GLib.Error(
                GLib.Quark.from_string("KimaiAPIError"),
                (int) message.status_code,
                "HTTP request failed: %d %s".printf((int) message.status_code, message.reason_phrase)
            );
        }

        return (string) message.response_body.data;
    }

    private KimaiCustomer parse_customer_object(Json.Object obj) throws GLib.Error {
        return new KimaiCustomer() {
            id = (int) obj.get_int_member("id"),
            name = obj.get_string_member("name")
        };
    }

    private KimaiProject parse_project_object(Json.Object obj) throws GLib.Error {
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

    private KimaiActivity parse_activity_object(Json.Object obj) throws GLib.Error {
        return new KimaiActivity() {
            id = (int) obj.get_int_member("id"),
            name = obj.get_string_member("name")
        };
    }

    private KimaiTimesheet parse_timesheet_object(Json.Object obj) throws GLib.Error {
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

    private List<KimaiCustomer> parse_customers_array(Json.Array arr) throws GLib.Error {
        var result = new List<KimaiCustomer>();
        for (uint i = 0; i < arr.get_length(); i++) {
            result.append(parse_customer_object(arr.get_element(i).get_object()));
        }
        return result;
    }

    private List<KimaiProject> parse_projects_array(Json.Array arr) throws GLib.Error {
        var result = new List<KimaiProject>();
        for (uint i = 0; i < arr.get_length(); i++) {
            result.append(parse_project_object(arr.get_element(i).get_object()));
        }
        return result;
    }

    private List<KimaiActivity> parse_activities_array(Json.Array arr) throws GLib.Error {
        var result = new List<KimaiActivity>();
        for (uint i = 0; i < arr.get_length(); i++) {
            result.append(parse_activity_object(arr.get_element(i).get_object()));
        }
        return result;
    }

    private List<KimaiTimesheet> parse_timesheets_array(Json.Array arr) throws GLib.Error {
        var result = new List<KimaiTimesheet>();
        for (uint i = 0; i < arr.get_length(); i++) {
            result.append(parse_timesheet_object(arr.get_element(i).get_object()));
        }
        return result;
    }

    public List<KimaiCustomer> get_customers() throws GLib.Error {
        if (!is_connection_valid) {
            return new List<KimaiCustomer>();
        }

        var parser = new Json.Parser();
        parser.load_from_data(request("GET", "/customers"), -1);
        return parse_customers_array(parser.get_root().get_array());
    }

    public List<KimaiProject> get_projects(int? customer_id = null) throws GLib.Error {
        if (!is_connection_valid) {
            return new List<KimaiProject>();
        }

        string endpoint = "/projects";
        if (customer_id != null) {
            endpoint += "?customer=" + customer_id.to_string();
        }

        var parser = new Json.Parser();
        parser.load_from_data(request("GET", endpoint), -1);
        return parse_projects_array(parser.get_root().get_array());
    }

    public List<KimaiActivity> get_activities(int? project_id = null) throws GLib.Error {
        if (!is_connection_valid) {
            return new List<KimaiActivity>();
        }

        string endpoint = "/activities";
        if (project_id != null) {
            endpoint += "?project=" + project_id.to_string();
        }

        var parser = new Json.Parser();
        parser.load_from_data(request("GET", endpoint), -1);
        return parse_activities_array(parser.get_root().get_array());
    }
    
    public KimaiCustomer? get_customer(int customer_id) throws GLib.Error {
        if (!is_connection_valid) {
            return null;
        }

        string endpoint = "/customers/%d".printf(customer_id);
        string response = request("GET", endpoint);

        var parser = new Json.Parser();
        parser.load_from_data(response, -1);
        return parse_customer_object(parser.get_root().get_object());
    }

    public KimaiProject? get_project(int project_id) throws GLib.Error {
        if (!is_connection_valid) {
            return null;
        }

        string endpoint = "/projects/%d".printf(project_id);
        string response = request("GET", endpoint);

        var parser = new Json.Parser();
        parser.load_from_data(response, -1);
        return parse_project_object(parser.get_root().get_object());
    }

    public KimaiActivity? get_activity(int activity_id) throws GLib.Error {
        if (!is_connection_valid) {
            return null;
        }

        string endpoint = "/activities/%d".printf(activity_id);
        string response = request("GET", endpoint);

        var parser = new Json.Parser();
        parser.load_from_data(response, -1);
        return parse_activity_object(parser.get_root().get_object());
    }

    public List<KimaiTimesheet> get_active_timesheets() throws GLib.Error {
        if (!is_connection_valid) {
            return new List<KimaiTimesheet>();
        }

        var parser = new Json.Parser();
        parser.load_from_data(request("GET", "/timesheets/active"), -1);
        return parse_timesheets_array(parser.get_root().get_array());
    }

    public KimaiTimesheet? start_timer(int project_id, int activity_id, string description) throws GLib.Error {
        if (!is_connection_valid) {
            return null;
        }

        string json_body = "{ \"project\": %d, \"activity\": %d, \"description\": \"%s\" }"
                            .printf(project_id, activity_id, description);
        string response = request("POST", "/timesheets", json_body);

        var parser = new Json.Parser();
        parser.load_from_data(response, -1);
        return parse_timesheet_object(parser.get_root().get_object());
    }

    public KimaiTimesheet? stop_timer(int timesheet_id) throws GLib.Error {
        if (!is_connection_valid) {
            return null;
        }

        var now = new DateTime.now_local();
        string timestamp = now.format("%Y-%m-%dT%H:%M:%S");

        string json_body = "{ \"end\": \"%s\" }".printf(timestamp);
        string url = "/timesheets/%d".printf(timesheet_id);
        string response = request("PATCH", url, json_body);

        var parser = new Json.Parser();
        parser.load_from_data(response, -1);
        return parse_timesheet_object(parser.get_root().get_object());
    }
}

