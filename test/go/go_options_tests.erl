%%% Copyright (c) 2009-2015, Dmitry Vasiliev <dima@hlabs.org>
%%% All rights reserved.
%%%
%%% Redistribution and use in source and binary forms, with or without
%%% modification, are permitted provided that the following conditions are met:
%%%
%%%  * Redistributions of source code must retain the above copyright notice,
%%%    this list of conditions and the following disclaimer.
%%%  * Redistributions in binary form must reproduce the above copyright
%%%    notice, this list of conditions and the following disclaimer in the
%%%    documentation and/or other materials provided with the distribution.
%%%  * Neither the name of the copyright holders nor the names of its
%%%    contributors may be used to endorse or promote products derived from
%%%    this software without specific prior written permission.
%%%
%%% THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
%%% AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
%%% IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
%%% ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE
%%% LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
%%% CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
%%% SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
%%% INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
%%% CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
%%% ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
%%% POSSIBILITY OF SUCH DAMAGE.

-module(go_options_tests).

-include_lib("eunit/include/eunit.hrl").
-include_lib("kernel/include/file.hrl").
-include("go.hrl").

%%%
%%% go_binary is required (no default, Lambda-style)
%%%

go_default_test() ->
    % With Lambda-style, go_binary is required - no default
    ?assertMatch({error, {missing_option, go_binary, _}},
        go_options:parse([])).

%%%
%%% go_binary option tests (Lambda-style)
%%%

go_binary_missing_test() ->
    % Without go_binary option, should error
    ?assertMatch({error, {missing_option, go_binary, _}},
        go_options:parse([])).

go_binary_not_found_test() ->
    ?assertMatch({error, {go_binary_not_found, _}},
        go_options:parse([{go_binary, "nonexistent_binary_12345"}])).

go_binary_valid_test() ->
    % Create a temporary executable binary for testing
    TempBinary = "test/go/.erlport_test_temp/test_binary",
    ok = filelib:ensure_dir(TempBinary),
    file:write_file(TempBinary, <<"#!/bin/sh\necho test\n">>),
    os:cmd(lists:concat(["chmod +x ", TempBinary])),

    try
        {ok, Options} = go_options:parse([{go_binary, TempBinary}]),
        ?assert(is_record(Options, go_options)),
        Go = Options#go_options.go,
        ?assert(is_list(Go)),
        ?assert(filelib:is_regular(Go))
    after
        file:delete(TempBinary)
    end.

go_binary_not_executable_test() ->
    % Create a temporary non-executable file
    TempFile = "test/go/.erlport_test_temp/not_executable",
    ok = filelib:ensure_dir(TempFile),
    file:write_file(TempFile, <<"test">>),
    os:cmd(lists:concat(["chmod -x ", TempFile])),

    try
        ?assertMatch({error, {go_binary_not_executable, _}},
            go_options:parse([{go_binary, TempFile}]))
    after
        file:delete(TempFile)
    end.

%%%
%%% go_path option tests
%%%

go_path_test() ->
    % Create a temporary executable for the test
    TempBinary = "test/go/.erlport_test_temp/test_binary_gopath",
    ok = filelib:ensure_dir(TempBinary),
    file:write_file(TempBinary, <<"#!/bin/sh\necho test\n">>),
    os:cmd(lists:concat(["chmod +x ", TempBinary])),

    try
        {ok, Options} = go_options:parse([{go_binary, TempBinary}, {go_path, "/tmp/test_gopath"}]),
        ?assert(is_list(Options#go_options.go_path)),
        ?assert(string:str(Options#go_options.go_path, "/tmp/test_gopath") > 0)
    after
        file:delete(TempBinary)
    end.

go_path_list_test() ->
    % Create a temporary executable for the test
    TempBinary = "test/go/.erlport_test_temp/test_binary_gopath_list",
    ok = filelib:ensure_dir(TempBinary),
    file:write_file(TempBinary, <<"#!/bin/sh\necho test\n">>),
    os:cmd(lists:concat(["chmod +x ", TempBinary])),

    try
        {ok, Options} = go_options:parse([{go_binary, TempBinary}, {go_path, ["/tmp/path1", "/tmp/path2"]}]),
        GoPath = Options#go_options.go_path,
        ?assert(is_list(GoPath)),
        ?assert(string:str(GoPath, "/tmp/path1") > 0),
        ?assert(string:str(GoPath, "/tmp/path2") > 0)
    after
        file:delete(TempBinary)
    end.

go_path_invalid_test() ->
    ?assertMatch({error, {invalid_option, _, _}},
        go_options:parse([{go_path, ["/tmp/valid", invalid_path]}])).

%%%
%%% Common erlport option tests
%%%

use_stdio_test() ->
    TempBinary = "test/go/.erlport_test_temp/test_binary_stdio",
    ok = filelib:ensure_dir(TempBinary),
    file:write_file(TempBinary, <<"#!/bin/sh\necho test\n">>),
    os:cmd(lists:concat(["chmod +x ", TempBinary])),

    try
        {ok, Options} = go_options:parse([{go_binary, TempBinary}, use_stdio]),
        ?assertEqual(use_stdio, Options#go_options.use_stdio)
    after
        file:delete(TempBinary)
    end.

nouse_stdio_test() ->
    TempBinary = "test/go/.erlport_test_temp/test_binary_nouse_stdio",
    ok = filelib:ensure_dir(TempBinary),
    file:write_file(TempBinary, <<"#!/bin/sh\necho test\n">>),
    os:cmd(lists:concat(["chmod +x ", TempBinary])),

    try
        {ok, Options} = go_options:parse([{go_binary, TempBinary}, nouse_stdio]),
        ?assertEqual(nouse_stdio, Options#go_options.use_stdio)
    after
        file:delete(TempBinary)
    end.

compressed_test() ->
    TempBinary = "test/go/.erlport_test_temp/test_binary_compressed",
    ok = filelib:ensure_dir(TempBinary),
    file:write_file(TempBinary, <<"#!/bin/sh\necho test\n">>),
    os:cmd(lists:concat(["chmod +x ", TempBinary])),

    try
        {ok, Options} = go_options:parse([{go_binary, TempBinary}, {compressed, 6}]),
        ?assertEqual(6, Options#go_options.compressed)
    after
        file:delete(TempBinary)
    end.

compressed_invalid_test() ->
    ?assertMatch({error, {invalid_option, {compressed, _}}},
        go_options:parse([{compressed, 10}])).

packet_test() ->
    TempBinary = "test/go/.erlport_test_temp/test_binary_packet",
    ok = filelib:ensure_dir(TempBinary),
    file:write_file(TempBinary, <<"#!/bin/sh\necho test\n">>),
    os:cmd(lists:concat(["chmod +x ", TempBinary])),

    try
        {ok, Options} = go_options:parse([{go_binary, TempBinary}, {packet, 2}]),
        ?assertEqual(2, Options#go_options.packet)
    after
        file:delete(TempBinary)
    end.

packet_invalid_test() ->
    ?assertMatch({error, {invalid_option, {packet, _}}},
        go_options:parse([{packet, 3}])).

buffer_size_test() ->
    TempBinary = "test/go/.erlport_test_temp/test_binary_bufsize",
    ok = filelib:ensure_dir(TempBinary),
    file:write_file(TempBinary, <<"#!/bin/sh\necho test\n">>),
    os:cmd(lists:concat(["chmod +x ", TempBinary])),

    try
        {ok, Options} = go_options:parse([{go_binary, TempBinary}, {buffer_size, 32768}]),
        ?assertEqual(32768, Options#go_options.buffer_size)
    after
        file:delete(TempBinary)
    end.

buffer_size_invalid_test() ->
    ?assertMatch({error, {invalid_option, {buffer_size, _}}},
        go_options:parse([{buffer_size, 0}])).
