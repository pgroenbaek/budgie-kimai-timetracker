# Kimai Timetracker Applet build
cc = meson.get_compiler('c')

budgie_dep = dependency(budgielib, required: true)
gtk_dep = dependency('gtk+-3.0')
glib_dep = dependency('glib-2.0')
gettext_dep = dependency('gettext', required: false)
json_glib_dep = dependency('json-glib-1.0', required: true)
soup_dep = dependency('libsoup-2.4', required: true)
secret_dep = dependency('libsecret-1', required: true)
x11_dep = dependency('x11')
xext_dep = cc.find_library('Xext', required: true)
xscrnsaver_dep = cc.find_library('Xss', required: true)
wayland_client_dep = dependency('wayland-client')
threads_dep = dependency('threads')

applet_kimaitimetracker_sources = [
  'ext-idle-notify-v1-protocol.c',
  'KimaiAPI.vala',
  'KimaiData.vala',
  'KimaiTimerIdleDetector.vala',
  'KimaiTimerManager.vala',
  'KimaiTimetrackerApplet.vala',
  'KimaiTimetrackerSettings.vala',
  'KimaiTimetrackerWindow.vala',
  'wayland-idle-detector.c',
  'x11-idle-detector.c',
]

applet_kimaitimetracker_deps = [
  budgie_dep,
  gtk_dep,
  glib_dep,
  gettext_dep,
  json_glib_dep,
  soup_dep,
  secret_dep,
  x11_dep,
  xext_dep,
  xscrnsaver_dep,
  wayland_client_dep,
  threads_dep
]

add_project_arguments('--pkg=posix', language: 'vala')
add_project_arguments(
  '-DGETTEXT_PACKAGE="budgie-kimai-timetracker-applet"',
  '-lX11',
  '-lXext',
  '-lXss',
  '-lwayland-client',
  '-lpthread',
  language: 'c'
)

shared_library('kimaitimetrackerapplet',
  applet_kimaitimetracker_sources,
  dependencies: applet_kimaitimetracker_deps,
  install_dir: PLUGINS_INSTALL_DIR,
  install: true
)
