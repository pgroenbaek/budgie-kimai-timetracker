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
 
#include "x11-idle-detector.h"

#include <X11/Xlib.h>
#include <X11/extensions/scrnsaver.h>

#include <stdint.h>
#include <stdlib.h>


struct X11IdleDetector
{
    Display* display;
    Window root;
    XScreenSaverInfo* info;
};

X11IdleDetector* x11_idle_new(void)
{
    X11IdleDetector* detector = calloc(1, sizeof(X11IdleDetector));

    if (detector == NULL) {
        return NULL;
    }

    detector->display = XOpenDisplay(NULL);

    if (detector->display == NULL) {
        free(detector);
        return NULL;
    }

    detector->root = XDefaultRootWindow(detector->display);
    detector->info = XScreenSaverAllocInfo();

    if (detector->info == NULL) {
        XCloseDisplay(detector->display);

        free(detector);
        return NULL;
    }

    return detector;
}

void x11_idle_free(X11IdleDetector* detector)
{
    if (detector == NULL) {
        return;
    }

    if (detector->info != NULL) {
        XFree(detector->info);
        detector->info = NULL;
    }

    if (detector->display != NULL) {
        XCloseDisplay(detector->display);
        detector->display = NULL;
    }

    free(detector);
}

uint64_t x11_idle_seconds(X11IdleDetector* detector)
{
    if (detector == NULL || detector->display == NULL || detector->info == NULL) {
        return 0;
    }

    if (!XScreenSaverQueryInfo(detector->display, detector->root, detector->info)) {
        return 0;
    }

    return (uint64_t) detector->info->idle / 1000;
}