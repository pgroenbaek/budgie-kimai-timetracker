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

#include "wayland-idle-detector.h"
#include "ext-idle-notify-v1-client-protocol.h"

#include <wayland-client.h>

#include <pthread.h>
#include <stdatomic.h>
#include <stdint.h>
#include <stdbool.h>
#include <string.h>
#include <stdlib.h>
#include <unistd.h>
#include <poll.h>
#include <time.h>
#include <errno.h>


struct WaylandIdleDetector
{
    struct wl_display *display;
    struct wl_registry *registry;
    struct wl_seat *seat;

    struct ext_idle_notifier_v1 *notifier;
    struct ext_idle_notification_v1 *notification;

    uint32_t notifier_version;

    pthread_t thread;

    int wake_pipe[2];

    atomic_bool stop;

    atomic_uint_fast64_t idle_since_us;
};


static uint64_t monotonic_us(void)
{
    struct timespec ts;

    clock_gettime(CLOCK_MONOTONIC, &ts);

    return ((uint64_t)ts.tv_sec * 1000000ULL) + ((uint64_t)ts.tv_nsec / 1000ULL);
}


static void registry_global(
    void *data,
    struct wl_registry *registry,
    uint32_t name,
    const char *interface,
    uint32_t version)
{
    struct WaylandIdleDetector *s = (struct WaylandIdleDetector *) data;

    if (strcmp(interface, "wl_seat") == 0) {
        if (s->seat == NULL) {
            s->seat = wl_registry_bind(
                registry,
                name,
                &wl_seat_interface,
                1
            );
        }

        return;
    }

    if (strcmp(interface, "ext_idle_notifier_v1") == 0) {
        if (s->notifier == NULL) {
            uint32_t bind_version = version;

            if (bind_version > 2) {
                bind_version = 2;
            }

            s->notifier_version = bind_version;

            s->notifier = wl_registry_bind(
                registry,
                name,
                &ext_idle_notifier_v1_interface,
                bind_version
            );
        }

        return;
    }
}

static void registry_global_remove(void *data, struct wl_registry *registry, uint32_t name)
{
    (void) data;
    (void) registry;
    (void) name;
}

static const struct wl_registry_listener registry_listener = {
    .global = registry_global,
    .global_remove = registry_global_remove
};

static void idle_idled(void *data, struct ext_idle_notification_v1 *notification)
{
    struct WaylandIdleDetector *s = (struct WaylandIdleDetector *) data;

    (void) notification;

    atomic_store_explicit(&s->idle_since_us, monotonic_us(), memory_order_release);
}

static void idle_resumed(void *data, struct ext_idle_notification_v1 *notification)
{
    struct WaylandIdleDetector *s = (struct WaylandIdleDetector *) data;

    (void) notification;

    atomic_store_explicit(&s->idle_since_us, 0, memory_order_release);
}

static const struct ext_idle_notification_v1_listener idle_listener = {
    .idled = idle_idled,
    .resumed = idle_resumed
};

static void destroy_wayland_connection(struct WaylandIdleDetector *s)
{
    atomic_store_explicit(&s->idle_since_us, 0, memory_order_release);

    if (s->notification != NULL) {
        ext_idle_notification_v1_destroy(s->notification);
        s->notification = NULL;
    }

    if (s->notifier != NULL) {
        ext_idle_notifier_v1_destroy(s->notifier);
        s->notifier = NULL;
    }

    if (s->seat != NULL) {
        wl_seat_destroy(s->seat);
        s->seat = NULL;
    }

    if (s->registry != NULL) {
        wl_registry_destroy(s->registry);
        s->registry = NULL;
    }

    if (s->display != NULL) {
        wl_display_disconnect(s->display);
        s->display = NULL;
    }

    s->notifier_version = 0;
}

static bool setup_wayland_connection(struct WaylandIdleDetector *s)
{
    s->display = wl_display_connect(NULL);

    if (s->display == NULL) {
        return false;
    }

    s->registry = wl_display_get_registry(s->display);

    if (s->registry == NULL) {
        destroy_wayland_connection(s);
        return false;
    }

    if (wl_registry_add_listener(s->registry, &registry_listener, s) < 0) {
        destroy_wayland_connection(s);
        return false;
    }

    /*
     * Receive all globals.
     */
    if (wl_display_roundtrip(s->display) < 0) {
        destroy_wayland_connection(s);
        return false;
    }

    if (s->seat == NULL || s->notifier == NULL) {
        destroy_wayland_connection(s);
        return false;
    }

    /*
     * 1 millisecond notification.
     *
     * Protocol v2:
     *     get_input_idle_notification()
     *
     * Protocol v1 fallback:
     *     get_idle_notification()
     */
    if (s->notifier_version >= 2) {
        s->notification = ext_idle_notifier_v1_get_input_idle_notification(
            s->notifier,
            1,
            s->seat
        );
    }
    else {
        s->notification = ext_idle_notifier_v1_get_idle_notification(
            s->notifier,
            1,
            s->seat
        );
    }

    if (s->notification == NULL) {
        destroy_wayland_connection(s);
        return false;
    }

    if (ext_idle_notification_v1_add_listener(s->notification, &idle_listener, s) < 0) {
        destroy_wayland_connection(s);
        return false;
    }

    /*
     * Force the request through and receive the
     * initial notification state.
     */
    if (wl_display_roundtrip(s->display) < 0) {
        destroy_wayland_connection(s);
        return false;
    }

    return true;
}


static void* wayland_thread_main(void *data)
{
    struct WaylandIdleDetector *s = (struct WaylandIdleDetector *) data;

    while (!atomic_load_explicit(&s->stop, memory_order_acquire)){
        if (!setup_wayland_connection(s)) {
            struct timespec delay = {
                .tv_sec = 0,
                .tv_nsec = 250000000
            };

            nanosleep(&delay, NULL);

            continue;
        }

        int wayland_fd = wl_display_get_fd(s->display);

        while (!atomic_load_explicit(&s->stop, memory_order_acquire)) {
            struct pollfd fds[2];

            fds[0].fd = wayland_fd;
            fds[0].events = POLLIN;
            fds[0].revents = 0;

            fds[1].fd = s->wake_pipe[0];
            fds[1].events = POLLIN;
            fds[1].revents = 0;

            if (wl_display_flush(s->display) < 0) {
                if (errno != EAGAIN) {
                    break;
                }
            }

            int ret = poll(fds, 2, -1);

            if (ret < 0) {
                if (errno == EINTR) {
                    continue;
                }

                break;
            }

            /*
             * Destructor woke us up.
             */
            if (fds[1].revents & POLLIN) {
                char buf[16];

                (void) read(s->wake_pipe[0], buf, sizeof(buf));

                break;
            }

            if (fds[0].revents & (POLLERR | POLLHUP | POLLNVAL)) {
                break;
            }

            if (fds[0].revents & POLLIN) {
                if (wl_display_dispatch(s->display) < 0) {
                    break;
                }
            }
        }

        destroy_wayland_connection(s);
    }

    return NULL;
}

WaylandIdleDetector* wayland_idle_new(void)
{
    struct WaylandIdleDetector *s = calloc(1, sizeof(*s));

    if (s == NULL) {
        return NULL;
    }

    s->wake_pipe[0] = -1;
    s->wake_pipe[1] = -1;

    atomic_init(&s->stop, false);
    atomic_init(&s->idle_since_us, 0);

    if (pipe(s->wake_pipe) < 0) {
        free(s);
        return NULL;
    }

    if (pthread_create(&s->thread, NULL, wayland_thread_main, s) != 0) {
        close(s->wake_pipe[0]);
        close(s->wake_pipe[1]);

        free(s);
        return NULL;
    }

    return s;
}

void wayland_idle_free(WaylandIdleDetector *s)
{
    if (s == NULL) {
        return;
    }

    atomic_store_explicit(&s->stop, true, memory_order_release);

    /*
     * Wake poll().
     */
    char byte = 1;

    (void) write(s->wake_pipe[1], &byte, 1);

    pthread_join(s->thread, NULL);

    if (s->wake_pipe[0] >= 0) {
        close(s->wake_pipe[0]);
    }

    if (s->wake_pipe[1] >= 0) {
        close(s->wake_pipe[1]);
    }

    free(s);
}

uint64_t wayland_idle_seconds(WaylandIdleDetector *s)
{
    if (s == NULL) {
        return 0;
    }

    uint64_t since = atomic_load_explicit(&s->idle_since_us, memory_order_acquire);

    if (since == 0) {
        return 0;
    }

    uint64_t now = monotonic_us();

    if (now <= since) {
        return 0;
    }

    return (now - since) / 1000000ULL;
}