package main

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net"
	"net/http"
	"os"
	"regexp"
	"strings"
	"sync"
	"time"
)

type SpeedTestResult struct {
	DownloadMbps float64 `json:"download_mbps"`
	UploadMbps   float64 `json:"upload_mbps,omitempty"`
	PingMs       float64 `json:"ping_ms"`
	JitterMs     float64 `json:"jitter_ms"`
	PacketLoss   float64 `json:"packet_loss"`
	Protocol     string  `json:"protocol"`
	Error        *string `json:"error,omitempty"`
}

type LatencyStats struct {
	minLatency time.Duration
	maxLatency time.Duration
	latencies  []time.Duration
	mu         sync.Mutex
	errors     int
	totalTests int
}

func newLatencyStats() *LatencyStats {
	return &LatencyStats{
		latencies: make([]time.Duration, 0),
	}
}

func (l *LatencyStats) add(latency time.Duration) {
	l.mu.Lock()
	defer l.mu.Unlock()
	l.latencies = append(l.latencies, latency)
	if latency < l.minLatency || l.minLatency == 0 {
		l.minLatency = latency
	}
	if latency > l.maxLatency {
		l.maxLatency = latency
	}
}

func (l *LatencyStats) addError() {
	l.mu.Lock()
	defer l.mu.Unlock()
	l.errors++
	l.totalTests++
}

func (l *LatencyStats) mean() time.Duration {
	l.mu.Lock()
	defer l.mu.Unlock()
	if len(l.latencies) == 0 {
		return 0
	}
	var sum time.Duration
	for _, lat := range l.latencies {
		sum += lat
	}
	return sum / time.Duration(len(l.latencies))
}

func (l *LatencyStats) jitter() float64 {
	l.mu.Lock()
	defer l.mu.Unlock()
	if len(l.latencies) < 2 {
		return 0
	}
	var sum float64
	for i := 1; i < len(l.latencies); i++ {
		diff := float64(l.latencies[i]-l.latencies[i-1]) / 1_000_000 // convert ns to ms
		sum += diff * diff
	}
	return sum / float64(len(l.latencies)-1)
}

func (l *LatencyStats) min() time.Duration {
	l.mu.Lock()
	defer l.mu.Unlock()
	return l.minLatency
}

func (l *LatencyStats) max() time.Duration {
	l.mu.Lock()
	defer l.mu.Unlock()
	return l.maxLatency
}

func (l *LatencyStats) packetLoss() float64 {
	l.mu.Lock()
	defer l.mu.Unlock()
	if l.totalTests == 0 {
		return 0
	}
	return float64(l.errors) / float64(l.totalTests) * 100
}

type SpeedTester struct {
	client          *http.Client
	concurrentConns int
	useIPv6         bool
	useHTTPS        bool
}

func NewSpeedTester(concurrentConns int, useIPv6, useHTTPS bool) *SpeedTester {
	dialer := &net.Dialer{
		Timeout:   30 * time.Second,
		KeepAlive: 30 * time.Second,
	}

	var dialContext func(ctx context.Context, network, addr string) (net.Conn, error)

	if useIPv6 {
		dialContext = func(ctx context.Context, network, addr string) (net.Conn, error) {
			return dialer.DialContext(ctx, "tcp6", addr)
		}
	} else {
		dialContext = dialer.DialContext
	}

	transport := &http.Transport{
		MaxIdleConns:        concurrentConns * 2,
		MaxIdleConnsPerHost: concurrentConns * 2,
		IdleConnTimeout:     30 * time.Second,
		DialContext:         dialContext,
	}

	return &SpeedTester{
		client: &http.Client{
			Transport: transport,
			Timeout:   60 * time.Second,
		},
		concurrentConns: concurrentConns,
		useIPv6:         useIPv6,
		useHTTPS:        useHTTPS,
	}
}

type FastTarget struct {
	URL  string `json:"url"`
	Name string `json:"name"`
}

type FastResponse struct {
	Client  interface{}  `json:"client"`
	Targets []FastTarget `json:"targets"`
}

func getFastDotComToken(useHTTPS bool) (string, error) {
	scheme := "https"
	if !useHTTPS {
		scheme = "http"
	}

	resp, err := http.Get(scheme + "://fast.com")
	if err != nil {
		return "", fmt.Errorf("failed to fetch fast.com: %w", err)
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return "", err
	}

	scriptRegex := regexp.MustCompile(`app-[a-zA-Z0-9]+\.js`)
	match := scriptRegex.FindString(string(body))
	if match == "" {
		return "", fmt.Errorf("could not find script name")
	}

	scriptURL := scheme + "://fast.com/" + match
	resp2, err := http.Get(scriptURL)
	if err != nil {
		return "", fmt.Errorf("failed to fetch script: %w", err)
	}
	defer resp2.Body.Close()

	scriptBody, err := io.ReadAll(resp2.Body)
	if err != nil {
		return "", err
	}

	tokenRegex := regexp.MustCompile(`token:"([a-zA-Z0-9]*)"`)
	match2 := tokenRegex.FindStringSubmatch(string(scriptBody))
	if len(match2) < 2 {
		return "", fmt.Errorf("could not find token")
	}

	return match2[1], nil
}

func getFastDotComURLs(useHTTPS bool, token string, count int) ([]string, error) {
	scheme := "https"
	if !useHTTPS {
		scheme = "http"
	}

	url := fmt.Sprintf("%s://api.fast.com/netflix/speedtest/v2?https=%t&token=%s&urlCount=%d",
		scheme, useHTTPS, token, count)

	resp, err := http.Get(url)
	if err != nil {
		return nil, fmt.Errorf("failed to fetch API: %w", err)
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, err
	}

	var fastResp FastResponse
	if err := json.Unmarshal(body, &fastResp); err != nil {
		return nil, fmt.Errorf("failed to parse JSON: %w, body: %s", err, string(body))
	}

	urls := make([]string, 0, len(fastResp.Targets))
	for _, target := range fastResp.Targets {
		urls = append(urls, target.URL)
	}

	if len(urls) == 0 {
		return nil, fmt.Errorf("no URLs returned from API")
	}

	return urls, nil
}

func (s *SpeedTester) measureLatency(urls []string, count int, timeout time.Duration) (*LatencyStats, error) {
	stats := newLatencyStats()
	url := urls[0]

	var wg sync.WaitGroup

	for i := 0; i < count; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()

			ctx, cancel := context.WithTimeout(context.Background(), timeout)
			defer cancel()

			firstReq, err := http.NewRequestWithContext(ctx, "HEAD", url, nil)
			if err != nil {
				stats.addError()
				return
			}

			firstResp, err := s.client.Do(firstReq)
			if err != nil {
				stats.addError()
				return
			}
			firstResp.Body.Close()

			start := time.Now()
			req, err := http.NewRequestWithContext(ctx, "HEAD", url, nil)
			if err != nil {
				stats.addError()
				return
			}
			resp, err := s.client.Do(req)
			if err != nil {
				stats.addError()
				return
			}
			resp.Body.Close()
			latency := time.Since(start)

			// Skip suspiciously low latencies (likely cached)
			if latency < 10*time.Millisecond {
				stats.addError()
				return
			}

			stats.add(latency)
		}()
	}

	wg.Wait()

	if len(stats.latencies) == 0 {
		return stats, nil
	}
	return stats, nil
}

func (s *SpeedTester) measureDownloadSpeed(urls []string, duration time.Duration, progressFn func(float64)) (float64, error) {
	ctx, cancel := context.WithTimeout(context.Background(), duration)
	defer cancel()

	var wg sync.WaitGroup
	var totalBytes int64
	var mu sync.Mutex

	urlsToUse := urls
	if len(urls) > s.concurrentConns {
		urlsToUse = urls[:s.concurrentConns]
	}

	startTime := time.Now()

	for i := 0; i < len(urlsToUse); i++ {
		wg.Add(1)
		go func(url string) {
			defer wg.Done()
			for {
				select {
				case <-ctx.Done():
					return
				default:
					req, err := http.NewRequestWithContext(ctx, "GET", url, nil)
					if err != nil {
						return
					}
					resp, err := s.client.Do(req)
					if err != nil {
						return
					}
					buf := make([]byte, 32*1024)
					for {
						n, err := resp.Body.Read(buf)
						if n > 0 {
							mu.Lock()
							totalBytes += int64(n)
							mu.Unlock()
						}
						if err != nil {
							break
						}
					}
					resp.Body.Close()
				}
			}
		}(urlsToUse[i])
	}

	ticker := time.NewTicker(750 * time.Millisecond)
	defer ticker.Stop()

	for {
		select {
		case <-ctx.Done():
			elapsed := time.Since(startTime)
			mu.Lock()
			bytes := totalBytes
			mu.Unlock()

			if progressFn != nil && elapsed > 0 {
				mbps := float64(bytes) * 8 / elapsed.Seconds() / 1_000_000
				progressFn(mbps)
			}

			wg.Wait()

			if elapsed.Seconds() == 0 {
				return 0, nil
			}
			return float64(bytes) * 8 / elapsed.Seconds() / 1_000_000, nil

		case <-ticker.C:
			mu.Lock()
			current := totalBytes
			mu.Unlock()
			elapsed := time.Since(startTime)
			if elapsed > 0 && progressFn != nil {
				mbps := float64(current) * 8 / elapsed.Seconds() / 1_000_000
				progressFn(mbps)
			}
		}
	}
}

func (s *SpeedTester) measureUploadSpeed(urls []string, duration time.Duration, progressFn func(float64)) (float64, error) {
	ctx, cancel := context.WithTimeout(context.Background(), duration)
	defer cancel()

	var wg sync.WaitGroup
	var totalBytes int64
	var mu sync.Mutex

	uploadData := make([]byte, 4*1024*1024)
	for i := range uploadData {
		uploadData[i] = 'A'
	}

	urlsToUse := urls
	if len(urls) > s.concurrentConns {
		urlsToUse = urls[:s.concurrentConns]
	}

	startTime := time.Now()

	for i := 0; i < len(urlsToUse); i++ {
		wg.Add(1)
		go func(url string) {
			defer wg.Done()
			for {
				select {
				case <-ctx.Done():
					return
				default:
					req, err := http.NewRequestWithContext(ctx, "POST", url, nil)
					if err != nil {
						return
					}
					req.Body = io.NopCloser(strings.NewReader(string(uploadData)))
					req.ContentLength = int64(len(uploadData))
					resp, err := s.client.Do(req)
					if err != nil {
						return
					}
					io.Copy(io.Discard, resp.Body)
					resp.Body.Close()
					mu.Lock()
					totalBytes += int64(len(uploadData))
					mu.Unlock()
				}
			}
		}(urlsToUse[i])
	}

	ticker := time.NewTicker(750 * time.Millisecond)
	defer ticker.Stop()

	for {
		select {
		case <-ctx.Done():
			elapsed := time.Since(startTime)
			mu.Lock()
			bytes := totalBytes
			mu.Unlock()

			if progressFn != nil && elapsed > 0 {
				mbps := float64(bytes) * 8 / elapsed.Seconds() / 1_000_000
				progressFn(mbps)
			}

			wg.Wait()

			if elapsed.Seconds() == 0 {
				return 0, nil
			}
			return float64(bytes) * 8 / elapsed.Seconds() / 1_000_000, nil

		case <-ticker.C:
			mu.Lock()
			current := totalBytes
			mu.Unlock()
			elapsed := time.Since(startTime)
			if elapsed > 0 && progressFn != nil {
				mbps := float64(current) * 8 / elapsed.Seconds() / 1_000_000
				progressFn(mbps)
			}
		}
	}
}

func formatSpeed(mbps float64) (float64, string) {
	if mbps >= 1000 {
		return mbps / 1000, "Gbps"
	} else if mbps >= 1 {
		return mbps, "Mbps"
	} else {
		return mbps * 1000, "Kbps"
	}
}

func outputJSON(result *SpeedTestResult) {
	jsonBytes, _ := json.MarshalIndent(result, "", "  ")
	fmt.Println(string(jsonBytes))
}

func outputText(result *SpeedTestResult, latencyStats *LatencyStats) {
	protocol := result.Protocol
	downloadVal, downloadUnit := formatSpeed(result.DownloadMbps)

	fmt.Printf("\n")
	if latencyStats != nil && len(latencyStats.latencies) > 0 {
		ping := float64(latencyStats.mean().Milliseconds())
		minPing := float64(latencyStats.min().Milliseconds())
		maxPing := float64(latencyStats.max().Milliseconds())
		jitter := latencyStats.jitter()
		loss := latencyStats.packetLoss()

		if result.UploadMbps > 0 {
			uploadVal, uploadUnit := formatSpeed(result.UploadMbps)
			fmt.Printf("  Network: %s\n", protocol)
			fmt.Printf("  Latency: %.0fms (min: %.0fms, max: %.0fms)\n", ping, minPing, maxPing)
			fmt.Printf("  Jitter: %.1fms | Loss: %.1f%%\n", jitter, loss)
			fmt.Printf("  Download: %.1f %s | Upload: %.1f %s\n", downloadVal, downloadUnit, uploadVal, uploadUnit)
		} else {
			fmt.Printf("  Network: %s\n", protocol)
			fmt.Printf("  Latency: %.0fms (min: %.0fms, max: %.0fms)\n", ping, minPing, maxPing)
			fmt.Printf("  Jitter: %.1fms | Loss: %.1f%%\n", jitter, loss)
			fmt.Printf("  Download: %.1f %s\n", downloadVal, downloadUnit)
		}
	} else {
		if result.UploadMbps > 0 {
			uploadVal, uploadUnit := formatSpeed(result.UploadMbps)
			fmt.Printf("  %s | Download: %.1f %s | Upload: %.1f %s\n", protocol, downloadVal, downloadUnit, uploadVal, uploadUnit)
		} else {
			fmt.Printf("  %s | Download: %.1f %s\n", protocol, downloadVal, downloadUnit)
		}
	}
}

func main() {
	useHTTPS := true
	ipVersion := 0
	checkUpload := false
	jsonOutput := false
	maxDuration := 30
	concurrentConns := 8

	args := os.Args[1:]
	for i := 0; i < len(args); i++ {
		arg := args[i]
		switch arg {
		case "--https":
			useHTTPS = true
			if i+1 < len(args) && args[i+1] == "false" {
				useHTTPS = false
				i++
			}
		case "--ipv":
			if i+1 < len(args) {
				fmt.Sscanf(args[i+1], "%d", &ipVersion)
				i++
			}
		case "-u", "--upload":
			checkUpload = true
		case "-j", "--json":
			jsonOutput = true
		case "-d", "--duration":
			if i+1 < len(args) {
				fmt.Sscanf(args[i+1], "%d", &maxDuration)
				i++
			}
		case "-c", "--concurrent":
			if i+1 < len(args) {
				fmt.Sscanf(args[i+1], "%d", &concurrentConns)
				i++
			}
		case "-h", "--help":
			fmt.Println("Usage: fast-cli [options]")
			fmt.Println("")
			fmt.Println("Options:")
			fmt.Println("  -u, --upload      Check upload speed as well")
			fmt.Println("  -d, --duration    Maximum test duration in seconds (default: 30)")
			fmt.Println("  -c, --concurrent  Number of concurrent connections (default: 8)")
			fmt.Println("      --ipv        Specify IP version (4 or 6), 0=auto (default: 0)")
			fmt.Println("      --https      Use https when connecting to fast.com (default: true)")
			fmt.Println("  -j, --json        Output results in JSON format")
			fmt.Println("  -h, --help        Shows the help for a command")
			os.Exit(0)
		}
	}

	fmt.Print("Getting speed test URLs from fast.com...")
	token, err := getFastDotComToken(useHTTPS)
	if err != nil {
		fmt.Printf(" failed: %v\n", err)
		errMsg := err.Error()
		outputJSON(&SpeedTestResult{Error: &errMsg})
		os.Exit(1)
	}

	urls, err := getFastDotComURLs(useHTTPS, token, 10)
	if err != nil {
		fmt.Printf(" failed: %v\n", err)
		errMsg := err.Error()
		outputJSON(&SpeedTestResult{Error: &errMsg})
		os.Exit(1)
	}
	fmt.Printf(" got %d URLs\n", len(urls))

	tester := NewSpeedTester(concurrentConns, ipVersion == 6, useHTTPS)
	defer tester.client.CloseIdleConnections()

	duration := time.Duration(maxDuration) * time.Second

	var latencyStats *LatencyStats
	latencyStats, err = tester.measureLatency(urls, 10, 2*time.Second)
	if err != nil {
		fmt.Printf("Warning: latency test failed: %v\n", err)
		latencyStats = nil
	}

	fmt.Print("Testing download speed...")
	downloadMbps, err := tester.measureDownloadSpeed(urls, duration, nil)
	if err != nil {
		fmt.Printf(" failed: %v\n", err)
		errMsg := err.Error()
		outputJSON(&SpeedTestResult{Error: &errMsg})
		os.Exit(1)
	}
	fmt.Printf(" %.1f Mbps\n", downloadMbps)

	var uploadMbps float64
	if checkUpload {
		fmt.Print("Testing upload speed...")
		uploadMbps, err = tester.measureUploadSpeed(urls, duration, nil)
		if err != nil {
			fmt.Printf(" failed: %v\n", err)
			errMsg := err.Error()
			outputJSON(&SpeedTestResult{Error: &errMsg})
			os.Exit(1)
		}
		fmt.Printf(" %.1f Mbps\n", uploadMbps)
	}

	protocol := "Auto"
	if ipVersion == 6 {
		protocol = "IPv6"
	} else if ipVersion == 4 {
		protocol = "IPv4"
	}

	result := &SpeedTestResult{
		DownloadMbps: downloadMbps,
		UploadMbps:   uploadMbps,
		Protocol:     protocol,
	}

	if latencyStats != nil {
		result.PingMs = float64(latencyStats.mean().Milliseconds())
		result.JitterMs = latencyStats.jitter()
		result.PacketLoss = latencyStats.packetLoss()
	}

	if jsonOutput {
		outputJSON(result)
	} else {
		outputText(result, latencyStats)
	}
}
