const std = @import("std");
const Io = std.Io;

const zigimg = @import("zigimg");

const Vec2 = @Vector(2, u32);

fn loadImageFromPath(gpa: std.mem.Allocator, io: std.Io, path: []u8) !zigimg.Image {
    var read_buffer: [zigimg.io.DEFAULT_BUFFER_SIZE]u8 = undefined;
    const image = try zigimg.Image.fromFilePath(gpa, io, path, read_buffer[0..]);

    return image;
}

fn blitScaled(src: zigimg.Image, dst: zigimg.Image, new_size: i32, position: Vec2) !void {
    // TODO: Some kind of scaling
}

fn loadAndBlitToAtlas(gpa: std.mem.Allocator, io: std.Io, index: u32, path: []u8, atlas: zigimg.Image, target_size: Vec2) !void {
    const image = try loadImageFromPath(gpa, io, path);
    errdefer image.deinit(gpa);

    const target_position = indexToAtlasPosition(index, target_size, .{ atlas.width, atlas.height });
    try blitScaled(image, atlas, target_size, target_position);
}

fn indexToAtlasPosition(index: u32, image_size: Vec2, atlas_size: Vec2) Vec2 {
    const images_per_row = atlas_size[0] / image_size[0];
    const row_index = index / images_per_row;
    const column_index = index % images_per_row;

    const row = row_index * image_size[1];
    const column = column_index * image_size[0];

    return .{ row, column };
}

pub fn buildAtlasFromPaths(gpa: std.mem.Allocator, io: std.Io, paths: [][]u8, atlas_size: Vec2, sub_size: Vec2) !zigimg.Image {
    var atlas = zigimg.Image.create(gpa, atlas_size[0], atlas_size[1], .rgba32);
    errdefer atlas.deinit(gpa);

    var futures: []Io.AnyFuture = undefined;

    for (paths, 0..) |path, i| {
        futures[i] = io.concurrent(loadAndBlitToAtlas, .{ gpa, io, i, path, atlas, sub_size });
    }

    for (futures, paths) |future, path| {
        future.await() catch blk: {
            std.log.err("Failed to load image from '{s}'", .{path});
            break :blk null;
        };
    }

    return atlas;
}
