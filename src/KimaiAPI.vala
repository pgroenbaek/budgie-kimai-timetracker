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
        if (base_url.has_suffix("/"))
            this.base_url = base_url.chomp();
        else
            this.base_url = base_url;

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

        var message = new Soup.Message("GET", base_url + "/customers");
        message.request_headers.append("Authorization", this.auth_header);
        this.session.send_message(message);

        if (message.status_code == Soup.Status.UNAUTHORIZED) {
            is_connection_valid = false;
            throw new GLib.Error(GLib.Quark.from_string("KimaiAPIError"), 2, "Invalid API token (please adjust it in settings).");
        }

        if (message.status_code != Soup.Status.OK) {
            is_connection_valid = false;
            throw new GLib.Error(
                GLib.Quark.from_string("KimaiAPIError"),
                (int) message.status_code,
                "API validation failed: %d %s".printf((int) message.status_code, message.reason_phrase)
            );
        }
    }

    private KimaiTimesheet empty_timesheet() {
        var ts = new KimaiTimesheet();
        ts.id = 0;
        ts.description = "";
        ts.begin = new DateTime.now();
        ts.end = null;

        ts.project = new KimaiProject();
        ts.project.id = 0;
        ts.project.name = "";
        ts.project.customer = new KimaiCustomer();
        ts.project.customer.id = 0;
        ts.project.customer.name = "";

        ts.activity = new KimaiActivity();
        ts.activity.id = 0;
        ts.activity.name = "";

        return ts;
    }

    private List<KimaiCustomer> empty_customers() {
        var list = new List<KimaiCustomer>();
        var c = new KimaiCustomer();
        c.id = 0;
        c.name = "";
        list.append(c);
        return list;
    }

    private List<KimaiProject> empty_projects() {
        var list = new List<KimaiProject>();
        var p = new KimaiProject();
        p.id = 0;
        p.name = "";
        p.customer = new KimaiCustomer();
        p.customer.id = 0;
        p.customer.name = "";
        list.append(p);
        return list;
    }

    private List<KimaiActivity> empty_activities() {
        var list = new List<KimaiActivity>();
        var a = new KimaiActivity();
        a.id = 0;
        a.name = "";
        list.append(a);
        return list;
    }

    private List<KimaiTimesheet> empty_timesheets() {
        var list = new List<KimaiTimesheet>();
        list.append(empty_timesheet());
        return list;
    }

    private string request(string method, string endpoint, string? body = null) throws GLib.Error {
        if (!is_connection_valid)
            return "{}";

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

    private List<KimaiCustomer> parse_customers(string json_str) throws Error {
        var parser = new Json.Parser();
        parser.load_from_data(json_str, -1);
        var arr = parser.get_root().get_array();
        var result = new List<KimaiCustomer>();

        for (uint i = 0; i < arr.get_length(); i++) {
            var obj = arr.get_element(i).get_object();
            result.append(new KimaiCustomer() {
                id = (int) obj.get_int_member("id"),
                name = obj.get_string_member("name")
            });
        }

        return result;
    }

    private List<KimaiProject> parse_projects(string json_str) throws Error {
        var parser = new Json.Parser();
        parser.load_from_data(json_str, -1);
        var arr = parser.get_root().get_array();
        var result = new List<KimaiProject>();

        for (uint i = 0; i < arr.get_length(); i++) {
            var obj = arr.get_element(i).get_object();
            var proj = new KimaiProject() {
                id = (int) obj.get_int_member("id"),
                name = obj.get_string_member("name")
            };
            if (obj.has_member("customer")) {
                var cust_obj = obj.get_object_member("customer");
                proj.customer = new KimaiCustomer() {
                    id = (int) cust_obj.get_int_member("id"),
                    name = cust_obj.get_string_member("name")
                };
            }
            result.append(proj);
        }

        return result;
    }

    private List<KimaiActivity> parse_activities(string json_str) throws Error {
        var parser = new Json.Parser();
        parser.load_from_data(json_str, -1);
        var arr = parser.get_root().get_array();
        var result = new List<KimaiActivity>();

        for (uint i = 0; i < arr.get_length(); i++) {
            var obj = arr.get_element(i).get_object();
            result.append(new KimaiActivity() {
                id = (int) obj.get_int_member("id"),
                name = obj.get_string_member("name")
            });
        }

        return result;
    }

    private List<KimaiTimesheet> parse_timesheets(string json_str) throws Error {
        var parser = new Json.Parser();
        parser.load_from_data(json_str, -1);
        var arr = parser.get_root().get_array();
        var result = new List<KimaiTimesheet>();

        for (uint i = 0; i < arr.get_length(); i++) {
            var obj = arr.get_element(i).get_object();

            var proj_obj = obj.get_object_member("project");
            var cust_obj = proj_obj.get_object_member("customer");
            var act_obj  = obj.get_object_member("activity");

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

            timesheet.project = new KimaiProject() {
                id = (int) proj_obj.get_int_member("id"),
                name = proj_obj.get_string_member("name"),
                customer = new KimaiCustomer() {
                    id = (int) cust_obj.get_int_member("id"),
                    name = cust_obj.get_string_member("name")
                }
            };

            timesheet.activity = new KimaiActivity() {
                id = (int) act_obj.get_int_member("id"),
                name = act_obj.get_string_member("name")
            };

            result.append(timesheet);
        }

        return result;
    }

    public List<KimaiCustomer> list_customers() throws Error {
        if (!is_connection_valid) return empty_customers();

        return parse_customers(request("GET", "/customers"));
    }

    public List<KimaiProject> list_projects(int? customer_id = null) throws Error {
        if (!is_connection_valid) return empty_projects();

        string endpoint = "/projects";
        if (customer_id != null)
            endpoint += "?customer=" + customer_id.to_string();
        
        return parse_projects(request("GET", endpoint));
    }

    public List<KimaiActivity> list_activities(int? project_id = null) throws Error {
        if (!is_connection_valid) return empty_activities();

        string endpoint = "/activities";
        if (project_id != null)
            endpoint += "?project=" + project_id.to_string();
        
        return parse_activities(request("GET", endpoint));
    }

    public List<KimaiTimesheet> list_active_timesheets() throws Error {
        if (!is_connection_valid) return empty_timesheets();

        return parse_timesheets(request("GET", "/timesheets?active=1"));
    }

    public KimaiTimesheet start_timer(int project_id, int activity_id, string description) throws Error {
        if (!is_connection_valid) return empty_timesheet();

        string json_body = "{ \"project\": %d, \"activity\": %d, \"description\": \"%s\" }"
                            .printf(project_id, activity_id, description);

        var response = request("POST", "/timesheets", json_body);

        return parse_timesheets("[" + response + "]").nth_data(0);
    }

    public KimaiTimesheet stop_timer(int timesheet_id) throws Error {
        if (!is_connection_valid) return empty_timesheet();

        string json_body = "{ \"end\": \"now\" }";
        string url = "/timesheets/%d".printf(timesheet_id);

        var response = request("PATCH", url, json_body);

        return parse_timesheets("[" + response + "]").nth_data(0);
    }
}

