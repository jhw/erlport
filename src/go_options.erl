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

%%%
%%% @doc Go options handling
%%% @author Dmitry Vasiliev <dima@hlabs.org>
%%% @copyright 2009-2015 Dmitry Vasiliev <dima@hlabs.org>
%%% @private
%%%

-module(go_options).

-author('Dmitry Vasiliev <dima@hlabs.org>').

-export([
    parse/1
    ]).

-type option() :: {go, Go :: string()}
    | {go_src, SrcPath :: string()}
    | {go_path, Path :: string() | [Path :: string()]}
    | erlport_options:option().
-type options() :: [option()].

-export_type([option/0, options/0]).

-include("go.hrl").


%%
%% @doc Parse Go options
%%

-spec parse(Options::options()) ->
    {ok, #go_options{}} | {error, Reason::term()}.

parse(Options) when is_list(Options) ->
    parse(Options, #go_options{}).

parse([{go, Go} | Tail], Options) ->
    % Will be checked later
    parse(Tail, Options#go_options{go=Go});
parse([{go_src, GoSrc} | Tail], Options) ->
    % Will be validated and compiled later
    parse(Tail, Options#go_options{go_src=GoSrc});
parse([{go_path, GoPath}=Value | Tail], Options) ->
    case erlport_options:filter_invalid_paths(GoPath) of
        {ok, Path} ->
            % Paths will be checked later
            parse(Tail, Options#go_options{go_path=Path});
        {error, Invalid} ->
            {error, {invalid_option, Value, Invalid}}
    end;
parse([Option | Tail], Options) ->
    case erlport_options:parse(Option) of
        {ok, Name, Value} ->
            parse(Tail, set_by_name(Name, Value, Options));
        {error, _}=Error ->
            Error
    end;
parse([], Options=#go_options{env=Env0, go_path=GoPath0,
        go=Go, go_src=GoSrc, port_options=PortOptions, packet=Packet,
        cd=Path, use_stdio=UseStdio}) ->
    PortOptions1 = erlport_options:update_port_options(
        PortOptions, Path, UseStdio),
    case get_go(Go) of
        {ok, GoCmd, _MajVersion} ->
            case update_go_path(Env0, GoPath0) of
                {ok, GoPath, Env} ->
                    % Handle Go source compilation if specified
                    case GoSrc of
                        undefined ->
                            % No source specified, use Go command directly (won't work)
                            {ok, Options#go_options{env=Env,
                                go_path=GoPath, go=GoCmd,
                                port_options=[{env, Env}, {packet, Packet}
                                    | PortOptions1]}};
                        SrcPath ->
                            % Compile source and return binary path
                            case compile_go_source(GoCmd, SrcPath, GoPath, Env) of
                                {ok, BinaryPath} ->
                                    {ok, Options#go_options{env=Env,
                                        go_path=GoPath, go=BinaryPath,
                                        port_options=[{env, Env}, {packet, Packet}
                                            | PortOptions1]}};
                                {error, _}=CompileError ->
                                    CompileError
                            end
                    end;
                {error, _}=Error ->
                    Error
            end;
        {error, _}=Error ->
            Error
    end.

%%%
%%% Utility functions
%%%

set_by_name(Name, Value, Options) ->
    case proplists:get_value(Name, ?GO_FIELDS) of
        N when is_integer(N) andalso N > 1 ->
            setelement(N, Options, Value)
    end.

update_go_path(Env0, GoPath0) ->
    case code:priv_dir(erlport) of
        {error, bad_name} ->
            {error, {not_found, "erlport/priv"}};
        PrivDir ->
            GoDir = "go",
            ErlPortPath = erlport_options:joinpath(PrivDir, GoDir),
            {PathFromSetEnv, Env2} = extract_go_path(Env0, "", []),
            PathFromEnv = erlport_options:getenv("GOPATH"),
            GoPath = erlport_options:join_path([[ErlPortPath], GoPath0,
                erlport_options:split_path(PathFromSetEnv),
                erlport_options:split_path(PathFromEnv)]),
            Env3 = [{"GOPATH", GoPath} | Env2],
            {ok, GoPath, Env3}
    end.

get_go(default) ->
    case erlport_options:getenv(?GO_VAR_NAME) of
        "" ->
            try find_go(?DEFAULT_GO)
            catch
                throw:not_found ->
                    {error, go_not_found}
            end;
        Go ->
            try find_go(Go)
            catch
                throw:not_found ->
                    {error, {invalid_env_var, {?GO_VAR_NAME, Go},
                        not_found}}
            end
    end;
get_go(Go=[_|_]) ->
    try find_go(Go)
    catch
        throw:not_found ->
            {error, {invalid_option, {go, Go}, not_found}}
    end;
get_go(Go) ->
    {error, {invalid_option, {go, Go}}}.

find_go(Go) ->
    {GoCommand, Options} = lists:splitwith(fun (C) -> C =/= $ end, Go),
    case os:find_executable(GoCommand) of
        false ->
            throw(not_found);
        Filename ->
            Fullname = erlport_options:absname(Filename),
            case check_go_version(Fullname) of
                {ok, {MajVersion, _, _}} ->
                    {ok, Fullname ++ Options, MajVersion};
                {error, _}=Error ->
                    Error
            end
    end.

extract_go_path([{"GOPATH", P} | Tail], Path, Env) ->
    extract_go_path(Tail, [P, erlport_options:pathsep() | Path], Env);
extract_go_path([Item | Tail], Path, Env) ->
    extract_go_path(Tail, Path, [Item | Env]);
extract_go_path([], Path, Env) ->
    {lists:append(lists:reverse(Path)), lists:reverse(Env)}.

check_go_version(Go) ->
    Out = erlport_options:get_version(Go ++ " version"),
    case re:run(Out, "go version go([0-9]+)\\.([0-9]+)\\.?([0-9]*)",
            [{capture, all_but_first, list}]) of
        {match, [Maj, Min]} ->
            Version = {list_to_integer(Maj), list_to_integer(Min), 0},
            if
                Version >= {1, 11, 0} ->
                    {ok, Version};
                true ->
                    {error, {unsupported_go_version, Out}}
            end;
        {match, [Maj, Min, Patch]} ->
            Version = {list_to_integer(Maj), list_to_integer(Min),
                       list_to_integer(Patch)},
            if
                Version >= {1, 11, 0} ->
                    {ok, Version};
                true ->
                    {error, {unsupported_go_version, Out}}
            end;
        nomatch ->
            {error, {invalid_go, Go}}
    end.

compile_go_source(GoCmd, SrcPath, _GoPath, _Env) ->
    % Check if source file exists
    case filelib:is_regular(SrcPath) of
        false ->
            {error, {go_src_not_found, SrcPath}};
        true ->
            % Determine cache directory and binary path
            CacheDir = filename:join([filename:dirname(SrcPath), ".erlport_cache"]),
            SrcBase = filename:basename(SrcPath, ".go"),
            BinaryPath = filename:join([CacheDir, SrcBase]),

            % Check if compilation is needed
            NeedsCompile = case filelib:is_regular(BinaryPath) of
                false ->
                    true;  % Binary doesn't exist
                true ->
                    % Check if source is newer than binary
                    SrcTime = filelib:last_modified(SrcPath),
                    BinTime = filelib:last_modified(BinaryPath),
                    SrcTime > BinTime
            end,

            case NeedsCompile of
                false ->
                    {ok, BinaryPath};  % Use cached binary
                true ->
                    % Create cache directory if it doesn't exist
                    ok = filelib:ensure_dir(BinaryPath),

                    % Get absolute paths for source directory
                    AbsSrcPath = filename:absname(SrcPath),
                    SrcDir = filename:dirname(AbsSrcPath),

                    % Build using cd to source directory and using relative paths
                    % This ensures go.mod is found properly
                    BuildCmd = lists:concat([
                        "cd ", SrcDir, " && ",
                        GoCmd, " build -o ", filename:absname(BinaryPath), " ",
                        filename:basename(AbsSrcPath)
                    ]),

                    % Execute compilation
                    Output = os:cmd(BuildCmd ++ " 2>&1"),
                    case filelib:is_regular(BinaryPath) of
                        true ->
                            {ok, BinaryPath};  % Success - binary created
                        false ->
                            {error, {go_compile_failed, Output}}
                    end
            end
    end.
