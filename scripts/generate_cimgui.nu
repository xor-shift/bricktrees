def main [cimgui_path: string, imconfig: string, output_path: string, ...rest] {
    print -e "asdasdasd"
    print -e $"($cimgui_path)"
    print -e $"($imconfig)"
    print -e $"($output_path)"
    print -e "asdasdasd"

    cd $cimgui_path

    cp cimgui.cpp cimgui.cpp.bak
    cp cimgui.h cimgui.h.bak

    cd generator
    cp -r output output_bak

    luajit generator.lua gcc "internal noimstrv" $"-DIMGUI_USER_CONFIG=\"($imconfig)\""

    # sic.
    rm preprocesed.h
    rm -r output
    mv output_bak output

    cd ..
    cp cimgui.cpp $output_path
    cp cimgui.h $output_path
    cp -r imgui $output_path

    cp $imconfig $output_path

    mv cimgui.cpp.bak cimgui.cpp
    mv cimgui.h.bak cimgui.h
}

