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
%%% go option tests
%%%

go_default_test() ->
    case os:find_executable("go") of
        false ->
            ok;  % Skip test if Go not installed
        _ ->
            {ok, #go_options{go=Go}} = go_options:parse([]),
            % Just check that Go was found, don't check exact path
            ?assert(is_list(Go)),
            ?assert(length(Go) > 0)
    end.

go_from_env_test() ->
    case os:find_executable("go") of
        false ->
            ok;  % Skip test if Go not installed
        GoPath ->
            os:putenv("ERLPORT_GO", GoPath),
            try
                {ok, #go_options{go=Go}} = go_options:parse([]),
                ?assertEqual(GoPath, Go)
            after
                os:unsetenv("ERLPORT_GO")
            end
    end.

go_not_found_test() ->
    ?assertMatch({error, {invalid_option, {go, _}, not_found}},
        go_options:parse([{go, "nonexistent_go_binary_12345"}])).

go_invalid_test() ->
    ?assertMatch({error, {invalid_option, {go, _}}},
        go_options:parse([{go, invalid}])).

%%%
%%% go_src option tests
%%%

go_src_not_found_test() ->
    ?assertMatch({error, {go_src_not_found, _}},
        go_options:parse([{go_src, "nonexistent_file.go"}])).

go_src_valid_test() ->
    case os:find_executable("go") of
        false ->
            ok;  % Skip test if Go not installed
        _ ->
            % Use our test utils as a valid Go source file
            SrcPath = "test/go/test_utils.go",
            case filelib:is_regular(SrcPath) of
                true ->
                    {ok, Options} = go_options:parse([{go_src, SrcPath}]),
                    % Should have compiled binary path
                    ?assert(is_record(Options, go_options)),
                    Go = Options#go_options.go,
                    ?assert(is_list(Go)),
                    % Binary should exist in cache
                    ?assert(filelib:is_regular(Go));
                false ->
                    ok  % Skip if test file doesn't exist
            end
    end.

go_src_caching_test() ->
    case os:find_executable("go") of
        false ->
            ok;  % Skip test if Go not installed
        _ ->
            SrcPath = "test/go/test_utils.go",
            case filelib:is_regular(SrcPath) of
                true ->
                    % First compilation
                    {ok, Options1} = go_options:parse([{go_src, SrcPath}]),
                    BinaryPath = Options1#go_options.go,
                    ?assert(filelib:is_regular(BinaryPath)),

                    % Get initial mtime
                    {ok, FileInfo1} = file:read_file_info(BinaryPath),
                    MTime1 = FileInfo1#file_info.mtime,

                    % Wait a bit to ensure different mtime if recompiled
                    timer:sleep(1100),

                    % Second compilation - should use cache
                    {ok, Options2} = go_options:parse([{go_src, SrcPath}]),
                    BinaryPath2 = Options2#go_options.go,
                    ?assertEqual(BinaryPath, BinaryPath2),

                    % Check mtime hasn't changed (binary wasn't recompiled)
                    {ok, FileInfo2} = file:read_file_info(BinaryPath2),
                    MTime2 = FileInfo2#file_info.mtime,
                    ?assertEqual(MTime1, MTime2);
                false ->
                    ok
            end
    end.

go_src_recompile_on_change_test() ->
    case os:find_executable("go") of
        false ->
            ok;  % Skip test if Go not installed
        _ ->
            SrcPath = "test/go/test_utils.go",
            case filelib:is_regular(SrcPath) of
                true ->
                    % First compilation
                    {ok, Options1} = go_options:parse([{go_src, SrcPath}]),
                    BinaryPath = Options1#go_options.go,
                    ?assert(filelib:is_regular(BinaryPath)),

                    % Get initial mtime of both source and binary
                    {ok, SrcInfo1} = file:read_file_info(SrcPath),
                    SrcMTime1 = SrcInfo1#file_info.mtime,
                    {ok, BinInfo1} = file:read_file_info(BinaryPath),
                    BinMTime1 = BinInfo1#file_info.mtime,

                    % Wait to ensure different timestamp
                    timer:sleep(1100),

                    % Touch source file to make it newer
                    Now = erlang:localtime(),
                    ok = file:write_file_info(SrcPath, #file_info{mtime = Now}),

                    % Verify source is now newer
                    {ok, SrcInfo2} = file:read_file_info(SrcPath),
                    SrcMTime2 = SrcInfo2#file_info.mtime,
                    ?assert(SrcMTime2 > SrcMTime1),

                    % Second compilation - should recompile because source is newer
                    {ok, Options2} = go_options:parse([{go_src, SrcPath}]),
                    BinaryPath2 = Options2#go_options.go,
                    ?assertEqual(BinaryPath, BinaryPath2),

                    % Check binary mtime has changed (binary was recompiled)
                    {ok, BinInfo2} = file:read_file_info(BinaryPath2),
                    BinMTime2 = BinInfo2#file_info.mtime,
                    ?assert(BinMTime2 > BinMTime1),

                    % Restore original source mtime
                    ok = file:write_file_info(SrcPath, SrcInfo1);
                false ->
                    ok
            end
    end.

%%%
%%% go_path option tests
%%%

go_path_test() ->
    case os:find_executable("go") of
        false ->
            ok;
        _ ->
            {ok, Options} = go_options:parse([{go_path, "/tmp/test_gopath"}]),
            ?assert(is_list(Options#go_options.go_path)),
            ?assert(string:str(Options#go_options.go_path, "/tmp/test_gopath") > 0)
    end.

go_path_list_test() ->
    case os:find_executable("go") of
        false ->
            ok;
        _ ->
            {ok, Options} = go_options:parse([{go_path, ["/tmp/path1", "/tmp/path2"]}]),
            GoPath = Options#go_options.go_path,
            ?assert(is_list(GoPath)),
            ?assert(string:str(GoPath, "/tmp/path1") > 0),
            ?assert(string:str(GoPath, "/tmp/path2") > 0)
    end.

go_path_invalid_test() ->
    ?assertMatch({error, {invalid_option, _, _}},
        go_options:parse([{go_path, ["/tmp/valid", invalid_path]}])).

%%%
%%% Common erlport option tests
%%%

use_stdio_test() ->
    case os:find_executable("go") of
        false ->
            ok;
        _ ->
            {ok, Options} = go_options:parse([use_stdio]),
            ?assertEqual(use_stdio, Options#go_options.use_stdio)
    end.

nouse_stdio_test() ->
    case os:find_executable("go") of
        false ->
            ok;
        _ ->
            {ok, Options} = go_options:parse([nouse_stdio]),
            ?assertEqual(nouse_stdio, Options#go_options.use_stdio)
    end.

compressed_test() ->
    case os:find_executable("go") of
        false ->
            ok;
        _ ->
            {ok, Options} = go_options:parse([{compressed, 6}]),
            ?assertEqual(6, Options#go_options.compressed)
    end.

compressed_invalid_test() ->
    ?assertMatch({error, {invalid_option, {compressed, _}}},
        go_options:parse([{compressed, 10}])).

packet_test() ->
    case os:find_executable("go") of
        false ->
            ok;
        _ ->
            {ok, Options} = go_options:parse([{packet, 2}]),
            ?assertEqual(2, Options#go_options.packet)
    end.

packet_invalid_test() ->
    ?assertMatch({error, {invalid_option, {packet, _}}},
        go_options:parse([{packet, 3}])).

buffer_size_test() ->
    case os:find_executable("go") of
        false ->
            ok;
        _ ->
            {ok, Options} = go_options:parse([{buffer_size, 32768}]),
            ?assertEqual(32768, Options#go_options.buffer_size)
    end.

buffer_size_invalid_test() ->
    ?assertMatch({error, {invalid_option, {buffer_size, _}}},
        go_options:parse([{buffer_size, 0}])).
