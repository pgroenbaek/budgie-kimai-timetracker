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

using GLib;

/*
 * X11 idle detector C wrapper.
 */
[CCode(cheader_filename = "x11-idle-detector.h")]
private extern void* x11_idle_new();

[CCode(cheader_filename = "x11-idle-detector.h")]
private extern void x11_idle_free(void* detector);

[CCode(cheader_filename = "x11-idle-detector.h")]
private extern uint64 x11_idle_seconds(void* detector);


/*
 * Wayland idle detector C wrapper.
 */
[CCode(cheader_filename = "wayland-idle-detector.h")]
private extern void* wayland_idle_new();

[CCode(cheader_filename = "wayland-idle-detector.h")]
private extern void wayland_idle_free(void* detector);

[CCode(cheader_filename = "wayland-idle-detector.h")]
private extern uint64 wayland_idle_seconds(void* detector);


/*
 * Idle detector for X11/Wayland.
 *
 * Chooses the backend automatically based
 * on the session type.
 */
public class KimaiTimerIdleDetector : GLib.Object {

    private bool is_wayland = false;
    private void* detector = null;

    public KimaiTimerIdleDetector() {
        string? session_type = Environment.get_variable("XDG_SESSION_TYPE");

        if (session_type != null && session_type.down() == "wayland") {
            is_wayland = true;
            init_wayland();
        }
        else {
            is_wayland = false;
            init_x11();
        }
    }

    private void init_x11() {
        detector = x11_idle_new();

        if (detector == null) {
            GLib.warning("Unable to initialize X11 idle detector");
        }
    }

    private void init_wayland() {
        detector = wayland_idle_new();

        if (detector == null) {
            GLib.warning("Unable to initialize Wayland idle detector");
        }
    }

    public uint64 get_idle_seconds() {
        if (detector == null) {
            return 0;
        }

        if (is_wayland) {
            return wayland_idle_seconds(detector);
        }

        return x11_idle_seconds(detector);
    }

    public string get_backend_name() {
        if (detector == null) {
            return is_wayland ? "wayland-unavailable" : "x11-unavailable";
        }

        return is_wayland ? "wayland-ext-idle-notify" : "x11-xss";
    }

    ~KimaiTimerIdleDetector() {
        if (detector == null) {
            return;
        }

        if (is_wayland) {
            wayland_idle_free(detector);
        }
        else {
            x11_idle_free(detector);
        }

        detector = null;
    }
}