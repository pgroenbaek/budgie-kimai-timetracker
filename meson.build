project(
  'budgie-kimai-timetracker-applet',
  'vala',
  version: '1.0.2',
  default_options: ['warning_level=2']
)

prefix = get_option('prefix')
libdir = join_paths(prefix, get_option('libdir'))
budgielib = get_option('budgielib')
PLUGINS_INSTALL_DIR = join_paths(libdir, 'budgie-desktop', 'plugins', 'budgie-kimai-timetracker')

subdir('src')
subdir('data')