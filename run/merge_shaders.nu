def merge_shaders [out: string, files: list] {
    cat ...$files | save -f $out
}

def merge_shader [name: string] {
    let shader_files = (ls $"../src/shaders/($name)/" | get name)
    let common_files = (ls ../src/shaders/common/ | get name)
    let all_files = $common_files | append $shader_files

    merge_shaders $"./shaders/($name).wgsl" $all_files
}

merge_shader compute
merge_shader visualiser
merge_shader svo
merge_shader svo_variant
merge_shader voxeliser
