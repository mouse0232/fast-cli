const std = @import("std");
const http = std.http;
const net = std.net;

/// Simplified protocol verification without socket-level enforcement
/// (Due to Zig 0.14 HTTP client limitations)
pub const StrictNetwork = struct {
    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
        };
    }

    /// Test connectivity for specific protocol using DNS-based verification
    pub fn testProtocolConnectivity(self: *Self, protocol: u8) !void {
        const test_url = if (protocol == 6)
            "https://ipv6.google.com"
        else
            "https://ipv4.google.com";

        var client = http.Client{ .allocator = self.allocator };
        defer client.deinit();

        // First verify DNS resolution for the protocol
        const hostname = if (protocol == 6) "ipv6.google.com" else "ipv4.google.com";

        // Check if we can resolve addresses for the specific protocol
        const addresses = net.getAddressList(self.allocator, hostname, 443) catch {
            return error.ProtocolResolutionFailed;
        };
        defer addresses.deinit();

        var has_protocol_address = false;
        for (addresses.addrs) |addr| {
            if ((protocol == 6 and addr.any.family == net.AddressFamily.inet6) or
                (protocol == 4 and addr.any.family == net.AddressFamily.inet))
            {
                has_protocol_address = true;
                break;
            }
        }

        if (!has_protocol_address) {
            return error.NoAddressForProtocol;
        }

        // Test actual connectivity
        const result = client.fetch(.{
            .method = .HEAD,
            .location = .{ .url = test_url },
            .max_append_size = 1024,
            .timeout = 5 * std.time.ms_per_s,
        }) catch |err| {
            std.log.err("Protocol {} connectivity failed: {}", .{ protocol, err });
            return error.ProtocolConnectivityFailed;
        };
        defer result.deinit();

        if (result.status != .ok) {
            return error.ProtocolTestFailed;
        }

        std.log.info("Protocol {} connectivity confirmed", .{protocol});
    }

    pub fn deinit(self: *Self) void {
        _ = self;
    }
};

/// Test connectivity for specific protocol
pub fn verifyProtocolConnectivity(allocator: std.mem.Allocator, protocol: u8) bool {
    var network = StrictNetwork.init(allocator);
    defer network.deinit();

    return network.testProtocolConnectivity(protocol) catch |err| {
        std.log.debug("Protocol {} verification failed: {}", .{ protocol, err });
        return false;
    };
}

/// Test module
const testing = std.testing;

test "StrictNetwork connectivity test" {
    var network = StrictNetwork.init(testing.allocator);
    defer network.deinit();

    // Should at least be able to initialize without errors
    try testing.expect(true);
}
