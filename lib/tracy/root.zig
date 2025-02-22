const c = @cImport({
    @cDefine("TRACY_ENABLE", "");
    @cInclude("tracy/TracyC.h");
});

