package main

import (
	"github.com/juhovh/tailguard/daemon/http"
)

func main() {
	server := http.NewServer()
	defer server.Close()

	server.ListenAndServe(":8090")
}
