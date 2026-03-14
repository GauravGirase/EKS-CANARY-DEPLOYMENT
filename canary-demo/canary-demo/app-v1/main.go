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

var version = "v1"
var startTime = time.Now()

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

	log.Printf("Starting myapp %s on port %s", version, port)
	log.Fatal(http.ListenAndServe(":"+port, nil))
}

func homeHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"app":     "myapp",
		"version": version,
		"message": "Hello from stable v1! Everything is working perfectly.",
		"uptime":  time.Since(startTime).String(),
	})
}

func healthHandler(w http.ResponseWriter, r *http.Request) {
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
	// V1 is perfectly stable - always succeeds
	time.Sleep(time.Duration(rand.Intn(50)) * time.Millisecond)
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"version": version,
		"data":    fmt.Sprintf("Stable data from %s", version),
		"latency": "fast",
	})
}

// Simple Prometheus-compatible metrics endpoint
var requestCount int
var errorCount int

func metricsHandler(w http.ResponseWriter, r *http.Request) {
	requestCount++
	fmt.Fprintf(w, `# HELP http_requests_total Total HTTP requests
# TYPE http_requests_total counter
http_requests_total{app="myapp",version="%s",status="200"} %d
http_requests_total{app="myapp",version="%s",status="500"} %d
# HELP app_version Current app version
# TYPE app_version gauge
app_version{version="%s"} 1
`, version, requestCount, version, errorCount, version)
}
