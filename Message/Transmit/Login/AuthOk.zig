const std = @import("std");
const Piranha = @import("../../../Core/Piranha.zig").Piranha;
const Stream = @import("../../../Core/Byte/Stream.zig");

pub const AuthOk = struct {
    msg: Piranha,

    pub fn init(allocator: std.mem.Allocator, conn: std.Io.net.Stream, io: std.Io) AuthOk {
        return .{ .msg = Piranha.init(allocator, 20104, 1, conn, io) };
    }

    pub fn deinit(self: *AuthOk) void {
        self.msg.deinit();
    }

    pub fn encode(self: *AuthOk) void {
        const w = Stream.Writer.init(&self.msg.stream);
        const ts = std.Io.Timestamp.now(self.msg.io, .real).toMilliseconds();
        var tsBuf: [24]u8 = undefined;
        const tsStr = std.fmt.bufPrint(&tsBuf, "{d}", .{ts}) catch "";
        w.long(0, 1);
        w.long(0, 1);
        w.str("psinatoken");
        w.str(null);
        w.str(null);
        w.int(67);
        w.int(264);
        w.int(1);
        w.str("prod");
        w.int(0);
        w.int(0);
        w.int(1);
        w.str("");
        w.str(tsStr);
        w.str(tsStr);
    }

    pub fn send(self: *AuthOk) !void {
        self.encode();
        try self.msg.send();
    }
};
