const std = @import("std");
const Stream = @import("../../../Core/Byte/Stream.zig").Stream;
const TxHello = @import("../../Transmit/Login/Hello.zig");

pub const Hello = struct {
    stream: Stream,
    conn: std.net.Stream,

    pub fn init(allocator: std.mem.Allocator, payload: []const u8, conn: std.net.Stream) !Hello {
        return .{
            .stream = try Stream.initWithBytes(allocator, payload),
            .conn = conn,
        };
    }

    pub fn deinit(self: *Hello) void {
        self.stream.deinit();
    }

    pub fn decode(_: *Hello) !void {}

    pub fn process(self: *Hello) !void {
        var msg = TxHello.Hello.init(self.stream.allocator, self.conn);
        defer msg.deinit();
        try msg.send();
    }
};
