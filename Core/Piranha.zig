const std = @import("std");
const Stream = @import("Byte/Stream.zig").Stream;
const Logger = @import("Logger.zig");

pub const Piranha = struct {
    stream: Stream,
    id: u16,
    version: u16,
    conn: std.net.Stream,

    pub fn init(
        allocator: std.mem.Allocator,
        id: u16,
        version: u16,
        conn: std.net.Stream,
    ) Piranha {
        return .{
            .stream = Stream.init(allocator),
            .id = id,
            .version = version,
            .conn = conn,
        };
    }

    pub fn deinit(self: *Piranha) void {
        self.stream.deinit();
    }

    pub fn send(self: *Piranha) !void {
        if (self.id < 20_000) return;

        const bodyLen = self.stream.buffer.items.len;

        var header: [7]u8 = undefined;
        std.mem.writeInt(u16, header[0..2], self.id, .big);
        header[2] = @truncate((bodyLen >> 16) & 0xFF);
        header[3] = @truncate((bodyLen >> 8) & 0xFF);
        header[4] = @truncate(bodyLen & 0xFF);
        std.mem.writeInt(u16, header[5..7], self.version, .big);

        try self.conn.writeAll(&header);
        try self.conn.writeAll(self.stream.buffer.items);

        Logger.packetOut(self.id, Logger.packetName(self.id), bodyLen);
    }
};
