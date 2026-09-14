const std = @import("std");
const builtin = @import("builtin");
const Io = std.Io;

const simple_atlas = @import("simple_atlas");
const zigimg = simple_atlas.zigimg;

fn readLine(line_buffer: []u8, input: *std.Io.Reader) ![]u8 {
    // Source - https://stackoverflow.com/a/62077901

    // Posted by Cristobal Montecino, modified by community. See post 'Timeline' for change history

    // Retrieved 2026-09-14, License - CC BY-SA 4.0
    var w: std.Io.Writer = .fixed(line_buffer);

    var line_length = try input.streamDelimiterLimit(&w, '\n', .unlimited);
    std.debug.assert(line_length <= line_buffer.len);

    // Consume the '\n' with takeByte and throw it away
    var next_byte: ?u8 = null;
    if (input.takeByte()) |value| {
        next_byte = value;
    } else |err| switch (err) {
        error.EndOfStream => {
            std.debug.assert(next_byte == null);
        },
        else => return err,
    }
    std.debug.assert(next_byte == '\n' or next_byte == null);

    // Trim \r on windows
    // @see @Sawcce's answer: https://stackoverflow.com/a/75912768/9959510
    // @see https://en.wikipedia.org/wiki/Newline#Representation
    if (builtin.os.tag == .windows) {
        if (line_length > 0) {
            if (next_byte == '\n' and line_buffer[line_length - 1] == '\r') {
                line_length -= 1;
            }
        }
    }

    return line_buffer[0..line_length];
}

fn readNumber(line_buffer: []u8, input: *std.Io.Reader) !u32 {
    return std.fmt.parseInt(u32, try readLine(line_buffer, input), 10);
}

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    var allocator: std.heap.DebugAllocator(.{}) = .{};
    const gpa = allocator.allocator();

    var stdin_buffer: [1024]u8 = undefined;
    var stdin = std.Io.File.stdin().reader(io, &stdin_buffer);

    var line_buffer: [1024]u8 = undefined;

    // Read in arguments
    const atlas_width = try readNumber(line_buffer[0..], &stdin.interface);
    const atlas_height = try readNumber(line_buffer[0..], &stdin.interface);

    const image_width = try readNumber(line_buffer[0..], &stdin.interface);
    const image_height = try readNumber(line_buffer[0..], &stdin.interface);

    var paths: std.ArrayList([]u8) = .empty;
    defer paths.deinit(gpa);

    while (readLine(line_buffer[0..], &stdin.interface)) |line| {
        if (line.len == 0) break;
        try paths.append(gpa, line);
    } else |_| {}

    const image = try simple_atlas.buildAtlasFromPaths(gpa, io, paths.items, .{ atlas_width, atlas_height }, .{ image_width, image_height });

    var write_buffer: [zigimg.io.DEFAULT_BUFFER_SIZE]u8 = undefined;
    try image.writeToFilePath(gpa, io, "atlas.png", write_buffer[0..], .{ .png = .{} });
}
