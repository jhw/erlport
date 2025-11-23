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

-include_lib("kernel/include/file.hrl").

-export([
    parse/1
    ]).

-type option() :: {go, Go :: string()}
    | {go_binary, BinaryPath :: string()}
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
parse([{go_binary, GoBinary} | Tail], Options) ->
    % Will be validated later - expects pre-compiled binary (Lambda-style)
    parse(Tail, Options#go_options{go_binary=GoBinary});
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
        go_binary=GoBinary, port_options=PortOptions, packet=Packet,
        cd=Path, use_stdio=UseStdio}) ->
    PortOptions1 = erlport_options:update_port_options(
        PortOptions, Path, UseStdio),
    case update_go_path(Env0, GoPath0) of
        {ok, GoPath, Env} ->
            % Lambda-style: expect pre-compiled binary
            case GoBinary of
                undefined ->
                    {error, {missing_option, go_binary,
                        "Go binary path required (like AWS Lambda)"}};
                BinaryPath ->
                    % Validate binary exists and is executable
                    case validate_go_binary(BinaryPath) of
                        ok ->
                            {ok, Options#go_options{env=Env,
                                go_path=GoPath, go=BinaryPath,
                                port_options=[{env, Env}, {packet, Packet}
                                    | PortOptions1]}};
                        {error, _}=ValidationError ->
                            ValidationError
                    end
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

extract_go_path([{"GOPATH", P} | Tail], Path, Env) ->
    extract_go_path(Tail, [P, erlport_options:pathsep() | Path], Env);
extract_go_path([Item | Tail], Path, Env) ->
    extract_go_path(Tail, Path, [Item | Env]);
extract_go_path([], Path, Env) ->
    {lists:append(lists:reverse(Path)), lists:reverse(Env)}.

validate_go_binary(BinaryPath) ->
    % Check if binary exists
    case filelib:is_regular(BinaryPath) of
        false ->
            {error, {go_binary_not_found, BinaryPath}};
        true ->
            % Check if binary is executable (Unix-style check)
            AbsPath = filename:absname(BinaryPath),
            case file:read_file_info(AbsPath) of
                {ok, FileInfo} ->
                    % Check if owner execute bit is set
                    case FileInfo#file_info.mode band 8#00100 of
                        0 ->
                            {error, {go_binary_not_executable, AbsPath}};
                        _ ->
                            ok
                    end;
                {error, Reason} ->
                    {error, {go_binary_access_error, AbsPath, Reason}}
            end
    end.
