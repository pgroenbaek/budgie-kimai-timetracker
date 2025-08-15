public static int main (string[] args) {
    try {
        var kimai = new Kimai (
            "https://kimai.example.com/api",  // API base URL
            "myuser",                         // Username
            "myapitoken"                      // API token
        );

        // make a switch called stop upon inactivity with a spinner for minutes

        // List active timers
        string active = kimai.list_active_timesheets ();
        print ("Active timers: %s\n", active);

        // Start a timer
        string started = kimai.start_timer (1, 1, "Working on Budgie applet");
        print ("Started timer: %s\n", started);

        // Stop a timer with ID 123
        string stopped = kimai.stop_timer (123);
        print ("Stopped timer: %s\n", stopped);

    } catch (Error e) {
        stderr.printf ("Error: %s\n", e.message);
    }

    return 0;
}