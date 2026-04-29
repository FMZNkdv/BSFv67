const std = @import("std");

pub const Stream = struct {
    allocator: std.mem.Allocator,
    buffer: std.ArrayListUnmanaged(u8),
    offset: usize,
    bitOffset: u4,

    pub fn init(allocator: std.mem.Allocator) Stream {
        return .{
            .allocator = allocator,
            .buffer = .{},
            .offset = 0,
            .bitOffset = 0,
        };
    }

    pub fn initWithBytes(allocator: std.mem.Allocator, data: []const u8) !Stream {
        var self = init(allocator);
        try self.buffer.appendSlice(allocator, data);
        return self;
    }

    pub fn deinit(self: *Stream) void {
        self.buffer.deinit(self.allocator);
    }

    pub fn readInt(self: *Stream) i32 {
        self.bitOffset = 0;
        const val = std.mem.readInt(i32, self.buffer.items[self.offset..][0..4], .big);
        self.offset += 4;
        return val;
    }

    pub fn readShort(self: *Stream) i16 {
        self.bitOffset = 0;
        const val = std.mem.readInt(i16, self.buffer.items[self.offset..][0..2], .big);
        self.offset += 2;
        return val;
    }

    pub fn readString(self: *Stream) ![]u8 {
        const length = self.readInt();
        if (length <= 0 or length >= 90_000)
            return try self.allocator.dupe(u8, "");
        const ulen: usize = @intCast(length);
        const result = try self.allocator.dupe(
            u8,
            self.buffer.items[self.offset .. self.offset + ulen],
        );
        self.offset += ulen;
        return result;
    }

    pub fn readVInt(self: *Stream) i32 {
        self.bitOffset = 0;
        var result: u32 = 0;
        var shift: u6 = 0;

        var b: u32 = self.buffer.items[self.offset];
        self.offset += 1;

        const a1: u32 = (b & 0x40) >> 6;
        const a2: u32 = (b & 0x80) >> 7;
        const s: u32 = (b << 1) & 0x7E;
        b = s | (a2 << 7) | a1;

        result |= (b & 0x7F) << @as(u5, @truncate(shift));
        shift += 7;

        while ((b & 0x80) != 0) {
            if (shift > 28) break;
            b = self.buffer.items[self.offset];
            self.offset += 1;
            result |= (b & 0x7F) << @as(u5, @truncate(shift));
            shift += 7;
        }

        const r: i32 = @bitCast(result);
        return (r >> 1) ^ (-(r & 1));
    }

    pub fn readBoolean(self: *Stream) bool {
        return self.readVInt() >= 1;
    }

    pub fn readLogicLong(self: *Stream) [2]i32 {
        return .{ self.readVInt(), self.readVInt() };
    }

    pub fn readLong(self: *Stream) [2]i32 {
        return .{ self.readInt(), self.readInt() };
    }

    pub fn readDataReference(self: *Stream) [2]i32 {
        const a = self.readVInt();
        return .{ a, if (a == 0) 0 else self.readVInt() };
    }

    pub fn writeByte(self: *Stream, value: u8) !void {
        self.bitOffset = 0;
        try self.buffer.append(self.allocator, value);
        self.offset += 1;
    }

    pub fn writeShort(self: *Stream, value: i16) !void {
        self.bitOffset = 0;
        var b: [2]u8 = undefined;
        std.mem.writeInt(i16, &b, value, .big);
        try self.buffer.appendSlice(self.allocator, &b);
        self.offset += 2;
    }

    pub fn writeInt(self: *Stream, value: i32) !void {
        self.bitOffset = 0;
        var b: [4]u8 = undefined;
        std.mem.writeInt(i32, &b, value, .big);
        try self.buffer.appendSlice(self.allocator, &b);
        self.offset += 4;
    }

    pub fn writeVInt(self: *Stream, value: i32) !void {
        self.bitOffset = 0;
        var v: u32 = @bitCast(value);

        const flippedSigned: i32 = value ^ (value >> 31);
        var flipped: u32 = @bitCast(flippedSigned);

        var temp: u32 = (v >> 25) & 0x40;
        temp |= v & 0x3F;
        v >>= 6;
        flipped >>= 6;

        if (flipped == 0) {
            try self.writeByte(@truncate(temp));
            return;
        }

        try self.writeByte(@truncate(temp | 0x80));
        flipped >>= 7;

        var r: u32 = if (flipped != 0) 0x80 else 0;
        try self.writeByte(@truncate((v & 0x7F) | r));
        v >>= 7;

        while (flipped != 0) {
            flipped >>= 7;
            r = if (flipped != 0) 0x80 else 0;
            try self.writeByte(@truncate((v & 0x7F) | r));
            v >>= 7;
        }
    }

    pub fn writeBoolean(self: *Stream, value: bool) !void {
        if (self.bitOffset == 0) {
            try self.buffer.append(self.allocator, 0);
            self.offset += 1;
        }
        if (value) {
            self.buffer.items[self.offset - 1] |=
                @as(u8, 1) << @as(u3, @truncate(self.bitOffset));
        }
        self.bitOffset = @truncate((self.bitOffset + 1) & 7);
    }

    pub fn writeString(self: *Stream, value: ?[]const u8) !void {
        if (value) |str| {
            if (str.len > 90_000) {
                try self.writeInt(-1);
                return;
            }
            try self.writeInt(@intCast(str.len));
            try self.buffer.appendSlice(self.allocator, str);
            self.offset += str.len;
        } else {
            try self.writeInt(-1);
        }
    }

    pub fn writeStringVInt(self: *Stream, value: ?[]const u8) !void {
        if (value) |str| {
            try self.writeVInt(@intCast(str.len));
            try self.buffer.appendSlice(self.allocator, str);
            self.offset += str.len;
        } else {
            try self.writeVInt(0);
        }
    }

    pub fn writeLong(self: *Stream, v1: i32, v2: i32) !void {
        try self.writeInt(v1);
        try self.writeInt(v2);
    }

    pub fn writeLongLong(self: *Stream, value: i64) !void {
        try self.writeInt(@as(i32, @truncate(value >> 32)));
        try self.writeInt(@as(i32, @truncate(value)));
    }

    pub fn writeLogicLong(self: *Stream, v1: i32, v2: i32) !void {
        try self.writeVInt(v1);
        try self.writeVInt(v2);
    }

    pub fn writeDataReference(self: *Stream, v1: i32, v2: i32) !void {
        if (v1 < 1) {
            try self.writeVInt(0);
        } else {
            try self.writeVInt(v1);
            try self.writeVInt(v2);
        }
    }

    pub fn writeBytes(self: *Stream, data: ?[]const u8) !void {
        if (data) |buf| {
            try self.writeInt(@intCast(buf.len));
            try self.buffer.appendSlice(self.allocator, buf);
            self.offset += buf.len;
        } else {
            try self.writeInt(-1);
        }
    }

    pub fn writeHex(self: *Stream, hex: []const u8) !void {
        if (hex.len % 2 != 0) return error.OddHexLength;
        var i: usize = 0;
        while (i < hex.len) : (i += 2) {
            const byte = std.fmt.parseInt(u8, hex[i .. i + 2], 16) catch
                return error.InvalidHexChar;
            try self.buffer.append(self.allocator, byte);
            self.offset += 1;
        }
    }
};

pub const Writer = struct {
    s: *Stream,

    pub fn init(stream: *Stream) Writer {
        return .{ .s = stream };
    }

    pub fn int(w: Writer, v: i32) void {
        w.s.writeInt(v) catch unreachable;
    }
    pub fn short(w: Writer, v: i16) void {
        w.s.writeShort(v) catch unreachable;
    }
    pub fn byte(w: Writer, v: u8) void {
        w.s.writeByte(v) catch unreachable;
    }
    pub fn vint(w: Writer, v: i32) void {
        w.s.writeVInt(v) catch unreachable;
    }
    pub fn str(w: Writer, v: ?[]const u8) void {
        w.s.writeString(v) catch unreachable;
    }
    pub fn strVInt(w: Writer, v: ?[]const u8) void {
        w.s.writeStringVInt(v) catch unreachable;
    }
    pub fn long(w: Writer, a: i32, b: i32) void {
        w.s.writeLong(a, b) catch unreachable;
    }
    pub fn logicLong(w: Writer, a: i32, b: i32) void {
        w.s.writeLogicLong(a, b) catch unreachable;
    }
    pub fn boolean(w: Writer, v: bool) void {
        w.s.writeBoolean(v) catch unreachable;
    }
    pub fn hex(w: Writer, v: []const u8) void {
        w.s.writeHex(v) catch unreachable;
    }
    pub fn bytes(w: Writer, v: ?[]const u8) void {
        w.s.writeBytes(v) catch unreachable;
    }
    pub fn dataRef(w: Writer, a: i32, b: i32) void {
        w.s.writeDataReference(a, b) catch unreachable;
    }
};
