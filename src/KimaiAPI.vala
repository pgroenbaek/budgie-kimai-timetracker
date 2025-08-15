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

public class KimaiAPI : Object {
    private Session session;
    private string base_url;
    private string auth_header;

    public KimaiAPI(string base_url, string username, string api_token) {
        // Ensure no trailing slash in base_url
        if (base_url.has_suffix ("/")) {
            this.base_url = base_url.chomp ();
        } else {
            this.base_url = base_url;
        }

        this.session = new Session();
        string auth = Base64.encode((username + ":" + api_token).data);
        this.auth_header = "Basic " + auth;
    }

    private string request(string method, string endpoint, string? body = null) throws Error {
        string url = this.base_url + endpoint;
        var message = new Message(method, url);
        message.request_headers.append("Authorization", this.auth_header);

        if (body != null) {
            message.request_headers.append("Content-Type", "application/json");
            message.set_request_body_from_bytes("application/json", new Bytes(body.data));
        }

        this.session.send_and_read(message, null);
        return (string) message.get_body().data;
    }

    // List active timesheets, parsed into a Json.Array
    public Json.Array list_active_timesheets() throws Error {
        string json_str = request("GET", "/timesheets?active=1");

        var parser = new Json.Parser();
        parser.load_from_data(json_str, -1);

        var root = parser.get_root();
        if (root.get_value_type() != Json.NodeType.ARRAY) {
            throw new Error.FAILED("Unexpected JSON structure: expected array");
        }

        return root.get_array();
    }

    // Start a timer
    public Json.Node start_timer(int project_id, int activity_id, string description) throws Error {
        var json_body = @"{
            ""project"": %d,
            ""activity"": %d,
            ""description"": ""%s""
        }".printf(project_id, activity_id, description);

        string json_str = request("POST", "/timesheets", json_body);
        var parser = new Json.Parser();
        parser.load_from_data(json_str, -1);
        return parser.get_root();
    }

    // Stop a timer (pass the ID of the timesheet)
    public Json.Node stop_timer(int timesheet_id) throws Error {
        var json_body = @"{
            ""end"": ""now""
        }";
        string json_str = request("PATCH", "/timesheets/%d".printf(timesheet_id), json_body);
        var parser = new Json.Parser();
        parser.load_from_data(json_str, -1);
        return parser.get_root();
    }
}
