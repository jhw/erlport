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

package erlang

import (
	"erlport/erlport/erlproto"
	"fmt"
	"io"
	"os"
	"reflect"
	"runtime/debug"
	"sync"

	"github.com/okeuday/erlang_go/src/erlang"
)

type MessageHandler struct {
	port           *erlproto.Port
	handlers       map[string]interface{}
	messageHandler func(interface{})
	messageID      uint64
	responses      map[uint64]chan interface{}
	responseLock   sync.Mutex
	messageIDLock  sync.Mutex
}

// NewMessageHandler creates a new message handler
func NewMessageHandler(port *erlproto.Port) *MessageHandler {
	return &MessageHandler{
		port:      port,
		handlers:  make(map[string]interface{}),
		responses: make(map[uint64]chan interface{}),
		messageID: 0,
	}
}

// Register registers a function to be callable from Erlang
func (h *MessageHandler) Register(name string, fn interface{}) error {
	// Verify fn is actually a function
	fnType := reflect.TypeOf(fn)
	if fnType.Kind() != reflect.Func {
		return fmt.Errorf("expected function, got %v", fnType.Kind())
	}
	h.handlers[name] = fn
	return nil
}

// SetMessageHandler sets a handler for cast messages
func (h *MessageHandler) SetMessageHandler(handler func(interface{})) {
	h.messageHandler = handler
}

// Cast sends an asynchronous message to an Erlang process
func (h *MessageHandler) Cast(pid interface{}, message interface{}) error {
	// Message format: {'M', Pid, Message}
	// Note: pid and message are already Erlang terms, don't convert
	castMessage := erlang.OtpErlangTuple([]interface{}{
		erlang.OtpErlangAtom("M"),
		pid,
		message,
	})
	return h.port.Write(castMessage)
}

// nextMessageID generates the next message ID in a thread-safe manner
func (h *MessageHandler) nextMessageID() uint64 {
	h.messageIDLock.Lock()
	defer h.messageIDLock.Unlock()
	h.messageID++
	return h.messageID
}

// Call calls an Erlang function and waits for the response
func (h *MessageHandler) Call(module, function string, args []interface{}) (interface{}, error) {
	// Generate message ID
	msgID := h.nextMessageID()

	// Create response channel
	respChan := make(chan interface{}, 1)
	h.responseLock.Lock()
	h.responses[msgID] = respChan
	h.responseLock.Unlock()

	// Clean up response channel when done
	defer func() {
		h.responseLock.Lock()
		delete(h.responses, msgID)
		h.responseLock.Unlock()
		close(respChan)
	}()

	// Build call message: {'C', Id, Module, Function, Args, Context}
	// Context 'N' means normal (asynchronous spawn on Erlang side)
	callMessage := erlang.OtpErlangTuple([]interface{}{
		erlang.OtpErlangAtom("C"),
		msgID,
		erlang.OtpErlangAtom(module),
		erlang.OtpErlangAtom(function),
		erlang.OtpErlangList{Value: args},
		erlang.OtpErlangAtom("N"),
	})

	// Send the call
	err := h.port.Write(callMessage)
	if err != nil {
		return nil, fmt.Errorf("failed to send call: %v", err)
	}

	// Wait for response
	response := <-respChan

	// Normalize response (convert STRING_EXT and binaries properly)
	response = normalizeErlangTerm(response)

	// Check if it's an error response
	if responseTuple, ok := response.(erlang.OtpErlangTuple); ok {
		if len(responseTuple) >= 2 {
			if atom, ok := responseTuple[0].(erlang.OtpErlangAtom); ok && string(atom) == "error" {
				return nil, fmt.Errorf("erlang error: %v", responseTuple[1])
			}
		}
	}

	return response, nil
}

// Start begins the message processing loop
func (h *MessageHandler) Start() {
	h.start()
}

// start begins the message processing loop
func (h *MessageHandler) start() {
	for {
		message, err := h.port.Read()
		if err != nil {
			if err == io.EOF {
				break
			}
			fmt.Fprintf(os.Stderr, "Error reading message: %v\n", err)
			continue
		}

		// Check if this is a response message ('r' or 'e')
		// These must be handled synchronously to unblock waiting Call()s
		if tuple, ok := message.(erlang.OtpErlangTuple); ok && len(tuple) >= 2 {
			if msgTypeAtom, ok := tuple[0].(erlang.OtpErlangAtom); ok {
				msgType := string(msgTypeAtom)
				if msgType == "r" || msgType == "e" {
					// Handle response synchronously
					h.handleMessage(message)
					continue
				}
			}
		}

		// For call messages ('C'), handle in goroutine to avoid blocking message loop
		go func(msg interface{}) {
			response := h.handleMessage(msg)
			if response != nil {
				err := h.port.Write(response)
				if err != nil {
					fmt.Fprintf(os.Stderr, "Error writing response: %v\n", err)
				}
			}
		}(message)
	}
}

// handleMessage processes an incoming message and returns a response
func (h *MessageHandler) handleMessage(message interface{}) interface{} {
	defer func() {
		if r := recover(); r != nil {
			fmt.Printf("Panic in handleMessage: %v\n%s\n", r, debug.Stack())
		}
	}()

	// Message format: {MessageType, MessageID, ...}
	tuple, ok := message.(erlang.OtpErlangTuple)
	if !ok {
		return h.errorResponse(nil, "invalid_message", "Expected tuple", nil)
	}

	if len(tuple) < 2 {
		return h.errorResponse(nil, "invalid_message", "Tuple too short", nil)
	}

	// Get message type (atom: 'C' for call, 'M' for message, 'P' for print)
	msgTypeAtom, ok := tuple[0].(erlang.OtpErlangAtom)
	if !ok {
		return h.errorResponse(nil, "invalid_message", fmt.Sprintf("Expected atom for message type, got %T", tuple[0]), nil)
	}
	msgType := string(msgTypeAtom)

	// Get message ID
	msgID := tuple[1]

	switch msgType {
	case "C": // Call
		// Format: {'C', Id, Module, Function, Args} or {'C', Id, Module, Function, Args, Context}
		if len(tuple) < 5 {
			return h.errorResponse(msgID, "invalid_message", "Call message too short", nil)
		}
		return h.handleCall(msgID, tuple[2:])
	case "M": // Message (cast)
		// Format: {'M', Payload} (no message ID for casts)
		if len(tuple) < 2 {
			return nil
		}
		return h.handleCast(tuple[1:])
	case "r": // Response (success)
		// Format: {'r', Id, Result}
		h.handleResponse(msgID, tuple[2])
		return nil
	case "e": // Response (error)
		// Format: {'e', Id, Error}
		h.handleResponse(msgID, erlang.OtpErlangTuple([]interface{}{
			erlang.OtpErlangAtom("error"),
			tuple[2],
		}))
		return nil
	case "P": // Print
		// Handle print messages
		return nil
	default:
		return h.errorResponse(msgID, "unknown_message", fmt.Sprintf("Unknown message type: %s", msgType), nil)
	}
}

// handleResponse routes a response to the appropriate waiting channel
func (h *MessageHandler) handleResponse(msgID interface{}, result interface{}) {
	// Convert msgID to uint64
	var id uint64
	switch v := msgID.(type) {
	case uint64:
		id = v
	case uint:
		id = uint64(v)
	case uint8:
		id = uint64(v)
	case uint16:
		id = uint64(v)
	case uint32:
		id = uint64(v)
	case int:
		id = uint64(v)
	case int8:
		id = uint64(v)
	case int16:
		id = uint64(v)
	case int32:
		id = uint64(v)
	case int64:
		id = uint64(v)
	default:
		fmt.Fprintf(os.Stderr, "Invalid message ID type: %T\n", msgID)
		return
	}

	// Find the response channel
	h.responseLock.Lock()
	respChan, exists := h.responses[id]
	h.responseLock.Unlock()

	if !exists {
		fmt.Fprintf(os.Stderr, "No response channel for message ID: %d\n", id)
		return
	}

	// Send the response (blocking - channel is buffered)
	respChan <- result
}

// normalizeErlangTerm converts STRING_EXT strings to OtpErlangLists recursively
func normalizeErlangTerm(term interface{}) interface{} {
	switch v := term.(type) {
	case string:
		// STRING_EXT: convert to OtpErlangList of integers
		listValues := make([]interface{}, len(v))
		for i, b := range []byte(v) {
			listValues[i] = uint8(b)
		}
		return erlang.OtpErlangList{Value: listValues}
	case erlang.OtpErlangList:
		// Recursively normalize list elements
		normalized := make([]interface{}, len(v.Value))
		for i, elem := range v.Value {
			normalized[i] = normalizeErlangTerm(elem)
		}
		return erlang.OtpErlangList{Value: normalized}
	case erlang.OtpErlangTuple:
		// Recursively normalize tuple elements
		normalized := make([]interface{}, len(v))
		for i, elem := range v {
			normalized[i] = normalizeErlangTerm(elem)
		}
		return erlang.OtpErlangTuple(normalized)
	default:
		// Other types pass through
		return term
	}
}

// handleCall processes a function call request
func (h *MessageHandler) handleCall(msgID interface{}, args []interface{}) interface{} {
	if len(args) < 3 {
		return h.errorResponse(msgID, "invalid_call", "Expected module, function, args", nil)
	}

	// Extract module, function, and arguments
	_, ok := args[0].(erlang.OtpErlangAtom)
	if !ok {
		return h.errorResponse(msgID, "invalid_call", "Module must be atom", nil)
	}

	functionAtom, ok := args[1].(erlang.OtpErlangAtom)
	if !ok {
		return h.errorResponse(msgID, "invalid_call", "Function must be atom", nil)
	}

	// Normalize args to convert STRING_EXT to proper OtpErlangLists
	normalizedArgs := normalizeErlangTerm(args[2])

	// Args should be a list
	var callArgsSlice []interface{}
	switch v := normalizedArgs.(type) {
	case erlang.OtpErlangList:
		callArgsSlice = v.Value
	default:
		return h.errorResponse(msgID, "invalid_call", fmt.Sprintf("Args must be list, got %T: %+v", normalizedArgs, normalizedArgs), nil)
	}

	// For now, we ignore the module and just look up by function name
	// In a full implementation, you might want to support module namespacing
	functionName := string(functionAtom)

	handler, exists := h.handlers[functionName]
	if !exists {
		return h.errorResponse(msgID, "undef", fmt.Sprintf("Function not found: %s", functionName), nil)
	}

	// Call the function using reflection
	result, err := h.callFunction(handler, callArgsSlice)
	if err != nil {
		return h.errorResponse(msgID, "call_error", fmt.Sprintf("Error calling function: %v", err), nil)
	}

	// Return success response: {'r', MessageID, Result}
	return erlang.OtpErlangTuple([]interface{}{
		erlang.OtpErlangAtom("r"),
		msgID,
		result,
	})
}

// handleCast processes an async message (cast)
func (h *MessageHandler) handleCast(args []interface{}) interface{} {
	// Message format: {'M', Payload}
	if len(args) < 1 {
		return nil
	}

	payload := args[0]

	// If a message handler is registered, call it
	if h.messageHandler != nil {
		// Normalize the payload to convert STRING_EXT
		normalizedPayload := normalizeErlangTerm(payload)

		// Call the handler in a goroutine to not block message processing
		go func() {
			defer func() {
				if r := recover(); r != nil {
					fmt.Fprintf(os.Stderr, "Panic in message handler: %v\n%s\n", r, debug.Stack())
				}
			}()
			h.messageHandler(normalizedPayload)
		}()
	}

	return nil
}

// callFunction uses reflection to call a registered Go function
func (h *MessageHandler) callFunction(fn interface{}, args []interface{}) (interface{}, error) {
	fnValue := reflect.ValueOf(fn)
	fnType := fnValue.Type()

	// Check argument count
	if fnType.NumIn() != len(args) {
		return nil, fmt.Errorf("expected %d arguments, got %d", fnType.NumIn(), len(args))
	}

	// Convert arguments to Go values
	in := make([]reflect.Value, len(args))
	for i, arg := range args {
		expectedType := fnType.In(i)

		// If function expects interface{}, pass raw Erlang term without conversion
		if expectedType.Kind() == reflect.Interface && expectedType.NumMethod() == 0 {
			in[i] = reflect.ValueOf(arg)
			continue
		}

		// Otherwise convert from Erlang to Go
		converted := convertErlangToGo(arg)
		argValue := reflect.ValueOf(converted)

		// Try to convert to the expected type if possible
		if argValue.Type().ConvertibleTo(expectedType) {
			in[i] = argValue.Convert(expectedType)
		} else {
			in[i] = argValue
		}
	}

	// Call function
	out := fnValue.Call(in)

	// Handle return values
	if len(out) == 0 {
		return erlang.OtpErlangAtom("ok"), nil
	} else if len(out) == 1 {
		return convertGoToErlang(out[0].Interface()), nil
	} else {
		// Multiple return values - return as tuple
		values := make([]interface{}, len(out))
		for i, v := range out {
			values[i] = convertGoToErlang(v.Interface())
		}
		return erlang.OtpErlangTuple(values), nil
	}
}

// errorResponse creates an error response tuple
func (h *MessageHandler) errorResponse(msgID interface{}, errorType string, message string, stacktrace interface{}) interface{} {
	if stacktrace == nil {
		stacktrace = erlang.OtpErlangList{Value: []interface{}{}}
	}

	errorTuple := erlang.OtpErlangTuple([]interface{}{
		erlang.OtpErlangAtom("go"),
		erlang.OtpErlangAtom(errorType),
		erlang.OtpErlangBinary{Value: []byte(message), Bits: 8},
		stacktrace,
	})

	return erlang.OtpErlangTuple([]interface{}{
		erlang.OtpErlangAtom("e"),
		msgID,
		errorTuple,
	})
}

// convertErlangToGo converts Erlang terms to Go values
func convertErlangToGo(term interface{}) interface{} {
	switch v := term.(type) {
	case erlang.OtpErlangAtom:
		switch string(v) {
		case "true":
			return true
		case "false":
			return false
		case "nil", "undefined":
			return nil
		default:
			return string(v)
		}
	case erlang.OtpErlangBinary:
		return string(v.Value)
	case erlang.OtpErlangList:
		result := make([]interface{}, len(v.Value))
		for i, item := range v.Value {
			result[i] = convertErlangToGo(item)
		}
		return result
	case erlang.OtpErlangTuple:
		result := make([]interface{}, len(v))
		for i, item := range v {
			result[i] = convertErlangToGo(item)
		}
		return result
	case int, int8, int16, int32, int64, uint, uint8, uint16, uint32, uint64, float32, float64:
		return v
	default:
		return v
	}
}

// convertGoToErlang converts Go values to Erlang terms
func convertGoToErlang(value interface{}) interface{} {
	if value == nil {
		return erlang.OtpErlangAtom("undefined")
	}

	switch v := value.(type) {
	// Raw Erlang terms - return as-is
	case erlang.OtpErlangAtom:
		return v
	case erlang.OtpErlangBinary:
		// Ensure Bits is set properly
		return erlang.OtpErlangBinary{Value: v.Value, Bits: 8}
	case erlang.OtpErlangList:
		return v
	case erlang.OtpErlangTuple:
		return v
	// Go native types - convert to Erlang
	case bool:
		if v {
			return erlang.OtpErlangAtom("true")
		}
		return erlang.OtpErlangAtom("false")
	case string:
		return erlang.OtpErlangBinary{Value: []byte(v), Bits: 8}
	case []byte:
		return erlang.OtpErlangBinary{Value: v, Bits: 8}
	case []interface{}:
		return erlang.OtpErlangList{Value: v}
	case int, int8, int16, int32, int64, uint, uint8, uint16, uint32, uint64, float32, float64:
		return v
	default:
		// For other types, try to return as-is (might already be an Erlang term)
		return v
	}
}
