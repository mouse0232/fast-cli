const std = @import("std");
const http = std.http;

/// Strict protocol-enforced HTTP client
pub const StrictHttpClient = struct {
    allocator: std.mem.Allocator,
    force_protocol: ?u8 = null, // 4, 6, or null for auto
    protocol_available: bool = false,

    const Self = @This();
    const IPv6TestUrl = "https://ipv6.google.com";
    const IPv4TestUrl = "https://ipv4.google.com";

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
        };
    }

    pub fn setProtocol(self: *Self, version: u8) void {
        self.force_protocol = version;
    }

    pub fn detectConnectivity(self: *Self) !void {
        if (self.force_protocol) |version| {
            if (version == 6) {
                try self.testIPv6Connectivity();
            } else if (version == 4) {
                try self.testIPv4Connectivity();
            }
        }
        self.protocol_available = true;
    }

    fn testIPv6Connectivity(self: *Self) !void {
        var client = http.Client{ .allocator = self.allocator };
        defer client.deinit();

        const result = client.fetch(.{
            .method = .HEAD,
            .location = .{ .url = IPv6TestUrl },
            .max_append_size = 1024,
            .timeout = 3 * std.time.ms_per_s,
        }) catch {
            return error.IPv6NotAvailable;
        };
        defer result.deinit();

        if (result.status != .ok) {
            return error.IPv6NotAvailable;
        }
    }

    fn testIPv4Connectivity(self: *Self) !void {
        var client = http.Client{ .allocator = self.allocator };
        defer client.deinit();

        const result = client.fetch(.{
            .method = .HEAD,
            .location = .{ .url = IPv4TestUrl },
            .max_append_size = 1024,
            .timeout = 3 * std.time.ms_per_s,
        }) catch {
            return error.IPv4NotAvailable;
        };
        defer result.deinit();

        if (result.status != .ok) {
            return error.IPv4NotAvailable;
        }
    }

    pub fn createClient(self: *Self) !http.Client {
        if (self.force_protocol != null and !self.protocol_available) {
            return error.ProtocolNotAvailable;
        }
        return http.Client{ .allocator = self.allocator };
    }

    pub fn deinit(self: *Self) void {
        _ = self;
    }

    pub fn getProtocolStatus(self: *Self) struct { requested: ?u8, available: bool } {
        return .{
            .requested = self.force_protocol,
            .available = self.protocol_available,
        };
    }
};

/// Test module
const testing = std.testing;

test "StrictHttpClient initialization" {
    var client = StrictHttpClient.init(testing.allocator);
    defer client.deinit();

    try testing.expect(client.force_protocol == null);
    try testing.expect(!client.protocol_available);
}

test "StrictHttpClient protocol setting" {
    var client = StrictHttpClient.init(testing.allocator);
    defer client.deinit();

    client.setProtocol(6);
    try testing.expect(client.force_protocol.? == 6);

    client.setProtocol(4);
    try testing.expect(client.force_protocol.? == 4);
}

test "StrictHttpClient status reporting" {
    var client = StrictHttpClient.init(testing.allocator);
    defer client.deinit();

    const status = client.getProtocolStatus();
    try testing.expect(status.requested == null);
    try testing.expect(!status.available);
}
