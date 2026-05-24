package main

import (
	"context"
	"errors"
	"flag"
	"fmt"
	"log"
	nethttp "net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

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

	server := http.NewServer()
	defer server.Close()

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	errCh := make(chan error, 1)
	go func() {
		errCh <- server.ListenAndServe(fmt.Sprintf(":%d", *port))
	}()

	select {
	case err := <-errCh:
		if err != nil && !errors.Is(err, nethttp.ErrServerClosed) {
			log.Fatal(err)
		}
	case <-ctx.Done():
		shutdownCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel()
		if err := server.Shutdown(shutdownCtx); err != nil {
			log.Printf("Shutdown error: %v", err)
		}
		if err := <-errCh; err != nil && !errors.Is(err, nethttp.ErrServerClosed) {
			log.Printf("Server error: %v", err)
		}
	}
}
