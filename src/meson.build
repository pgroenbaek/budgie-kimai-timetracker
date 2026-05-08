# Kimai Timetracker Applet build
budgie_dep = dependency('budgie-1.0', required: true)
gtk_dep = dependency('gtk+-3.0')
glib_dep = dependency('glib-2.0')
gettext_dep = dependency('gettext', required: false)
json_glib_dep = dependency('json-glib-1.0', required: true)
soup_dep = dependency('libsoup-2.4', required: true)
secret_dep = dependency('libsecret-1', required: true)

# TODO: Might have to dynamically apply these deps for Budgie <=10.9/10.10+ respectively
cc = meson.get_compiler('c')
x11_dep = dependency('x11')
xext_dep = cc.find_library('Xext', required: true)
xscrnsaver_dep = cc.find_library('Xss', required: true)

applet_kimaitimetracker_sources = [
  'KimaiAPI.vala',
  'KimaiData.vala',
  'KimaiTimerIdleDetector.vala',
  'KimaiTimerManager.vala',
  'KimaiTimetrackerApplet.vala',
  'KimaiTimetrackerSettings.vala',
  'KimaiTimetrackerWindow.vala',
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
  xscrnsaver_dep
]

add_project_arguments(
  '-DGETTEXT_PACKAGE="budgie-kimai-timetracker-applet"',
  '-lX11',
  '-lXext',
  '-lXss',
  language: 'c'
)

shared_library('kimaitimetrackerapplet',
  applet_kimaitimetracker_sources,
  dependencies: applet_kimaitimetracker_deps,
  install: true
)
