const std = @import("std");
const http = std.http;

/// IPv6-enabled HTTP client wrapper
pub const IPv6HttpClient = struct {
    allocator: std.mem.Allocator,
    use_ipv6: bool = false,
    
    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
        };
    }

    pub fn enableIPv6(self: *Self) void {
        self.use_ipv6 = true;
    }

    pub fn disableIPv6(self: *Self) void {
        self.use_ipv6 = false;
    }

    /// Create a new HTTP client with IPv6 support configuration
    pub fn createClient(self: *Self) http.Client {
        var client = http.Client{ .allocator = self.allocator };
        
        // Configure IPv6 if enabled
        if (self.use_ipv6) {
            // Note: In Zig 0.14.1, we need to handle IPv6 at the connection level
            // This is a placeholder for future IPv6 configuration
            // Currently Zig's HTTP client doesn't provide direct IP version control
        }
        
        return client;
    }

    pub fn deinit(self: *Self) void {
        _ = self;
    }

    /// Fetch with IPv6 support (if available in the platform)
    pub fn fetch(self: *Self, options: http.Client.FetchOptions) !http.Client.FetchResult {
        var client = self.createClient();
        defer client.deinit();

        return client.fetch(options);
    }
};

/// Test module for IPv6 functionality
const testing = std.testing;

test "IPv6HttpClient initialization" {
    var ipv6_client = IPv6HttpClient.init(testing.allocator);
    defer ipv6_client.deinit();

    // Test default state (IPv4)
    try testing.expect(!ipv6_client.use_ipv6);

    // Test enabling IPv6
    ipv6_client.enableIPv6();
    try testing.expect(ipv6_client.use_ipv6);

    // Test disabling IPv6
    ipv6_client.disableIPv6();
    try testing.expect(!ipv6_client.use_ipv6);
}

test "IPv6HttpClient client creation" {
    var ipv6_client = IPv6HttpClient.init(testing.allocator);
    defer ipv6_client.deinit();

    // Should create client successfully
    const client = ipv6_client.createClient();
    client.deinit();
}