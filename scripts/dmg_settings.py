# The disk image's window, for dmgbuild (run by scripts/make_dmg.sh): Plinth
# in the ensō on the left, Applications on the right, on the rice paper
# drawn by tools/draw_dmg_background.py. The positions match the drawing.
app = defines["app"]  # noqa: F821, dmgbuild passes -D values in `defines`

format = "UDZO"
filesystem = "HFS+"
files = [app]
symlinks = {"Applications": "/Applications"}

background = defines["background"]  # noqa: F821
window_rect = ((200, 200), (640, 428))  # the background, plus the title bar
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
icon_size = 96
text_size = 13
icon_locations = {
    "Plinth.app": (180, 186),
    "Applications": (460, 186),
}
