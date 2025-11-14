const std = @import("std");
const zli = @import("zli");
const builtin = @import("builtin");

const Fast = @import("../lib/fast.zig").Fast;
const HTTPSpeedTester = @import("../lib/http_speed_tester_v2.zig").HTTPSpeedTester;

const StabilityCriteria = @import("../lib/http_speed_tester_v2.zig").StabilityCriteria;
const SpeedTestResult = @import("../lib/http_speed_tester_v2.zig").SpeedTestResult;
const BandwidthMeter = @import("../lib/bandwidth.zig");
const SpeedMeasurement = @import("../lib/bandwidth.zig").SpeedMeasurement;
const progress = @import("../lib/progress.zig");
const HttpLatencyTester = @import("../lib/http_latency_tester.zig").HttpLatencyTester;
const log = std.log.scoped(.cli);
const https_flag = zli.Flag{
    .name = "https",
    .description = "Use https when connecting to fast.com",
    .type = .Bool,
    .default_value = .{ .Bool = true },
};

const ipv_flag = zli.Flag{
    .name = "ipv",
    .description = "Specify IP version (4 or 6), default: auto-detect",
    .type = .Int,
    .default_value = .{ .Int = 0 }, // 0 means auto
};

const check_upload_flag = zli.Flag{
    .name = "upload",
    .description = "Check upload speed as well",
    .shortcut = "u",
    .type = .Bool,
    .default_value = .{ .Bool = false },
};

const json_output_flag = zli.Flag{
    .name = "json",
    .description = "Output results in JSON format",
    .shortcut = "j",
    .type = .Bool,
    .default_value = .{ .Bool = false },
};

const max_duration_flag = zli.Flag{
    .name = "duration",
    .description = "Maximum test duration in seconds (uses Fast.com-style stability detection by default)",
    .shortcut = "d",
    .type = .Int,
    .default_value = .{ .Int = 30 },
};

const concurrent_connections_flag = zli.Flag{
    .name = "concurrent",
    .description = "Number of concurrent connections to use (0 for single-threaded mode)",
    .shortcut = "c",
    .type = .Int,
    .default_value = .{ .Int = 8 },
};

pub fn build(allocator: std.mem.Allocator) !*zli.Command {
    const root = try zli.Command.init(allocator, .{
        .name = "fast-cli",
        .description = "Estimate connection speed using fast.com",
        .version = null,
    }, run);

    try root.addFlag(https_flag);
    try root.addFlag(ipv_flag);
    try root.addFlag(check_upload_flag);
    try root.addFlag(json_output_flag);
    try root.addFlag(max_duration_flag);
    try root.addFlag(concurrent_connections_flag);

    return root;
}

fn run(ctx: zli.CommandContext) !void {
    const use_https = ctx.flag("https", bool);
    const ip_version = ctx.flag("ipv", i64);
    const check_upload = ctx.flag("upload", bool);
    const json_output = ctx.flag("json", bool);
    const max_duration = ctx.flag("duration", i64);
    const concurrent_connections = ctx.flag("concurrent", i64);

    log.info("Config: https={}, ip_version={}, upload={}, json={}, max_duration={}s, concurrent_connections={}", .{
        use_https, ip_version, check_upload, json_output, max_duration, concurrent_connections,
    });

    // Configure latency tester
    var latency_tester = HttpLatencyTester.init(std.heap.smp_allocator);
    defer latency_tester.deinit();
    latency_tester.setTestCount(10); // Perform 10 latency tests for stats
    latency_tester.setTimeout(2000); // 2 second timeout per test

    // First verify network connectivity for strict modes
    if (ip_version == 6) {
        std.log.info("Verifying IPv6 connectivity...", .{});
        if (!verifyIPv6Connectivity()) {
            if (!json_output) {
                try ctx.spinner.fail("❌ IPv6 connectivity test failed - your network may not support IPv6", .{});
            } else {
                try outputJson(null, null, null, "IPv6 connectivity test failed");
            }
            return;
        }
        std.log.info("IPv6 connectivity confirmed", .{});
    } else if (ip_version == 4) {
        std.log.info("Verifying IPv4 connectivity...", .{});
        if (!verifyIPv4Connectivity()) {
            if (!json_output) {
                try ctx.spinner.fail("❌ IPv4 connectivity test failed", .{});
            } else {
                try outputJson(null, null, null, "IPv4 connectivity test failed");
            }
            return;
        }
        std.log.info("IPv4 connectivity confirmed", .{});
    }

    var fast = Fast.init(std.heap.smp_allocator, use_https);

    // Strict protocol enforcement
    if (ip_version == 6) {
        fast.enableIPv6();
        std.log.info("Strict IPv6 mode enabled", .{});
    } else if (ip_version == 4) {
        fast.disableIPv6();
        std.log.info("Strict IPv4 mode enabled", .{});
    } // else auto-detect (default behavior)

    defer fast.deinit();

    const urls = fast.get_urls(5) catch |err| {
        if (!json_output) {
            try ctx.spinner.fail("Failed to get URLs: {}", .{err});
        } else {
            const error_msg = switch (err) {
                error.ConnectionTimeout => "Failed to contact fast.com servers",
                else => "Failed to get URLs",
            };
            try outputJson(null, null, null, error_msg);
        }
        return;
    };

    log.info("Got {} URLs", .{urls.len});
    for (urls) |url| {
        log.debug("URL: {s}", .{url});
    }

    // Measure latency with stats
    const latency_stats = if (!json_output) blk: {
        try ctx.spinner.start(.{}, "Measuring latency (10 tests)...", .{});
        const result = latency_tester.measureLatencyStats(urls) catch |err| {
            log.err("Latency test failed: {}", .{err});
            break :blk null;
        };
        break :blk result;
    } else blk: {
        break :blk latency_tester.measureLatencyStats(urls) catch null;
    };

    if (!json_output) {
        try ctx.spinner.start(.{}, "Measuring download speed...", .{});
    }

    // Initialize speed tester with strict protocol enforcement
    var speed_tester = HTTPSpeedTester.init(std.heap.smp_allocator);
    if (ip_version == 6) {
        speed_tester.enableIPv6();
    } else if (ip_version == 4) {
        speed_tester.disableIPv6();
    } // else auto-detect
    
    // Set concurrent connections based on user input
    if (concurrent_connections >= 0) {
        speed_tester.setConcurrentConnections(@as(u32, @intCast(concurrent_connections)));
    }
    
    defer speed_tester.deinit();

    // Add network protocol info to results
    const protocol_info = if (ip_version == 6) "IPv6" else if (ip_version == 4) "IPv4" else "Auto";

    // Use Fast.com-style stability detection by default
    const criteria = StabilityCriteria{
        .ramp_up_duration_seconds = 4,
        .max_duration_seconds = @as(u32, @intCast(@max(25, max_duration))),
        .measurement_interval_ms = 750,
        .sliding_window_size = 6,
        .stability_threshold_cov = 0.15,
        .stable_checks_required = 2,
    };

    const download_result = if (json_output) blk: {
        // JSON mode: clean output only
        break :blk speed_tester.measure_download_speed_stability(urls, criteria) catch |err| {
            log.err("Download test failed: {}", .{err});
            try outputJson(null, null, null, "Download test failed");
            return;
        };
    } else blk: {
        // Interactive mode with spinner updates
        const progressCallback = progress.createCallback(ctx.spinner, updateSpinnerText);
        break :blk speed_tester.measureDownloadSpeedWithStabilityProgress(urls, criteria, progressCallback) catch |err| {
            try ctx.spinner.fail("Download test failed: {}", .{err});
            return;
        };
    };

    var upload_result: ?SpeedTestResult = null;
    if (check_upload) {
        if (!json_output) {
            try ctx.spinner.start(.{}, "Measuring upload speed...", .{});
        }

        upload_result = if (json_output) blk: {
            // JSON mode: clean output only
            break :blk speed_tester.measure_upload_speed_stability(urls, criteria) catch |err| {
                log.err("Upload test failed: {}", .{err});
                const latency_value = if (latency_stats) |stats| stats.meanLatency() else null;
                try outputJson(download_result.speed.value, latency_value, null, "Upload test failed");
                return;
            };
        } else blk: {
            // Interactive mode with spinner updates
            const uploadProgressCallback = progress.createCallback(ctx.spinner, updateUploadSpinnerText);
            break :blk speed_tester.measureUploadSpeedWithStabilityProgress(urls, criteria, uploadProgressCallback) catch |err| {
                try ctx.spinner.fail("Upload test failed: {}", .{err});
                return;
            };
        };
    }
    // Output results with strict protocol info
    if (!json_output) {
        if (latency_stats) |stats| {
            if (upload_result) |up| {
                try ctx.spinner.succeed(
                    \\🔒 Network: {s}
                    \\🏓 Latency: {d:.0}ms (min: {d:.0}ms, max: {d:.0}ms)
                    \\📊 Jitter: {d:.1}ms | 📉 Loss: {d:.1}%
                    \\⬇️ Download: {d:.1} {s} | ⬆️ Upload: {d:.1} {s}
                , .{
                    protocol_info,
                    stats.meanLatency() orelse 0.0,
                    stats.minLatency() orelse 0.0,
                    stats.maxLatency() orelse 0.0,
                    stats.jitter(),
                    stats.packetLossRate(),
                    download_result.speed.value,
                    download_result.speed.unit.toString(),
                    up.speed.value,
                    up.speed.unit.toString(),
                });
            } else {
                try ctx.spinner.succeed(
                    \\🔒 Network: {s}
                    \\🏓 Latency: {d:.0}ms (min: {d:.0}ms, max: {d:.0}ms)
                    \\📊 Jitter: {d:.1}ms | 📉 Loss: {d:.1}%
                    \\⬇️ Download: {d:.1} {s}
                , .{
                    protocol_info,
                    stats.meanLatency() orelse 0.0,
                    stats.minLatency() orelse 0.0,
                    stats.maxLatency() orelse 0.0,
                    stats.jitter(),
                    stats.packetLossRate(),
                    download_result.speed.value,
                    download_result.speed.unit.toString(),
                });
            }
        } else {
            if (upload_result) |up| {
                try ctx.spinner.succeed("🔒 {s} | ⬇️ Download: {d:.1} {s} | ⬆️ Upload: {d:.1} {s}", .{ protocol_info, download_result.speed.value, download_result.speed.unit.toString(), up.speed.value, up.speed.unit.toString() });
            } else {
                try ctx.spinner.succeed("🔒 {s} | ⬇️ Download: {d:.1} {s}", .{ protocol_info, download_result.speed.value, download_result.speed.unit.toString() });
            }
        }
    } else {
        const upload_speed = if (upload_result) |up| up.speed.value else null;

        if (latency_stats) |stats| {
            const latency_ms = stats.meanLatency();
            const jitter_ms = stats.jitter();
            const packet_loss = stats.packetLossRate();
            try outputJsonWithStats(download_result.speed.value, latency_ms, upload_speed, jitter_ms, packet_loss, null);
        } else {
            try outputJsonWithStats(download_result.speed.value, null, upload_speed, null, null, null);
        }
    }
}

/// Update spinner text with current speed measurement
fn updateSpinnerText(spinner: anytype, measurement: SpeedMeasurement) void {
    spinner.updateText("⬇️ {d:.1} {s}", .{ measurement.value, measurement.unit.toString() }) catch {};
}

/// Update spinner text with current upload speed measurement
fn updateUploadSpinnerText(spinner: anytype, measurement: SpeedMeasurement) void {
    spinner.updateText("⬆️ {d:.1} {s}", .{ measurement.value, measurement.unit.toString() }) catch {};
}

fn outputJsonWithStats(
    download_mbps: ?f64,
    ping_ms: ?f64,
    upload_mbps: ?f64,
    jitter_ms: ?f64,
    packet_loss: ?f64,
    error_message: ?[]const u8,
) !void {
    const stdout = std.io.getStdOut().writer();

    var download_buf: [32]u8 = undefined;
    var ping_buf: [32]u8 = undefined;
    var upload_buf: [32]u8 = undefined;
    var jitter_buf: [32]u8 = undefined;
    var loss_buf: [32]u8 = undefined;
    var error_buf: [256]u8 = undefined;

    const download_str = if (download_mbps) |d| try std.fmt.bufPrint(&download_buf, "{d:.1}", .{d}) else "null";
    const ping_str = if (ping_ms) |p| try std.fmt.bufPrint(&ping_buf, "{d:.1}", .{p}) else "null";
    const upload_str = if (upload_mbps) |u| try std.fmt.bufPrint(&upload_buf, "{d:.1}", .{u}) else "null";
    const jitter_str = if (jitter_ms) |j| try std.fmt.bufPrint(&jitter_buf, "{d:.1}", .{j}) else "null";
    const loss_str = if (packet_loss) |l| try std.fmt.bufPrint(&loss_buf, "{d:.1}", .{l}) else "null";
    const error_str = if (error_message) |e| try std.fmt.bufPrint(&error_buf, "\"{s}\"", .{e}) else "null";

    try stdout.print(
        \\{{
        \\  "download_mbps": {s},
        \\  "ping_ms": {s},
        \\  "upload_mbps": {s},
        \\  "jitter_ms": {s},
        \\  "packet_loss": {s},
        \\  "error": {s}
        \\}}
    , .{
        download_str,
        ping_str,
        upload_str,
        jitter_str,
        loss_str,
        error_str,
    });
}

// Backward compatibility for old calls
fn outputJson(download_mbps: ?f64, ping_ms: ?f64, upload_mbps: ?f64, error_message: ?[]const u8) !void {
    try outputJsonWithStats(download_mbps, ping_ms, upload_mbps, null, null, error_message);
}

const StrictNetwork = @import("../lib/strict_network.zig");

// Strict network connectivity verification
fn verifyIPv6Connectivity() bool {
    return StrictNetwork.verifyProtocolConnectivity(std.heap.smp_allocator, 6);
}

fn verifyIPv4Connectivity() bool {
    return StrictNetwork.verifyProtocolConnectivity(std.heap.smp_allocator, 4);
}
