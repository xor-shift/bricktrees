if you are seeing this repo on git, how?
im pushing there so as to not lose work in case i somehow lose my disks

if you are seeing these two lines, i've not yet forked cimgui or otherwise have not made anything to automate the imconfig.h stuff.

you need to cd into `thirdparty/cimgui/generator` and run: `bash generator.sh -c -DIMGUI_USER_CONFIG='"../../../lib/imgui/imconfig.h"'`
