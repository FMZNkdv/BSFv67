const std = @import("std");
const Stream = @import("../../../Core/Byte/Stream.zig").Stream;
const AuthOk = @import("../../Transmit/Login/AuthOk.zig");
const OwnData = @import("../../Transmit/Home/OwnData.zig");

pub const Auth = struct {
    stream: Stream,
    conn: std.net.Stream,
    highId: i32 = 0,
    lowId: i32 = 0,
    token: []u8 = &[_]u8{},
    major: i32 = 0,
    build: i32 = 0,
    content: i32 = 0,

    pub fn init(allocator: std.mem.Allocator, payload: []const u8, conn: std.net.Stream) !Auth {
        return .{
            .stream = try Stream.initWithBytes(allocator, payload),
            .conn = conn,
        };
    }

    pub fn deinit(self: *Auth) void {
        self.stream.deinit();
    }

    pub fn decode(self: *Auth) !void {
        self.highId = self.stream.readInt();
        self.lowId = self.stream.readInt();
        self.token = try self.stream.readString();
        self.major = self.stream.readVInt();
        self.build = self.stream.readVInt();
        self.content = self.stream.readVInt();
    }

    pub fn process(self: *Auth) !void {
        std.Thread.sleep(2 * std.time.ns_per_s);

        var ok = AuthOk.AuthOk.init(self.stream.allocator, self.conn);
        defer ok.deinit();
        try ok.send();

        var home = OwnData.OwnData.init(self.stream.allocator, self.conn);
        defer home.deinit();
        try home.send();
    }
};
