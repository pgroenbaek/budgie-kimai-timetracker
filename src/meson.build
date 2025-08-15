# Kimai Timetracker Applet build
budgie_dep = dependency('budgie-1.0', required: true)
gtk_dep = dependency('gtk+-3.0')
glib_dep = dependency('glib-2.0')
gettext_dep = dependency('gettext', required: false)

applet_kimaitimetracker_sources = [
  'WebcamWhitebalanceApplet.vala',
  'WebcamWhitebalanceSettings.vala',
  'WebcamWhitebalanceWindow.vala',
]

applet_kimaitimetracker_deps = [
  budgie_dep,
  gtk_dep,
  glib_dep,
  gettext_dep,
]

add_project_arguments('-DGETTEXT_PACKAGE="budgie-kimai-timetracker-applet"', language: 'c')

shared_library('kimaitimetrackerapplet',
  applet_kimaitimetracker_sources,
  dependencies: applet_kimaitimetracker_deps,
  install: true
)