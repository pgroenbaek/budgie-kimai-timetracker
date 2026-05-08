/*
 * This file is part of the Budgie Desktop Kimai Timetracker Applet.
 *
 * Copyright (C) 2026 Peter Grønbæk Andersen <peter@grnbk.io>
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

using GLib;

[CCode(cheader_filename = "X11/Xlib.h")]
public extern void* XOpenDisplay(string? name);

[CCode(cheader_filename = "X11/Xlib.h")]
public extern int XCloseDisplay(void* display);

[CCode(cheader_filename = "X11/Xlib.h")]
public extern ulong XDefaultRootWindow(void* display);

[CCode(cheader_filename = "stdlib.h")]
public extern void free(void* ptr);

[CCode(cname = "XScreenSaverAllocInfo")]
public extern void* xss_alloc();

[CCode(cname = "XScreenSaverQueryInfo")]
public extern int xss_query(
    void* display,
    ulong drawable,
    void* info
);

public class KimaiTimerIdleDetector : Object {

    private void* display;
    private ulong root;
    private void* info;
    private bool is_wayland;

    public KimaiTimerIdleDetector() {

        var s = Environment.get_variable("XDG_SESSION_TYPE");
        is_wayland = (s != null && s.down() == "wayland");

        if (!is_wayland) {
            display = XOpenDisplay(null);

            if (display != null) {
                root = XDefaultRootWindow(display);
                info = xss_alloc();
            }
        }
    }

    public uint64 get_idle_seconds() {
        if (is_wayland) {
            return get_idle_wayland();
        }

        if (display == null || info == null) {
            return 0;
        }

        xss_query(display, root, info);

        uint64 idle = ((uint64[]) info)[3];

        return idle / 1000;
    }

    private uint64 get_idle_wayland() {
        try {
            string[] argv = {
                "gdbus", "call",
                "--system",
                "--dest", "org.freedesktop.login1",
                "--object-path", "/org/freedesktop/login1/session/self",
                "--method", "org.freedesktop.DBus.Properties.Get",
                "org.freedesktop.login1.Session",
                "IdleSinceHintMonotonic"
            };

            string stdout;
            Process.spawn_sync(
                null,
                argv,
                null,
                SpawnFlags.SEARCH_PATH,
                null,
                out stdout,
                null,
                null
            );

            int start = stdout.index_of("uint64 ");
            if (start < 0) {
                return 0;
            }

            start += 7;
            int end = stdout.index_of(",", start);
            if (end < 0) {
                return 0;
            }

            string num = stdout.substring(start, end - start).strip();

            uint64 idle_since = uint64.parse(num);
            uint64 now = GLib.get_monotonic_time();

            if (now > idle_since) {
                return (now - idle_since) / 1000000;
            }

        }
        catch (Error e) {

        }

        return 0;
    }

    public string get_backend_name() {
        return is_wayland ? "wayland-logind" : "x11-xss";
    }

    ~StatusDotIdleDetector() {
        if (info != null) {
            free(info);
        }

        if (display != null) {
            XCloseDisplay(display);
        }
    }
}