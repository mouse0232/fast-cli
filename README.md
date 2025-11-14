# fast-cli

[![Zig](https://img.shields.io/badge/Zig-0.14.0+-orange.svg)](https://ziglang.org/)
[![CI](https://github.com/mikkelam/fast-cli/actions/workflows/ci.yml/badge.svg)](https://github.com/mikkelam/fast-cli/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

A blazingly fast CLI tool for testing internet speed uses fast.com v2 api. Written in Zig for maximum performance.

⚡ **1.2 MB binary** • 🚀 **Zero runtime deps** • 📊 **Smart stability detection** • 🌐 **IPv6 Support**

## New Features

- **Strict IPv6/IPv4 Mode**: Force test using specific IP protocol version
- **Enhanced Network Stats**: Jitter and packet loss measurement
- **Concurrent Connections**: Configurable concurrent connections for speed tests
- **Improved JSON Output**: More detailed network statistics

## Demo

![Fast-CLI Demo](demo/fast-cli-demo.svg)

## Why fast-cli?

- **Tiny binary**: Just 1.2 MB, no runtime dependencies
- **Blazing fast**: Concurrent connections with adaptive chunk sizing
- **Cross-platform**: Single binary for Linux, macOS
- **Smart stopping**: Uses Coefficient of Variation (CoV) algorithm for adaptive test duration
- **Protocol Aware**: IPv6 and IPv4 protocol verification and enforcement

## Supported Platforms

- **Linux**: x86_64, aarch64 (ARM64)
- **macOS**: x86_64 (Intel), aarch64 (aka Apple Silicon)
- **Windows**: x86_64 (Experimental)

## Installation

### Quick Install

```bash
curl -sSL https://raw.githubusercontent.com/mouse0232/fast-cli/main/install.sh | bash
```

### Pre-built Binaries
For example, on an Apple Silicon Mac:
```bash
curl -L https://github.com/mouse0232/fast-cli/releases/latest/download/fast-cli-aarch64-macos.tar.gz -o fast-cli.tar.gz
tar -xzf fast-cli.tar.gz
chmod +x fast-cli && sudo mv fast-cli /usr/local/bin/
fast-cli --help
```

### Build from Source
```bash
git clone https://github.com/mikkelam/fast-cli.git
cd fast-cli
zig build -Doptimize=ReleaseSafe
```

## Usage
```console
❯ ./fast-cli --help
Estimate connection speed using fast.com
v0.1.0

Usage: fast-cli [options]

Flags:
 -u, --upload      Check upload speed as well [Bool] (default: false)
 -d, --duration    Maximum test duration in seconds [Int] (default: 30)
 -c, --concurrent  Number of concurrent connections (0=single-thread) [Int] (default: 8)
     --ipv        Specify IP version (4 or 6), 0=auto [Int] (default: 0)
     --https      Use https when connecting to fast.com [Bool] (default: true)
 -j, --json        Output results in JSON format [Bool] (default: false)
 -h, --help        Shows the help for a command [Bool] (default: false)
```

## Advanced Features

### IPv6 Testing
```bash
# Force IPv6 testing with connectivity verification
fast-cli --ipv 6

# Force IPv4 testing
fast-cli --ipv 4

# Auto-detect protocol (default)
fast-cli --ipv 0
```

### Custom Concurrent Connections
```bash
# Single-threaded mode
fast-cli --concurrent 0

# High concurrency for faster results
fast-cli --concurrent 16
```

### Quick Tests
```bash
# Quick 15-second test
fast-cli -d 15

# Quick test with upload and JSON output
fast-cli -u -d 20 -j
```

## Example Output

```console
$ fast-cli --upload --ipv 6
🔒 IPv6 | 🏓 Latency: 25ms (min: 18ms, max: 42ms)
📊 Jitter: 3.2ms | 📉 Loss: 0.0%
⬇️ Download: 213.7 Mbps | ⬆️ Upload: 82.1 Mbps

$ fast-cli -d 15 -c 4
🔒 Auto | 🏓 Latency: 22ms | ⬇️ Download: 155.0 Mbps

$ fast-cli -j --ipv 4
{
  "download_mbps": 221.4,
  "upload_mbps": 92.8,
  "ping_ms": 19.2,
  "jitter_ms": 2.1,
  "packet_loss": 0.0,
  "protocol": "IPv4",
  "error": null
}
```

## Network Statistics

fast-cli now provides detailed network quality metrics:

- **Latency**: Average, minimum, and maximum round-trip time
- **Jitter**: Variation in latency measurements
- **Packet Loss**: Percentage of failed connectivity tests
- **Protocol**: Network protocol used for testing (IPv4/IPv6/Auto)

## Development

```bash
# Debug build
zig build

# Run all tests
zig build test

# Test specific components
zig test src/lib/network_stats_test.zig
zig test src/lib/worker_manager_test.zig

# Release build with optimizations
zig build -Doptimize=ReleaseFast

# Cross-compilation for different targets
zig build -Dtarget=x86_64-linux -Doptimize=ReleaseSafe
```

## Technology

Built with Zig's standard library for maximum performance:
- Concurrent HTTP client with connection pooling
- Async I/O for efficient resource usage
- Zero-copy parsing where possible
- Memory safety with compile-time checks

## License

MIT License - see [LICENSE](LICENSE) for details.

---

*Not affiliated with Netflix or Fast.com*
