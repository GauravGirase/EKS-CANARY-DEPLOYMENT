package main

import (
	"encoding/json"
	"fmt"
	"log"
	"math/rand"
	"net/http"
	"os"
	"time"
)

var version = "v2-buggy"
var startTime = time.Now()

// INTENTIONAL BUG: 60% of requests will fail with 500
// This simulates a bad deployment that should be auto-rolled back
const errorRate = 0.60

func main() {
	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	http.HandleFunc("/", homeHandler)
	http.HandleFunc("/health", healthHandler)
	http.HandleFunc("/ready", readyHandler)
	http.HandleFunc("/api/data", dataHandler)
	http.HandleFunc("/metrics", metricsHandler)

	log.Printf("Starting myapp %s on port %s (WARNING: buggy version!)", version, port)
	log.Fatal(http.ListenAndServe(":"+port, nil))
}

func homeHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"app":     "myapp",
		"version": version,
		"message": "Hello from v2... but something is wrong!",
		"uptime":  time.Since(startTime).String(),
	})
}

func healthHandler(w http.ResponseWriter, r *http.Request) {
	// Health check still passes (pod stays Running)
	// This is realistic - the pod is alive but the app logic is broken
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(map[string]string{
		"status":  "healthy",
		"version": version,
	})
}

func readyHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(map[string]string{
		"status":  "ready",
		"version": version,
	})
}

func dataHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")

	// INTENTIONAL BUG: randomly fail 60% of requests
	if rand.Float64() < errorRate {
		errorCount++
		// Also simulate high latency on errors
		time.Sleep(time.Duration(500+rand.Intn(1000)) * time.Millisecond)
		w.WriteHeader(http.StatusInternalServerError)
		json.NewEncoder(w).Encode(map[string]interface{}{
			"version": version,
			"error":   "Internal Server Error - database connection pool exhausted",
			"code":    500,
		})
		return
	}

	requestCount++
	// Slow even on success
	time.Sleep(time.Duration(200+rand.Intn(300)) * time.Millisecond)
	json.NewEncoder(w).Encode(map[string]interface{}{
		"version": version,
		"data":    fmt.Sprintf("Unstable data from %s", version),
		"latency": "slow",
	})
}

var requestCount int
var errorCount int

func metricsHandler(w http.ResponseWriter, r *http.Request) {
	fmt.Fprintf(w, `# HELP http_requests_total Total HTTP requests
# TYPE http_requests_total counter
http_requests_total{app="myapp",version="%s",status="200"} %d
http_requests_total{app="myapp",version="%s",status="500"} %d
# HELP app_version Current app version
# TYPE app_version gauge
app_version{version="%s"} 1
`, version, requestCount, version, errorCount, version)
}
