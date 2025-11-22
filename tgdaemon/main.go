package main

import (
	"github.com/juhovh/tailguard/tgdaemon/env"
	"github.com/juhovh/tailguard/tgdaemon/http"
)

func main() {
	cfg := env.GetTailguardConfig()
	server := http.NewServer(cfg)
	defer server.Close()

	server.ListenAndServe(":8090")
}
