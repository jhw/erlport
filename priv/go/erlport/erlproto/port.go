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

package erlproto

import (
	"encoding/binary"
	"fmt"
	"io"
	"os"
	"sync"

	"github.com/okeuday/erlang_go/src/erlang"
)

// Port represents an Erlang port for communication
type Port struct {
	packet     int
	compressed int
	bufferSize int
	inFd       *os.File
	outFd      *os.File
	readLock   sync.Mutex
	writeLock  sync.Mutex
	buffer     []byte
}

// NewPort creates a new port for Erlang communication
func NewPort(packet int, useStdio bool, compressed int, bufferSize int) (*Port, error) {
	if bufferSize < 1 {
		return nil, fmt.Errorf("invalid buffer size value: %d", bufferSize)
	}
	if packet != 1 && packet != 2 && packet != 4 {
		return nil, fmt.Errorf("invalid packet size value: %d", packet)
	}
	if compressed < 0 || compressed > 9 {
		return nil, fmt.Errorf("invalid compressed level: %d", compressed)
	}

	var inFd, outFd *os.File
	if useStdio {
		inFd = os.Stdin
		outFd = os.Stdout
	} else {
		inFd = os.NewFile(3, "fd3")
		outFd = os.NewFile(4, "fd4")
	}

	return &Port{
		packet:     packet,
		compressed: compressed,
		bufferSize: bufferSize,
		inFd:       inFd,
		outFd:      outFd,
		buffer:     make([]byte, 0, bufferSize),
	}, nil
}

// Read reads an incoming message from the port
func (p *Port) Read() (interface{}, error) {
	p.readLock.Lock()
	defer p.readLock.Unlock()

	// Read packet length header
	for len(p.buffer) < p.packet {
		buf := make([]byte, p.bufferSize)
		n, err := p.inFd.Read(buf)
		if err != nil {
			if err == io.EOF {
				return nil, io.EOF
			}
			return nil, err
		}
		if n == 0 {
			return nil, io.EOF
		}
		p.buffer = append(p.buffer, buf[:n]...)
	}

	// Parse length
	var length uint32
	switch p.packet {
	case 1:
		length = uint32(p.buffer[0])
	case 2:
		length = uint32(binary.BigEndian.Uint16(p.buffer[:2]))
	case 4:
		length = binary.BigEndian.Uint32(p.buffer[:4])
	}

	totalLength := p.packet + int(length)

	// Read full message
	for len(p.buffer) < totalLength {
		buf := make([]byte, p.bufferSize)
		n, err := p.inFd.Read(buf)
		if err != nil {
			if err == io.EOF {
				return nil, io.EOF
			}
			return nil, err
		}
		if n == 0 {
			return nil, io.EOF
		}
		p.buffer = append(p.buffer, buf[:n]...)
	}

	// Decode term
	termData := p.buffer[p.packet:totalLength]
	term, err := erlang.BinaryToTerm(termData)
	if err != nil {
		return nil, fmt.Errorf("failed to decode term: %v", err)
	}

	// Update buffer
	p.buffer = p.buffer[totalLength:]

	return term, nil
}

// Write writes an outgoing message to the port
func (p *Port) Write(message interface{}) error {
	p.writeLock.Lock()
	defer p.writeLock.Unlock()

	// Encode term
	var data []byte
	var err error
	if p.compressed > 0 {
		data, err = erlang.TermToBinary(message, p.compressed)
	} else {
		data, err = erlang.TermToBinary(message, -1)
	}
	if err != nil {
		return fmt.Errorf("failed to encode term: %v", err)
	}

	// Prepare packet with length header
	length := len(data)
	var header []byte
	switch p.packet {
	case 1:
		if length > 255 {
			return fmt.Errorf("message too large for packet size 1: %d bytes", length)
		}
		header = []byte{byte(length)}
	case 2:
		if length > 65535 {
			return fmt.Errorf("message too large for packet size 2: %d bytes", length)
		}
		header = make([]byte, 2)
		binary.BigEndian.PutUint16(header, uint16(length))
	case 4:
		header = make([]byte, 4)
		binary.BigEndian.PutUint32(header, uint32(length))
	}

	// Write header + data
	fullData := append(header, data...)
	written := 0
	for written < len(fullData) {
		n, err := p.outFd.Write(fullData[written:])
		if err != nil {
			return err
		}
		if n == 0 {
			return io.EOF
		}
		written += n
	}

	return nil
}

// Close closes the port
func (p *Port) Close() error {
	if p.inFd != os.Stdin {
		p.inFd.Close()
	}
	if p.outFd != os.Stdout {
		p.outFd.Close()
	}
	return nil
}
