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
// Note: Simplified to avoid opaque Pid issues in Go
// Just makes callbacks and counts down
func recurse(go_instance interface{}, n int) interface{} {
	if globalHandler == nil {
		return erl.OtpErlangAtom("error")
	}

	// Call back to Erlang: go_tests:recurse_helper(N)
	result, err := globalHandler.Call("go_tests", "recurse_helper", []interface{}{n})

	if err != nil {
		return erl.OtpErlangAtom("error")
	}

	// If we get 'done', return it
	if atom, ok := result.(erl.OtpErlangAtom); ok {
		if string(atom) == "done" {
			return atom
		}
	}

	// Otherwise result should be N-1, recurse again
	// Try various integer types
	if nextN, ok := result.(int); ok {
		return recurse(go_instance, nextN)
	}
	if nextN, ok := result.(uint8); ok {
		return recurse(go_instance, int(nextN))
	}
	if nextN, ok := result.(int64); ok {
		return recurse(go_instance, int(nextN))
	}

	return erl.OtpErlangAtom("error")
}

// Switch function - makes multiple callbacks to Erlang in a loop
func switchFunc(n int) interface{} {
	if globalHandler == nil {
		return erl.OtpErlangAtom("error")
	}

	result := 0
	for i := 0; i < n; i++ {
		// Call go_tests:test_callback({Result, I})
		response, err := globalHandler.Call("go_tests", "test_callback", []interface{}{
			erl.OtpErlangTuple([]interface{}{result, i}),
		})

		if err != nil {
			fmt.Fprintf(os.Stderr, "Switch callback error: %v\n", err)
			return erl.OtpErlangAtom("error")
		}

		// Response is a tuple {Result, NewValue}
		if tuple, ok := response.(erl.OtpErlangTuple); ok && len(tuple) == 2 {
			// Extract the new result value
			if newResult, ok := tuple[1].(int); ok {
				result = newResult
			} else if newResult, ok := tuple[1].(uint8); ok {
				result = int(newResult)
			}
		}
	}

	return n
}

// SetupMessageHandler sets up a message handler that calls back to Erlang
func setupMessageHandler() interface{} {
	if globalHandler == nil {
		return erl.OtpErlangAtom("error")
	}

	handler := func(message interface{}) {
		// Call back to go_tests:test_callback with {message, Message}
		messageTuple := erl.OtpErlangTuple([]interface{}{
			erl.OtpErlangAtom("message"),
			message,
		})

		_, err := globalHandler.Call("go_tests", "test_callback", []interface{}{
			messageTuple,
		})

		if err != nil {
			fmt.Fprintf(os.Stderr, "Message handler callback error: %v\n", err)
		}
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
	handler.Register("switch", switchFunc)
	handler.Register("setup_message_handler", setupMessageHandler)

	handler.Start()
}
