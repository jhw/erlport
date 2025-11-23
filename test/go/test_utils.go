package main

import (
	"erlport/erlport/erlang"
	"erlport/erlport/erlproto"
	"flag"
	"fmt"
	"os"

	erl "github.com/okeuday/erlang_go/src/erlang"
)

// Test utility functions that mirror Python/Ruby test utilities

// Global handler to enable Cast operations
var globalHandler *erlang.MessageHandler

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
func recurse(go_instance interface{}, n int) interface{} {
	if n <= 0 {
		return erl.OtpErlangAtom("done")
	}

	if globalHandler == nil {
		return erl.OtpErlangAtom("error")
	}

	// Call back to Erlang: go_tests:recurse(GoInstance, N-1)
	result, err := globalHandler.Call("go_tests", "recurse", []interface{}{
		go_instance,
		n - 1,
	})

	if err != nil {
		fmt.Fprintf(os.Stderr, "Recursion error: %v\n", err)
		return erl.OtpErlangAtom("error")
	}

	return result
}

// SetupMessageHandler sets up a message handler that calls back to Erlang
// This will be fully implemented in Phase 3 when Call functionality is added
func setupMessageHandler() interface{} {
	if globalHandler == nil {
		return erl.OtpErlangAtom("error")
	}

	handler := func(message interface{}) {
		// For now, just accept messages without processing
		// Full implementation requires Call functionality (Phase 3)
		_ = message
	}

	globalHandler.SetMessageHandler(handler)
	return erl.OtpErlangAtom("ok")
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
	globalHandler = handler // Set global handler for cast operations

	handler.Register("identity", identity)
	handler.Register("add", add)
	handler.Register("length", length)
	handler.Register("recurse", recurse)
	handler.Register("setup_message_handler", setupMessageHandler)

	handler.Start()
}
