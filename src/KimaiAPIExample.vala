
// make a switch called stop upon inactivity with a spinner for minutes

public static int main (string[] args) {
    try {
        var kimai = new Kimai (
            "https://kimai.example.com/api",  // API base URL
            "myuser",                         // Username
            "myapitoken"                      // API token
        );

        // List active timers and print their IDs/descriptions
        var active_array = kimai.list_active_timesheets ();
        for (uint i = 0; i < active_array.get_length (); i++) {
            var entry = active_array.get_object_element (i);
            int id = entry.get_int_member ("id");
            string desc = entry.get_string_member ("description");
            print ("Active ID: %d, Desc: %s\n", id, desc);
        }

        // Start a timer
        var started = kimai.start_timer (1, 1, "Working on Budgie applet");
        print ("Started ID: %d\n", started.get_object ().get_int_member ("id"));

        // Stop a timer with ID 123
        kimai.stop_timer (123);
        print ("Stopped timer 123\n");

    } catch (Error e) {
        stderr.printf ("Error: %s\n", e.message);
    }

    return 0;
}