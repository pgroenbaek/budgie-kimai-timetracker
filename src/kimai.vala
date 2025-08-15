using Soup;
using Json;
using GLib;

public class Kimai : Object {
    private Session session;
    private string base_url;
    private string auth_header;

    public Kimai (string base_url, string username, string api_token) {
        // Ensure no trailing slash in base_url
        if (base_url.has_suffix ("/")) {
            this.base_url = base_url.chomp ();
        } else {
            this.base_url = base_url;
        }

        this.session = new Session ();
        string auth = Base64.encode ((username + ":" + api_token).data);
        this.auth_header = "Basic " + auth;
    }

    private string request (string method, string endpoint, string? body = null) throws Error {
        string url = this.base_url + endpoint;
        var message = new Message (method, url);
        message.request_headers.append ("Authorization", this.auth_header);

        if (body != null) {
            message.request_headers.append ("Content-Type", "application/json");
            message.set_request_body_from_bytes ("application/json", new Bytes (body.data));
        }

        this.session.send_and_read (message, null);
        return (string) message.get_body ().data;
    }

    // List active timesheets, parsed into a Json.Array
    public Json.Array list_active_timesheets () throws Error {
        string json_str = request ("GET", "/timesheets?active=1");
        var parser = new Json.Parser ();
        parser.load_from_data (json_str, -1);
        var root = parser.get_root ();
        if (root.get_value_type () != Json.NodeType.ARRAY) {
            throw new Error.FAILED ("Unexpected JSON structure: expected array");
        }
        return root.get_array ();
    }

    // Start a timer
    public Json.Node start_timer (int project_id, int activity_id, string description) throws Error {
        var json_body = @"{
            ""project"": %d,
            ""activity"": %d,
            ""description"": ""%s""
        }".printf (project_id, activity_id, description);

        string json_str = request ("POST", "/timesheets", json_body);
        var parser = new Json.Parser ();
        parser.load_from_data (json_str, -1);
        return parser.get_root ();
    }

    // Stop a timer (pass the ID of the timesheet)
    public Json.Node stop_timer (int timesheet_id) throws Error {
        var json_body = @"{
            ""end"": ""now""
        }";
        string json_str = request ("PATCH", "/timesheets/%d".printf (timesheet_id), json_body);
        var parser = new Json.Parser ();
        parser.load_from_data (json_str, -1);
        return parser.get_root ();
    }
}
