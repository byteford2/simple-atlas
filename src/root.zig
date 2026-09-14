const std = @import("std");
const Io = std.Io;

pub const zigimg = @import("zigimg");

const Vec2i = @Vector(2, u32);
const Vec2f = @Vector(2, f32);

fn loadImageFromPath(gpa: std.mem.Allocator, io: std.Io, path: []u8) !zigimg.Image {
    var read_buffer: [zigimg.io.DEFAULT_BUFFER_SIZE]u8 = undefined;
    const image = try zigimg.Image.fromFilePath(gpa, io, path, read_buffer[0..]);

    return image;
}

fn toFloat(x: anytype) f32 {
    return std.math.lossyCast(f32, x);
}

fn toInt(x: anytype) u32 {
    return std.math.lossyCast(u32, x);
}

fn toInt8(x: anytype) u8 {
    return std.math.lossyCast(u8, x);
}

fn lerpColor(a: anytype, b: @TypeOf(a), t: f32) @TypeOf(a) {
    return .{
        .r = toInt8(std.math.lerp(toFloat(a.r), toFloat(b.r), t)),
        .g = toInt8(std.math.lerp(toFloat(a.g), toFloat(b.g), t)),
        .b = toInt8(std.math.lerp(toFloat(a.b), toFloat(b.b), t)),
        .a = toInt8(std.math.lerp(toFloat(a.a), toFloat(b.a), t)),
    };
}

fn vecIToF(v: Vec2i) Vec2f {
    return .{ toFloat(v[0]), toFloat(v[1]) };
}

fn vecFToI(v: Vec2f) Vec2i {
    return .{ toInt(v[0]), toInt(v[1]) };
}

fn blitScaled(gpa: std.mem.Allocator, src: *zigimg.Image, dst: zigimg.Image, new_size: Vec2i, offset: Vec2i) !void {
    // Bilinear scaling
    const offset_f = vecIToF(offset);
    const new_size_f = vecIToF(new_size);
    const old_size_f: Vec2f = .{ toFloat(src.width), toFloat(src.height) };
    const scale: Vec2f = old_size_f / new_size_f;

    try src.convert(gpa, .rgba32);

    for (offset[1]..offset[1] + new_size[1]) |y| {
        for (offset[0]..offset[0] + new_size[0]) |x| {
            const dst_position: Vec2f = .{ toFloat(x), toFloat(y) };
            const src_position = (dst_position - offset_f) * scale;

            const top_left = @floor(src_position);
            const top_right: Vec2f = .{ @ceil(src_position[0]), @floor(src_position[1]) };
            const bottom_left: Vec2f = .{ @floor(src_position[0]), @ceil(src_position[1]) };
            const bottom_right = @ceil(src_position);

            const rightness = src_position[0] - top_left[0];
            const bottomness = src_position[1] - top_left[1];

            const top_left_index = toInt(top_left[0]) + toInt(top_left[1]) * src.width;
            const bottom_left_index = toInt(bottom_left[0]) + toInt(bottom_left[1]) * src.width;

            const left_average = lerpColor(
                src.pixels.rgba32[std.math.clamp(top_left_index, 0, src.pixels.rgba32.len - 1)],
                src.pixels.rgba32[std.math.clamp(bottom_left_index, 0, src.pixels.rgba32.len - 1)],
                bottomness,
            );

            const top_right_index = toInt(top_right[0]) + toInt(top_right[1]) * src.width;
            const bottom_right_index = toInt(bottom_right[0]) + toInt(bottom_right[1]) * src.width;

            const right_average = lerpColor(
                src.pixels.rgba32[std.math.clamp(top_right_index, 0, src.pixels.rgba32.len - 1)],
                src.pixels.rgba32[std.math.clamp(bottom_right_index, 0, src.pixels.rgba32.len - 1)],
                bottomness,
            );

            const average = lerpColor(left_average, right_average, rightness);

            dst.pixels.rgba32[x + y * dst.width] = average;
        }
    }
}

fn loadAndBlitToAtlas(gpa: std.mem.Allocator, io: std.Io, index: u32, path: []u8, atlas: zigimg.Image, target_size: Vec2i, padding: u32) !void {
    var image = try loadImageFromPath(gpa, io, path);
    defer image.deinit(gpa);

    const target_position = indexToAtlasPosition(index, target_size, .{ @intCast(atlas.width), @intCast(atlas.height) }, padding);
    try blitScaled(gpa, &image, atlas, target_size, target_position);
}

fn loadAndBlitToAtlasInfallible(gpa: std.mem.Allocator, io: Io, index: u32, path: []u8, atlas: zigimg.Image, target_size: @Vector(2, u32), padding: u32) void {
    loadAndBlitToAtlas(gpa, io, index, path, atlas, target_size, padding) catch {
        std.log.debug("Error loading/blitting '{s}'", .{path});
    };
}

fn indexToAtlasPosition(index: u32, image_size: Vec2i, atlas_size: Vec2i, padding: u32) Vec2i {
    const effective_image_size = image_size + @as(Vec2i, @splat(padding));
    const useful_atlas_width = atlas_size[0] / effective_image_size[0] * effective_image_size[0];
    const images_per_row = useful_atlas_width / effective_image_size[0];
    const row_index = index / images_per_row;
    const column_index = index % images_per_row;

    const row = row_index * effective_image_size[1];
    const column = column_index * effective_image_size[0];

    return .{ column, row };
}

pub fn buildAtlasFromPaths(gpa: std.mem.Allocator, io: std.Io, paths: [][]u8, atlas_size: Vec2i, sub_size: Vec2i, padding: u32) !zigimg.Image {
    var atlas = try zigimg.Image.create(gpa, atlas_size[0], atlas_size[1], .rgba32);
    errdefer atlas.deinit(gpa);

    var futures: std.ArrayList(Io.Future(void)) = .empty;

    for (paths, 0..) |path, i| {
        try futures.append(gpa, try io.concurrent(loadAndBlitToAtlasInfallible, .{ gpa, io, @intCast(i), path, atlas, sub_size, padding }));
    }

    for (futures.items) |*future| {
        future.await(io);
    }

    return atlas;
}
