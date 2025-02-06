import (
    "bytes"
    "encoding/json"
    "fmt"
    "io/ioutil"
    "net/http"
    "strings"
    "os"
    "strconv"
    "time"
)

type Result struct {
    duration    time.Duration
    totalTokens int
    err         error
}

type Message struct {
    Role    string `json:"role"`
    Content string `json:"content"`
}

type RequestBody struct {
    Messages  []Message `json:"messages"`
    Model     string    `json:"model"`
    MaxTokens int       `json:"max_tokens"`
    TopP      float64   `json:"top_p"`
    N         int       `json:"n"`
    Stream    bool      `json:"stream"`
}

type RequestConfig struct {
    URL       string
    Prompt    string
    MaxTokens int
}

type ResponseBody struct {
    ID      string `json:"id"`
    Object  string `json:"object"`
    Created int64  `json:"created"`
    Model   string `json:"model"`
    Choices []struct {
        Index   int `json:"index"`
        Message struct {
            Role    string `json:"role"`
            Content string `json:"content"`
        } `json:"message"`
    } `json:"choices"`
    Usage struct {
        TotalTokens int `json:"total_tokens"`
    } `json:"usage"`
}

func readPromptsFromFile(filename string) ([]string, error) {
    content, err := ioutil.ReadFile(filename)
    if err != nil {
        return nil, fmt.Errorf("error reading file: %v", err)
    }

    var prompts []string
    for _, line := range strings.Split(string(content), "\n") {
        if trimmed := strings.TrimSpace(line); trimmed != "" {
            prompts = append(prompts, trimmed)
        }
    }

    if len(prompts) == 0 {
        return nil, fmt.Errorf("no prompts found in file")
    }

    return prompts, nil
}

func makeRequest(config RequestConfig, results chan<- Result) {
    reqBody := RequestBody{
        Messages: []Message{
            {
                Role:    "user",
                Content: config.Prompt,
            },
        },
        Model:     "meta/llama2-13b-chat-v1",
        MaxTokens: config.MaxTokens,
        TopP:      1,
        N:         1,
        Stream:    false,
    }

    jsonData, err := json.Marshal(reqBody)
    if err != nil {
        results <- Result{duration: 0, totalTokens: 0, err: fmt.Errorf("error marshaling JSON: %v", err)}
        return
    }

    client := &http.Client{
        Timeout: 30 * time.Second,
    }

    req, err := http.NewRequest("POST", config.URL, bytes.NewBuffer(jsonData))
    if err != nil {
        results <- Result{duration: 0, totalTokens: 0, err: fmt.Errorf("error creating request: %v", err)}
        return
    }

    req.Header.Set("Content-Type", "application/json")
    req.Header.Set("Accept", "application/json")

    // Reset timer immediately before the request
    start := time.Now()

    resp, err := client.Do(req)
    if err != nil {
        results <- Result{duration: 0, totalTokens: 0, err: fmt.Errorf("error making request: %v", err)}
        return
    }
    defer resp.Body.Close()

    body, err := ioutil.ReadAll(resp.Body)

    // Calculate duration immediately after reading the response body
    duration := time.Since(start)

    if err != nil {
        results <- Result{duration: 0, totalTokens: 0, err: fmt.Errorf("error reading response: %v", err)}
        return
    }

    if resp.StatusCode != http.StatusOK {
        results <- Result{duration: 0, totalTokens: 0, err: fmt.Errorf("unexpected status code: %d, body: %s", resp.StatusCode, string(body))}
        return
    }

    var responseBody ResponseBody
    if err := json.Unmarshal(body, &responseBody); err != nil {
        results <- Result{duration: 0, totalTokens: 0, err: fmt.Errorf("error parsing response JSON: %v", err)}
        return
    }

    fmt.Printf("Request completed - Duration: %v, Tokens: %d\n",
        duration, responseBody.Usage.TotalTokens)

    results <- Result{
        duration:    duration,
        totalTokens: responseBody.Usage.TotalTokens,
        err:        nil,
    }
}

func calculateAverageResponseTime(config RequestConfig, numRequests int) (time.Duration, float64, error) {
    results := make(chan Result, numRequests)

    for i := 0; i < numRequests; i++ {
        go makeRequest(config, results)
        time.Sleep(500 * time.Millisecond)
    }

    var totalDuration time.Duration
    var totalTokens int
    var successfulRequests int

    for i := 0; i < numRequests; i++ {
        result := <-results
        if result.err != nil {
            fmt.Printf("Request error: %v\n", result.err)
            continue
        }
        totalDuration += result.duration
        totalTokens += result.totalTokens
        successfulRequests++

        fmt.Printf("Request %d/%d - Duration: %v, Tokens: %d\n",
            i+1, numRequests, result.duration, result.totalTokens)
    }

    if successfulRequests == 0 {
        return 0, 0, fmt.Errorf("no successful requests")
    }

    avgDuration := totalDuration / time.Duration(successfulRequests)
    tokensPerSecond := float64(totalTokens) / totalDuration.Seconds()

    return avgDuration, tokensPerSecond, nil
}

func warmup(config RequestConfig, numWarmupRequests int) error {
    fmt.Printf("\n=== Warming up with %d requests ===\n", numWarmupRequests)
    results := make(chan Result, numWarmupRequests)

    for i := 0; i < numWarmupRequests; i++ {
        go makeRequest(config, results)
        time.Sleep(500 * time.Millisecond)

        fmt.Printf("Warmup request %d/%d completed\n", i+1, numWarmupRequests)
    }

    var successfulWarmups int
    for i := 0; i < numWarmupRequests; i++ {
        result := <-results
        if result.err != nil {
            fmt.Printf("Warmup request error: %v\n", result.err)
            continue
        }
        successfulWarmups++
    }

    if successfulWarmups == 0 {
        return fmt.Errorf("all warmup requests failed")
    }

    fmt.Printf("Warmup completed successfully with %d/%d requests\n",
        successfulWarmups, numWarmupRequests)
    return nil
}


func main() {
    // Start timing the entire benchmark
    benchmarkStart := time.Now()

    prompts, err := readPromptsFromFile("prompts.txt")
    if err != nil {
        fmt.Printf("Error reading prompts: %v\n", err)
        return
    }

    // Read configuration from environment variables with defaults
    url := os.Getenv("URL")
    if url == "" {
        url = "http://localhost:8000/v1/chat/completions" // default value
    }

    requestsPerPrompt := 10 // default value
    if envVal := os.Getenv("REQUESTS_PER_PROMPT"); envVal != "" {
        if val, err := strconv.Atoi(envVal); err == nil {
            requestsPerPrompt = val
        }
    }

    numWarmupRequests := 3 // default value
    if envVal := os.Getenv("NUM_WARMUP_REQUESTS"); envVal != "" {
        if val, err := strconv.Atoi(envVal); err == nil {
            numWarmupRequests = val
        }
    }

    warmupConfig := RequestConfig{
        URL:       url,
        Prompt:    prompts[0],
        MaxTokens: 200,
    }

    fmt.Printf("\n=== Benchmark Configuration ===\n")
    fmt.Printf("URL: %s\n", url)
    fmt.Printf("Number of prompts: %d\n", len(prompts))
    fmt.Printf("Requests per prompt: %d\n", requestsPerPrompt)
    fmt.Printf("Warmup requests: %d\n", numWarmupRequests)
    fmt.Printf("Total requests planned: %d\n", len(prompts)*requestsPerPrompt+numWarmupRequests)

    if err := warmup(warmupConfig, numWarmupRequests); err != nil {
        fmt.Printf("Warmup failed: %v\n", err)
        return
    }

    fmt.Println("\nWaiting 2 seconds before starting benchmark...")
    time.Sleep(2 * time.Second)

    var totalSuccessfulRequests int
    var overallTotalDuration time.Duration
    var overallTotalTokens int

    fmt.Printf("\n=== Starting Benchmark Test ===\n")
    fmt.Printf("Start time: %v\n\n", time.Now().Format("2006-01-02 15:04:05"))

    for i, prompt := range prompts {
        config := RequestConfig{
            URL:       url,
            Prompt:    prompt,
            MaxTokens: 200,
        }

        fmt.Printf("\n--- Prompt %d/%d ---\n", i+1, len(prompts))
        fmt.Printf("Prompt: %s\n", prompt)

        avgTime, tokensPerSec, err := calculateAverageResponseTime(config, requestsPerPrompt)
        if err != nil {
            fmt.Printf("Error calculating average: %v\n", err)
            continue
        }

        promptTotalDuration := avgTime * time.Duration(requestsPerPrompt)
        promptTotalTokens := int(tokensPerSec * avgTime.Seconds()) * requestsPerPrompt

        overallTotalDuration += promptTotalDuration
        overallTotalTokens += promptTotalTokens
        totalSuccessfulRequests += requestsPerPrompt

        fmt.Printf("Prompt Average Response Time: %v\n", avgTime)
        fmt.Printf("Prompt Tokens per Second: %.2f\n\n", tokensPerSec)

    }

    // Calculate total benchmark duration
    totalBenchmarkDuration := time.Since(benchmarkStart)

    if totalSuccessfulRequests > 0 {
        overallAvgLatency := overallTotalDuration / time.Duration(totalSuccessfulRequests)
        overallTokensPerSec := float64(overallTotalTokens) / overallTotalDuration.Seconds()

        fmt.Printf("\n=== Overall Benchmark Results ===\n")
        fmt.Printf("End time: %v\n", time.Now().Format("2006-01-02 15:04:05"))
        fmt.Printf("Total Benchmark Duration: %v\n", totalBenchmarkDuration)
        fmt.Printf("Total Successful Requests: %d\n", totalSuccessfulRequests)
        fmt.Printf("Overall Average Latency: %v\n", overallAvgLatency)
        fmt.Printf("Overall Average Tokens/Second: %.2f\n", overallTokensPerSec)

        // Add detailed timing breakdown
        fmt.Printf("\n=== Timing Breakdown ===\n")
        fmt.Printf("Total wall clock time: %v\n", totalBenchmarkDuration)
        fmt.Printf("Total processing time: %v\n", overallTotalDuration)
        fmt.Printf("Overhead time (includes delays): %v\n",
            totalBenchmarkDuration-overallTotalDuration)
    }
}
