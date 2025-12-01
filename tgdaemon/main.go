package main

import (
	"flag"
	"fmt"
	"os"

	"github.com/juhovh/tailguard/tgdaemon/env"
	"github.com/juhovh/tailguard/tgdaemon/http"
)

func main() {
	port := flag.Int("port", 0, "Port to listen on (required)")
	flag.Parse()

	if *port == 0 {
		fmt.Println("Error: --port is required")
		flag.Usage()
		os.Exit(1)
	}

	listenPort := *port
	fmt.Printf("Listening on port %d\n", listenPort)

	cfg := env.GetTailguardConfig()
	server := http.NewServer(cfg)
	defer server.Close()

	server.ListenAndServe(fmt.Sprintf(":%d", listenPort))
}
