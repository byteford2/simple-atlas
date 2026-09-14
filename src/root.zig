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

fn lerpColor(a: anytype, b: @TypeOf(a), t: f32) @TypeOf(a) {
    return .{
        .r = std.math.lossyCast(u8, std.math.lerp(std.math.lossyCast(f32, a.r), std.math.lossyCast(f32, b.r), t)),
        .g = std.math.lossyCast(u8, std.math.lerp(std.math.lossyCast(f32, a.g), std.math.lossyCast(f32, b.g), t)),
        .b = std.math.lossyCast(u8, std.math.lerp(std.math.lossyCast(f32, a.b), std.math.lossyCast(f32, b.b), t)),
        .a = std.math.lossyCast(u8, std.math.lerp(std.math.lossyCast(f32, a.a), std.math.lossyCast(f32, b.a), t)),
    };
}

fn blitScaled(gpa: std.mem.Allocator, src: *zigimg.Image, dst: zigimg.Image, new_size: Vec2i, offset: Vec2i) !void {
    // Bilinear scaling
    const offset_f: Vec2f = .{ @as(f32, @floatFromInt(offset[0])), @as(f32, @floatFromInt(offset[1])) };
    const new_size_f: Vec2f = .{ @as(f32, @floatFromInt(new_size[0])), @as(f32, @floatFromInt(new_size[1])) };
    const old_size_f: Vec2f = .{ @as(f32, @floatFromInt(src.width)), @as(f32, @floatFromInt(src.height)) };
    const scale: Vec2f = new_size_f / old_size_f;

    try src.convert(gpa, .rgba32);

    for (0..src.height) |y| {
        for (0..src.width) |x| {
            const src_position: Vec2f = .{ @as(f32, @floatFromInt(x)), @as(f32, @floatFromInt(y)) };
            const dst_position = src_position * scale + offset_f;

            const top_left = @floor(dst_position);
            const top_right: Vec2f = .{ @ceil(dst_position[0]), @floor(dst_position[1]) };
            const bottom_left: Vec2f = .{ @floor(dst_position[0]), @ceil(dst_position[1]) };
            const bottom_right = @ceil(dst_position);

            const rightness = dst_position[0] - top_left[0];
            const bottomness = dst_position[1] - top_left[1];

            const left_average = lerpColor(
                src.pixels.rgba32[std.math.lossyCast(u32, top_left[0] + top_left[1]) * src.width],
                src.pixels.rgba32[std.math.lossyCast(u32, bottom_left[0] + bottom_left[1]) * src.width],
                bottomness,
            );

            const right_average = lerpColor(
                src.pixels.rgba32[std.math.lossyCast(u32, top_right[0] + top_right[1]) * src.width],
                src.pixels.rgba32[std.math.lossyCast(u32, bottom_right[0] + bottom_right[1]) * src.width],
                bottomness,
            );

            const average = lerpColor(left_average, right_average, rightness);

            dst.pixels.rgba32[std.math.lossyCast(u32, dst_position[0] + dst_position[1]) * dst.width] = average;
        }
    }
}

fn loadAndBlitToAtlas(gpa: std.mem.Allocator, io: std.Io, index: u32, path: []u8, atlas: zigimg.Image, target_size: Vec2i) !void {
    var image = try loadImageFromPath(gpa, io, path);
    defer image.deinit(gpa);

    const target_position = indexToAtlasPosition(index, target_size, .{ @intCast(atlas.width), @intCast(atlas.height) });
    try blitScaled(gpa, &image, atlas, target_size, target_position);
}

fn loadAndBlitToAtlasInfallible(gpa: std.mem.Allocator, io: Io, index: u32, path: []u8, atlas: zigimg.Image, target_size: @Vector(2, u32)) void {
    loadAndBlitToAtlas(gpa, io, index, path, atlas, target_size) catch {};
}

fn indexToAtlasPosition(index: u32, image_size: Vec2i, atlas_size: Vec2i) Vec2i {
    const images_per_row = atlas_size[0] / image_size[0];
    const row_index = index / images_per_row;
    const column_index = index % images_per_row;

    const row = row_index * image_size[1];
    const column = column_index * image_size[0];

    return .{ row, column };
}

pub fn buildAtlasFromPaths(gpa: std.mem.Allocator, io: std.Io, paths: [][]u8, atlas_size: Vec2i, sub_size: Vec2i) !zigimg.Image {
    var atlas = try zigimg.Image.create(gpa, atlas_size[0], atlas_size[1], .rgba32);
    errdefer atlas.deinit(gpa);

    var futures: std.ArrayList(Io.Future(void)) = .empty;

    for (paths, 0..) |path, i| {
        try futures.append(gpa, try io.concurrent(loadAndBlitToAtlasInfallible, .{ gpa, io, @intCast(i), path, atlas, sub_size }));
    }

    for (futures.items) |*future| {
        future.await(io);
    }

    return atlas;
}
