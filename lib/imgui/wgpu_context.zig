const std = @import("std");

const blas = @import("blas");
const sdl = @import("gfx").sdl;
const wgpu = @import("gfx").wgpu;

const c = @import("root.zig").c;

const Uniforms = @import("root.zig").Uniforms;
const VariableBuffer = @import("variable_buffer.zig");

const make_vec = @import("vec.zig").make_vec;
const Vec = @import("vec.zig").Vec;

const Self = @This();

device: wgpu.Device,
queue: wgpu.Queue,

context: *c.ImGuiContext,

uniform_bgl: wgpu.BindGroupLayout,
texture_bgl: wgpu.BindGroupLayout,
pipeline_layout: wgpu.PipelineLayout,
pipeline: wgpu.RenderPipeline,

uniform_buffer: wgpu.Buffer,
uniform_bg: wgpu.BindGroup,

font_texture: wgpu.Texture,
font_texture_view: wgpu.TextureView,
default_sampler: wgpu.Sampler,
font_texture_bg: wgpu.BindGroup,

vtx_buffer: VariableBuffer,
idx_buffer: VariableBuffer,

pub fn init(device: wgpu.Device, queue: wgpu.Queue) !Self {
    const ctx = c.igCreateContext(null) orelse std.debug.panic("igCreateContext returned null", .{});
    c.igSetCurrentContext(ctx);

    c.igStyleColorsDark(null);

    const io = c.igGetIO();
    var width: c_int = undefined;
    var height: c_int = undefined;
    var pixels: [*c]u8 = undefined;
    var bytes_per_pixel: c_int = undefined;
    c.ImFontAtlas_GetTexDataAsRGBA32(io.*.Fonts, &pixels, &width, &height, &bytes_per_pixel);

    const font_texture = try device.create_texture(wgpu.Texture.Descriptor{
        .label = "imgui font texture",
        .usage = .{ .copy_dst = true, .texture_binding = true },
        .dimension = .D2,
        .format = .RGBA8Unorm,
        .view_formats = &.{.RGBA8Unorm},
        .sampleCount = 1,
        .mipLevelCount = 1,
        .size = .{
            .width = @intCast(width),
            .height = @intCast(height),
            .depth_or_array_layers = 1,
        },
    });
    errdefer font_texture.deinit();
    const font_texture_view = try font_texture.create_view(.{});

    queue.write_texture(wgpu.ImageCopyTexture{
        .texture = font_texture,
    }, pixels[0..@as(usize, @intCast(width * height * 4))], wgpu.Extent3D{
        .width = @intCast(width),
        .height = @intCast(height),
        .depth_or_array_layers = 1,
    }, wgpu.TextureDataLayout{
        .offset = 0,
        .bytes_per_row = @intCast(width * 4),
        .rows_per_image = @intCast(height),
    });

    io.*.BackendFlags |= c.ImGuiBackendFlags_RendererHasVtxOffset;
    io.*.BackendFlags |= c.ImGuiBackendFlags_HasSetMousePos;

    const imgui_shader_source = @embedFile("./imgui.wgsl");
    const imgui_shader = try device.create_shader_module_wgsl("imgui shader", imgui_shader_source);
    errdefer imgui_shader.deinit();

    const imgui_uniform_bgl = try device.create_bind_group_layout(.{
        .label = "imgui uniform bgl",
        .entries = &.{.{
            .binding = 0,
            .visibility = .{ .vertex = true },
            .layout = .{ .Buffer = .{ .type = .Uniform } },
        }},
    });
    errdefer imgui_uniform_bgl.deinit();

    const imgui_texture_bgl = try device.create_bind_group_layout(.{
        .label = "imgui texture bgl",
        .entries = &.{
            wgpu.BindGroupLayout.Entry{
                .binding = 0,
                .visibility = .{ .fragment = true },
                .layout = .{ .Sampler = .{ .type = .Filtering } },
            },
            wgpu.BindGroupLayout.Entry{
                .binding = 1,
                .visibility = .{ .fragment = true },
                .layout = .{ .Texture = .{
                    .sample_type = .Float,
                    .view_dimension = .D2,
                } },
            },
        },
    });
    errdefer imgui_texture_bgl.deinit();

    const imgui_pipeline_layout = try device.create_pipeline_layout(.{
        .label = "imgui pipeline layout",
        .bind_group_layouts = &.{ imgui_uniform_bgl, imgui_texture_bgl },
    });
    errdefer imgui_pipeline_layout.deinit();

    const imgui_pipeline = try device.create_render_pipeline(.{
        .label = "imgui render pipeline",
        .layout = imgui_pipeline_layout,
        .vertex = .{
            .module = imgui_shader,
            .entry_point = "vs_main",
            .buffers = &.{
                wgpu.VertexBufferLayout{
                    .attributes = &.{
                        .{
                            .format = wgpu.VertexFormat.Float32x2,
                            .offset = 0,
                            .shader_location = 0,
                        },
                        .{
                            .format = wgpu.VertexFormat.Float32x2,
                            .offset = 8,
                            .shader_location = 1,
                        },
                        .{
                            .format = wgpu.VertexFormat.Uint32,
                            .offset = 16,
                            .shader_location = 2,
                        },
                    },
                    .array_stride = @sizeOf(c.ImDrawVert),
                },
            },
        },
        .fragment = .{
            .module = imgui_shader,
            .entry_point = "fs_main",
            .targets = &.{.{
                .format = wgpu.TextureFormat.BGRA8Unorm,
                .blend = wgpu.BlendState.alpha_blending,
                .write_mask = wgpu.ColorWriteMask{ .red = true, .green = true, .blue = true, .alpha = true },
            }},
        },
        .primitive = .{ .topology = .TriangleList },
        .multisample = .{},
        .depth_stencil = null,
    });
    errdefer imgui_pipeline.deinit();

    const uniform_buffer = try device.create_buffer(.{
        .label = "imgui uniform buffer",
        .size = @sizeOf(Uniforms),
        .usage = .{ .uniform = true, .copy_dst = true },
    });
    errdefer uniform_buffer.deinit();

    const uniform_bg = try device.create_bind_group(wgpu.BindGroup.Descriptor{
        .label = "imgui uniform bind group",
        .layout = imgui_uniform_bgl,
        .entries = &.{
            wgpu.BindGroup.Entry{ .binding = 0, .resource = .{ .Buffer = .{
                .size = @sizeOf(Uniforms),
                .offset = 0,
                .buffer = uniform_buffer,
            } } },
        },
    });
    errdefer uniform_bg.deinit();

    const default_sampler = try device.create_sampler(.{});
    errdefer default_sampler.deinit();

    const font_texture_bg = try device.create_bind_group(wgpu.BindGroup.Descriptor{
        .label = "imgui font texture bind group",
        .layout = imgui_texture_bgl,
        .entries = &.{
            wgpu.BindGroup.Entry{
                .binding = 0,
                .resource = .{ .Sampler = default_sampler },
            },
            wgpu.BindGroup.Entry{
                .binding = 1,
                .resource = .{ .TextureView = font_texture_view },
            },
        },
    });
    errdefer font_texture_bg.deinit();

    var vtx_buffer = try VariableBuffer.init(device, .{
        .label = "imgui vertex buffer",
        .size = 0,
        .usage = .{
            .copy_dst = true,
            .vertex = true,
        },
    });
    errdefer vtx_buffer.deinit();

    var idx_buffer = try VariableBuffer.init(device, .{
        .label = "imgui index buffer",
        .size = 0,
        .usage = .{
            .copy_dst = true,
            .index = true,
        },
    });
    errdefer idx_buffer.deinit();

    return Self{
        .device = device,
        .queue = queue,

        .context = ctx,

        .uniform_bgl = imgui_uniform_bgl,
        .texture_bgl = imgui_texture_bgl,
        .pipeline_layout = imgui_pipeline_layout,
        .pipeline = imgui_pipeline,

        .uniform_buffer = uniform_buffer,
        .uniform_bg = uniform_bg,

        .font_texture = font_texture,
        .font_texture_view = font_texture_view,
        .default_sampler = default_sampler,
        .font_texture_bg = font_texture_bg,

        .vtx_buffer = vtx_buffer,
        .idx_buffer = idx_buffer,
    };
}

pub fn deinit(self: *Self) void {
    self.idx_buffer.buffer.deinit();
    self.vtx_buffer.buffer.deinit();

    self.pipeline.deinit();
    self.pipeline_layout.deinit();
    self.texture_bgl.deinit();
    self.uniform_bgl.deinit();

    c.igDestroyContext(self.context);

    self.* = undefined;
}

pub fn render(self: *Self, encoder: wgpu.CommandEncoder, onto: wgpu.TextureView) !void {
    const io = c.igGetIO();

    const uniforms: Uniforms = .{
        .dimensions = [2]u32{
            @intFromFloat(io.*.DisplaySize.x),
            @intFromFloat(io.*.DisplaySize.y),
        },
    };
    self.queue.write_buffer(self.uniform_buffer, 0, std.mem.asBytes(&uniforms));

    c.igRender();
    const draw_data = (c.igGetDrawData() orelse unreachable)[0];

    const draw_lists = make_vec(draw_data.CmdLists);

    // cheatsheet:
    // reset: \x1b[0m
    // bold : \x1b[1m
    // red  : \x1b[31m (index)
    // green: \x1b[32m (vertex)
    // blue : \x1b[34m (command)
    // magn.: \x1b[35m (draw list)

    std.log.debug( //
        "\x1b[1mImDrawData\x1b[0m: " ++
        "\x1b[31m{d}\x1b[0m idxs, " ++
        "\x1b[32m{d}\x1b[0m vtxs, " ++
        "\x1b[35m{d}\x1b[0m drls", .{
        draw_data.TotalIdxCount,
        draw_data.TotalVtxCount,
        draw_data.CmdListsCount,
    });

    if (draw_data.TotalIdxCount == 0) {
        return;
    }

    try self.idx_buffer.ensure_size(self.device, @as(usize, @intCast(draw_data.TotalIdxCount)) * 4);
    try self.vtx_buffer.ensure_size(self.device, @as(usize, @intCast(draw_data.TotalVtxCount)) * @sizeOf(c.ImDrawVert));

    var global_idx_offset: usize = 0;
    var global_vtx_offset: usize = 0;

    for (0.., draw_lists.items) |draw_list_no, draw_list| {
        const cmd_buffer = make_vec(draw_list.*.CmdBuffer);
        const idx_buffer = make_vec(draw_list.*.IdxBuffer);
        const vtx_buffer = make_vec(draw_list.*.VtxBuffer);

        self.queue.write_buffer(self.idx_buffer.buffer, global_idx_offset * 4, std.mem.sliceAsBytes(idx_buffer.items));
        self.queue.write_buffer(self.vtx_buffer.buffer, global_vtx_offset * @sizeOf(c.ImDrawVert), std.mem.sliceAsBytes(vtx_buffer.items));

        defer global_idx_offset += idx_buffer.items.len;
        defer global_vtx_offset += vtx_buffer.items.len;

        std.log.debug( //
            "  \x1b[1mImDrawList\x1b[0m #\x1b[35m{d}\x1b[0m: " ++
            "\x1b[31m{d}\x1b[0m idxs, " ++
            "\x1b[32m{d}\x1b[0m vtxs, " ++
            "\x1b[34m{d}\x1b[0m cmds", .{
            draw_list_no,
            idx_buffer.items.len,
            vtx_buffer.items.len,
            cmd_buffer.items.len,
        });

        for (0.., cmd_buffer.items) |command_no, command| {
            const idx_offset = global_idx_offset + @as(usize, @intCast(command.IdxOffset));
            const vtx_offset = global_vtx_offset + @as(usize, @intCast(command.VtxOffset));

            std.log.debug("    \x1b[1mImDrawCmd\x1b[0m #\x1b[34m{d}\x1b[0m:", .{command_no});
            std.log.debug("      [\x1b[31m{d} ({d} (g) + {d} (l)), {d}\x1b[0m) (\x1b[31m{d}\x1b[0m total)", .{
                idx_offset,
                global_idx_offset,
                command.IdxOffset,
                (idx_offset + command.ElemCount),
                command.ElemCount,
            });
            std.log.debug("      [\x1b[32m{d} ({d} (g) + {d} (l)), ...\x1b[0m)", .{
                vtx_offset,
                global_vtx_offset,
                command.VtxOffset,
            });
            std.log.debug("      texture #\x1b[1m{d}\x1b[0m", .{command.TextureId});

            const render_pass = try encoder.begin_render_pass(.{
                .label = "imgui render pass",
                .color_attachments = &.{
                    wgpu.RenderPass.ColorAttachment{
                        .view = onto,
                        .load_op = .Load,
                        .store_op = .Store,
                    },
                },
            });

            render_pass.set_pipeline(self.pipeline);
            render_pass.set_bind_group(0, self.uniform_bg, null);
            render_pass.set_bind_group(1, self.font_texture_bg, null);
            render_pass.set_vertex_buffer(0, self.vtx_buffer.buffer, 0, @intCast(self.vtx_buffer.desc.size));
            render_pass.set_index_buffer(self.idx_buffer.buffer, .Uint32, 0, @intCast(self.idx_buffer.desc.size));
            render_pass.set_scissor_rect(
                blas.vec2u(@intFromFloat(command.ClipRect.x), @intFromFloat(command.ClipRect.y)),
                blas.vec2u(
                    @intFromFloat(command.ClipRect.z - command.ClipRect.x),
                    @intFromFloat(command.ClipRect.w - command.ClipRect.y),
                ),
            );

            render_pass.draw_indexed(wgpu.RenderPass.IndexedDrawArgs{
                .first_index = @intCast(idx_offset),
                .index_count = @intCast(command.ElemCount),
                .base_vertex = @intCast(vtx_offset),
                .first_instance = 0,
                .instance_count = 1,
            });

            render_pass.end();
            render_pass.deinit();
        }
    }
}
