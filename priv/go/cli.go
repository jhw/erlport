// Copyright (c) 2009-2015, Dmitry Vasiliev <dima@hlabs.org>
// All rights reserved.
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are met:
//
//  * Redistributions of source code must retain the above copyright notice,
//    this list of conditions and the following disclaimer.
//  * Redistributions in binary form must reproduce the above copyright notice,
//    this list of conditions and the following disclaimer in the documentation
//    and/or other materials provided with the distribution.
//  * Neither the name of the copyright holders nor the names of its
//    contributors may be used to endorse or promote products derived from this
//    software without specific prior written permission.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
// AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
// IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
// ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE
// LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
// CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
// SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
// INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
// CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
// ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
// POSSIBILITY OF SUCH DAMAGE.

package main

import (
	"flag"
	"fmt"
	"os"
)

// This is a placeholder CLI that will be replaced by user code
// Users should create their own main.go that imports erlport packages

func main() {
	fmt.Fprintf(os.Stderr, "Error: This is the ErlPort Go runtime library.\n")
	fmt.Fprintf(os.Stderr, "Users must create their own Go program that imports:\n")
	fmt.Fprintf(os.Stderr, "  - erlport/erlport/erlproto\n")
	fmt.Fprintf(os.Stderr, "  - erlport/erlport/erlang\n")
	fmt.Fprintf(os.Stderr, "\nSee test/go/test_utils.go for an example.\n")
	os.Exit(1)
}

// ParseFlags is a helper function users can call from their main.go
func ParseFlags() (packet int, useStdio bool, compressed int, bufferSize int) {
	var stdio bool
	var noUseStdio bool

	flag.IntVar(&packet, "packet", 4, "Message length sent in N bytes. Valid values are 1, 2, or 4")
	flag.BoolVar(&stdio, "use_stdio", true, "Use file descriptors 0 and 1 for communication with Erlang")
	flag.BoolVar(&noUseStdio, "nouse_stdio", false, "Use file descriptors 3 and 4 for communication with Erlang")
	flag.IntVar(&compressed, "compressed", 0, "Compression level (0-9)")
	flag.IntVar(&bufferSize, "buffer_size", 65536, "Receive buffer size")

	flag.Parse()

	// Validate packet size
	if packet != 1 && packet != 2 && packet != 4 {
		fmt.Fprintf(os.Stderr, "Valid values for --packet are 1, 2, or 4\n")
		os.Exit(2)
	}

	// Validate compression level
	if compressed < 0 || compressed > 9 {
		fmt.Fprintf(os.Stderr, "Valid values for --compressed are 0..9\n")
		os.Exit(2)
	}

	// Validate buffer size
	if bufferSize <= 0 {
		fmt.Fprintf(os.Stderr, "Buffer size value should be greater than 0\n")
		os.Exit(2)
	}

	// Handle stdio flag
	useStdio = stdio && !noUseStdio

	return
}
