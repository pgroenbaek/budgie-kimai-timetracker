# Kimai Timetracker Applet build
budgie_dep = dependency('budgie-1.0', required: true)
gtk_dep = dependency('gtk+-3.0')
glib_dep = dependency('glib-2.0')
gettext_dep = dependency('gettext', required: false)
json_glib_dep = dependency('json-glib-1.0', required: true)

# Try libsoup-3.0 first, fallback to 2.4 if not found
soup_dep = dependency('libsoup-3.0', required: false)
if not soup_dep.found()
    soup_dep = dependency('libsoup-2.4', required: true)
endif

applet_kimaitimetracker_sources = [
  'WebcamWhitebalanceApplet.vala',
  'WebcamWhitebalanceSettings.vala',
  'WebcamWhitebalanceWindow.vala',
  'kimai.vala',
]

applet_kimaitimetracker_deps = [
  budgie_dep,
  gtk_dep,
  glib_dep,
  gettext_dep,
  json_glib_dep,
  soup_dep,
]

add_project_arguments(
  '-DGETTEXT_PACKAGE="budgie-kimai-timetracker-applet"',
  language: 'c'
)

shared_library('kimaitimetrackerapplet',
  applet_kimaitimetracker_sources,
  dependencies: applet_kimaitimetracker_deps,
  install: true
)
