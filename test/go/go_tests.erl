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

-module(go_tests).

-export([test_callback/1, recurse/2, recurse_helper/1]).

-include_lib("eunit/include/eunit.hrl").

-define(SETUP(Setup, Tests), {setup,
    Setup,
    fun cleanup/1,
    fun (P) ->
        Tests
    end}).
-define(SETUP(Tests), ?SETUP(fun setup/0, Tests)).

-define(TIMEOUT, 5000).


test_callback(Result) ->
    _ = log_event({test_callback, Result}),
    Result.

recurse(P, N) ->
    go:call(P, test_utils, recurse, [P, N]).

% Simple recursion helper that just passes N back to Go
recurse_helper(N) ->
    case N =< 0 of
        true -> done;
        false -> N - 1
    end.

%%%
%%% Event logging infrastructure (for callback tests)
%%%

log_event(Event) ->
    case ets:whereis(events) of
        undefined ->
            ok;  % Table doesn't exist, skip logging
        _ ->
            ets:insert(events, {events, Event})
    end.

get_events() ->
    Events = [E || {_, E} <- ets:lookup(events, events)],
    ets:delete(events, events),
    Events.

setup_event_logger() ->
    ets:new(events, [public, named_table, duplicate_bag]).

cleanup_event_logger() ->
    ets:delete(events).

%%%
%%% Basic start/stop tests
%%%

start_stop_test_() -> [
    fun () ->
        {ok, G} = go:start([{go_src, "test/go/test_utils.go"}]),
        ?assertEqual(ok, go:stop(G))
    end,
    fun () ->
        {ok, G} = go:start_link([{go_src, "test/go/test_utils.go"}]),
        ?assertEqual(ok, go:stop(G))
    end,
    fun () ->
        ?assertMatch({ok, _}, go:start({local, go_test},
            [{go_src, "test/go/test_utils.go"}])),
        ?assertEqual(ok, go:stop(go_test))
    end,
    fun () ->
        ?assertMatch({ok, _}, go:start_link({local, go_test},
            [{go_src, "test/go/test_utils.go"}])),
        ?assertEqual(ok, go:stop(go_test))
    end
    ].

%%%
%%% Call tests
%%%

call_test_() ->
    ?SETUP(
        ?_assertEqual(5, go:call(P, test_utils, add, [2, 3]))
    ).

identity_test_() ->
    ?SETUP([
        ?_assertEqual(42, go:call(P, test_utils, identity, [42])),
        ?_assertEqual(<<"test">>, go:call(P, test_utils, identity, [<<"test">>])),
        ?_assertEqual([1, 2, 3], go:call(P, test_utils, identity, [[1, 2, 3]]))
    ]).

length_test_() ->
    ?SETUP([
        ?_assertEqual(0, go:call(P, test_utils, length, [[]])),
        ?_assertEqual(3, go:call(P, test_utils, length, [[1, 2, 3]])),
        ?_assertEqual(5, go:call(P, test_utils, length, [[a, b, c, d, e]]))
    ]).

recursion_test_() ->
    ?SETUP(
        % Note: Simplified recursion test that doesn't pass Pid through callback chain
        % Tests Go→Erlang→Go callbacks by counting down
        ?_assertEqual(done, go:call(P, test_utils, recurse, [P, 5]))
    ).

%%%
%%% Datatype tests
%%%

datatype_test_() ->
    ?SETUP([
        % Atoms
        ?_assertEqual(test_atom, go:call(P, test_utils, identity, [test_atom])),
        ?_assertEqual(true, go:call(P, test_utils, identity, [true])),
        ?_assertEqual(false, go:call(P, test_utils, identity, [false])),

        % Numbers
        ?_assertEqual(0, go:call(P, test_utils, identity, [0])),
        ?_assertEqual(42, go:call(P, test_utils, identity, [42])),
        ?_assertEqual(-17, go:call(P, test_utils, identity, [-17])),

        % Binaries/Strings
        ?_assertEqual(<<>>, go:call(P, test_utils, identity, [<<>>])),
        ?_assertEqual(<<"hello">>, go:call(P, test_utils, identity, [<<"hello">>])),

        % Lists
        ?_assertEqual([], go:call(P, test_utils, identity, [[]])),
        ?_assertEqual([1, 2, 3], go:call(P, test_utils, identity, [[1, 2, 3]])),
        ?_assertEqual([a, b, c], go:call(P, test_utils, identity, [[a, b, c]])),

        % Tuples
        ?_assertEqual({}, go:call(P, test_utils, identity, [{}])),
        ?_assertEqual({1, 2}, go:call(P, test_utils, identity, [{1, 2}])),
        ?_assertEqual({a, b, c}, go:call(P, test_utils, identity, [{a, b, c}])),

        % Mixed nested structures
        ?_assertEqual([{1, a}, {2, b}],
            go:call(P, test_utils, identity, [[{1, a}, {2, b}]])),
        ?_assertEqual({[1, 2], [3, 4]},
            go:call(P, test_utils, identity, [{[1, 2], [3, 4]}]))
    ]).

%%%
%%% Error handling tests
%%%

error_test_() -> [
    fun () ->
        P = setup(),
        ?assertError({go, undef, _, _},
            go:call(P, test_utils, unknown_function, []))
    end,
    fun () ->
        P = setup(),
        ?assertError({go, call_error, _, _},
            go:call(P, test_utils, add, [1]))  % Wrong number of args
    end
    ].

%%%
%%% Stdio tests
%%%

stdin_stdout_test_() ->
    ?SETUP(fun () -> setup([use_stdio]) end,
        ?_assertEqual(5, go:call(P, test_utils, add, [2, 3]))
    ).

nouse_stdio_test_() ->
    ?SETUP(fun () -> setup([nouse_stdio]) end,
        ?_assertEqual(5, go:call(P, test_utils, add, [2, 3]))
    ).

%%%
%%% Compression test
%%%

compressed_test_() ->
    ?SETUP(fun () -> setup([{compressed, 6}]) end,
        ?_assertEqual(5, go:call(P, test_utils, add, [2, 3]))
    ).

%%%
%%% Cast/async messaging tests
%%%

erlang_cast_test_() -> {setup,
    fun () ->
        setup_event_logger(),
        setup()
    end,
    fun (P) ->
        cleanup(P),
        cleanup_event_logger()
    end,
    fun (P) ->
        fun () ->
            ?assertEqual(ok, go:call(P, test_utils, setup_message_handler, [])),
            ?assertEqual(ok, go:cast(P, test_message)),
            P ! test_message2,
            timer:sleep(500),
            ?assertEqual([{test_callback, {message, test_message}},
                {test_callback, {message, test_message2}}], get_events())
        end
    end}.

%%%
%%% Callback tests
%%%

call_back_test_() -> {setup,
    fun () ->
        setup_event_logger(),
        setup()
    end,
    fun (P) ->
        cleanup(P),
        cleanup_event_logger()
    end,
    fun (P) -> [
        fun () ->
            ?assertEqual(5, go:call(P, test_utils, switch, [5])),
            ?assertEqual([
                {test_callback, {0, 0}},
                {test_callback, {0, 1}},
                {test_callback, {1, 2}},
                {test_callback, {2, 3}},
                {test_callback, {3, 4}}
                ], get_events())
        end
    ] end}.

%%%
%%% Pipeline and queue tests
%%%

call_pipeline_test_() ->
    ?SETUP(
        {inparallel, [
            ?_assertEqual(N + 1, go:call(P, test_utils, add, [N , 1]))
            || N <- lists:seq(1, 50)]}
    ).

queue_test_() ->
    ?SETUP(
        {inparallel, [
            ?_assertEqual(262144, go:call(P, test_utils, length,
                [<<0:262144/unit:8>>]))
            || _ <- lists:seq(1, 50)]}
    ).

%%%
%%% Helper functions
%%%

setup() ->
    setup([]).

setup(Options) ->
    {ok, P} = go:start_link([{go_src, "test/go/test_utils.go"} | Options]),
    P.

cleanup(P) ->
    go:stop(P).
