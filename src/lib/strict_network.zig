const std = @import("std");
const http = std.http;
const net = std.net;

/// Strict protocol enforcement at socket level
pub const StrictNetwork = struct {
    allocator: std.mem.Allocator,
    forced_protocol: ?u8 = null,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
        };
    }

    pub fn setProtocol(self: *Self, version: u8) void {
        self.forced_protocol = version;
    }

    /// Create HTTP client with protocol enforcement
    pub fn createHttpClient(self: *Self) !http.Client {
        var client = http.Client{ .allocator = self.allocator };

        if (self.forced_protocol) |version| {
            // Override the connection resolution to enforce protocol
            client.resolve = struct {
                fn resolveWithProtocol(
                    allocator: std.mem.Allocator,
                    name: []const u8,
                    port: u16,
                    family: net.AddressFamily,
                ) !net.Address {
                    _ = family; // Ignore original preference

                    _ = if (version == 6)
                        net.AddressFamily.inet6
                    else
                        net.AddressFamily.inet;

                    const addresses = try net.getAddressList(allocator, name, port);
                    defer addresses.deinit();

                    // Find first address matching the forced protocol
                    for (addresses.addrs) |addr| {
                        if ((version == 6 and addr.any.family == .inet6) or
                            (version == 4 and addr.any.family == .inet))
                        {
                            return addr;
                        }
                    }

                    return error.NoAddressForForcedProtocol;
                }
            }.resolveWithProtocol;
        }

        return client;
    }

    /// Test strict protocol connectivity
    pub fn testConnectivity(self: *Self, test_url: []const u8) !void {
        var client = try self.createHttpClient();
        defer client.deinit();

        const result = client.fetch(.{
            .method = .HEAD,
            .location = .{ .url = test_url },
            .max_append_size = 1024,
            .timeout = 5 * std.time.ms_per_s,
        }) catch |err| {
            std.log.err("Strict protocol {} connectivity failed: {}", .{ self.forced_protocol.?, err });
            return error.ProtocolConnectivityFailed;
        };
        defer result.deinit();

        if (result.status != .ok) {
            return error.ProtocolTestFailed;
        }
    }

    pub fn deinit(self: *Self) void {
        _ = self;
    }
};

/// Test connectivity for specific protocol
pub fn verifyProtocolConnectivity(allocator: std.mem.Allocator, protocol: u8) bool {
    var network = StrictNetwork.init(allocator);
    defer network.deinit();

    network.setProtocol(protocol);

    const test_url = if (protocol == 6)
        "https://ipv6.google.com"
    else
        "https://ipv4.google.com";

    return network.testConnectivity(test_url) catch |err| {
        std.log.debug("Protocol {} verification failed: {}", .{ protocol, err });
        return false;
    };
}

/// Test module
const testing = std.testing;

test "StrictNetwork protocol setting" {
    var network = StrictNetwork.init(testing.allocator);
    defer network.deinit();

    network.setProtocol(6);
    try testing.expect(network.forced_protocol.? == 6);

    network.setProtocol(4);
    try testing.expect(network.forced_protocol.? == 4);
}

test "StrictNetwork client creation" {
    var network = StrictNetwork.init(testing.allocator);
    defer network.deinit();

    network.setProtocol(6);
    const client = try network.createHttpClient();
    client.deinit();
}
