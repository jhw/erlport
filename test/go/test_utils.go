package main

import (
	"erlport/erlport/erlang"
	"erlport/erlport/erlproto"
	"flag"
	"fmt"
	"os"
)

// Test utility functions that mirror Python/Ruby test utilities

// Basic functions
func identity(v interface{}) interface{} {
	return v
}

func add(a, b int) int {
	return a + b
}

func length(v []interface{}) int {
	return len(v)
}

// Recursion test - calls back to Erlang
// Note: This is simplified for now, full implementation would need callback support
func recurse(go_instance interface{}, n int) interface{} {
	if n <= 0 {
		return "done"
	}
	// For now, just return done - full recursion would require calling back to Erlang
	return "done"
}

func main() {
	var packet int
	var stdio bool
	var noUseStdio bool
	var compressed int
	var bufferSize int

	flag.IntVar(&packet, "packet", 4, "Message length sent in N bytes")
	flag.BoolVar(&stdio, "use_stdio", true, "Use stdin/stdout")
	flag.BoolVar(&noUseStdio, "nouse_stdio", false, "Use fd3/fd4")
	flag.IntVar(&compressed, "compressed", 0, "Compression level")
	flag.IntVar(&bufferSize, "buffer_size", 65536, "Buffer size")

	flag.Parse()

	useStdio := stdio && !noUseStdio

	port, err := erlproto.NewPort(packet, useStdio, compressed, bufferSize)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error creating port: %v\n", err)
		os.Exit(1)
	}

	handler := erlang.NewMessageHandler(port)
	handler.Register("identity", identity)
	handler.Register("add", add)
	handler.Register("length", length)
	handler.Register("recurse", recurse)

	handler.Start()
}
