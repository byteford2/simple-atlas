const std = @import("std");
const Io = std.Io;

const simple_atlas = @import("simple_atlas");

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const gpa = std.heap.c_allocator;

    // TODO: Read in paths, output path, and sizes; write image to file

    const image = simple_atlas.buildAtlasFromPaths();

    var write_buffer: [zigimg.io.DEFAULT_BUFFER_SIZE]u8 = undefined;
}
