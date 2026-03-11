# fast-cli

[![Go](https://img.shields.io/badge/Go-1.21+-00ADD8.svg)](https://golang.org/)
[![CI](https://github.com/mikkelam/fast-cli/actions/workflows/ci.yml/badge.svg)](https://github.com/mikkelam/fast-cli/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

A blazingly fast CLI tool for testing internet speed using fast.com API. Written in Go for cross-platform compatibility.

## Features

- **Download & Upload Speed**: Test your connection speed
- **IPv4/IPv6 Support**: Force test using specific IP protocol version
- **Enhanced Network Stats**: Jitter and latency measurement
- **Concurrent Connections**: Configurable concurrent connections for speed tests
- **JSON Output**: Machine-readable results

## Demo

![Fast-CLI Demo](demo/fast-cli-demo.svg)

## Why fast-cli?

- **Cross-platform**: Single binary for Linux, macOS, Windows
- **Fast**: Concurrent connections with connection pooling
- **Simple**: Zero configuration required
- **Protocol Aware**: IPv6 and IPv4 protocol verification

## Supported Platforms

- **Linux**: x86_64, aarch64 (ARM64)
- **macOS**: x86_64 (Intel), aarch64 (Apple Silicon)
- **Windows**: x86_64

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
go build -o fast-cli ./cmd/fast-cli/
```

## Usage

```console
$ ./fast-cli --help
Usage: fast-cli [options]

Options:
  -u, --upload      Check upload speed as well
  -d, --duration    Maximum test duration in seconds (default: 30)
  -c, --concurrent  Number of concurrent connections (default: 8)
      --ipv        Specify IP version (4 or 6), 0=auto (default: 0)
      --https      Use https when connecting to fast.com (default: true)
  -j, --json        Output results in JSON format
  -h, --help        Shows the help for a command
```

## Examples

### Basic Speed Test

```bash
./fast-cli
```

### Test with Upload Speed

```bash
./fast-cli --upload
```

### IPv6 Only

```bash
./fast-cli --ipv 6
```

### IPv4 Only

```bash
./fast-cli --ipv 4
```

### JSON Output

```bash
./fast-cli --json
```

### Quick 15-second Test

```bash
./fast-cli -d 15
```

### High Concurrency

```bash
./fast-cli -c 16
```

## Example Output

```console
$ ./fast-cli --upload --ipv 6
  Network: IPv6
  Latency: 25ms (min: 18ms, max: 42ms)
  Jitter: 3.2ms
  Download: 213.7 Mbps | Upload: 82.1 Mbps

$ ./fast-cli -d 15 -c 4
  Auto | Download: 155.0 Mbps

$ ./fast-cli -j --ipv 4
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

- **Latency**: Average, minimum, and maximum round-trip time
- **Jitter**: Variation in latency measurements
- **Protocol**: Network protocol used for testing (IPv4/IPv6/Auto)

## Development

```bash
# Build
go build -o fast-cli ./cmd/fast-cli/

# Run
./fast-cli

# Cross-compilation
GOOS=linux GOARCH=amd64 go build -o fast-cli-linux-amd64 ./cmd/fast-cli/
GOOS=darwin GOARCH=arm64 go build -o fast-cli-darwin-arm64 ./cmd/fast-cli/
```

## Project Structure

```
.
├── cmd/
│   └── fast-cli/
│       └── main.go          # CLI entry point
├── go.mod                   # Go module definition
└── README.md                # This file
```

## License

MIT License - see [LICENSE](LICENSE) for details.

---

*Not affiliated with Netflix or Fast.com*
