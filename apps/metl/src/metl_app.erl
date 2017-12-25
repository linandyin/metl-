%%%-------------------------------------------------------------------
%% @doc metl public API
%% @end
%%%-------------------------------------------------------------------

-module(metl_app).

-behaviour(application).

%% Application callbacks
-export([start/2, stop/1]).

%%====================================================================
%% API
%%====================================================================

start(_StartType, _StartArgs) ->
    Dispatch = cowboy_router:compile([
        {'_', [{"/", metl_web, []}]}
    ]),
    cowboy:start_http(my_http_listener, 100, [{port, 1234}],
        [{env, [{dispatch, Dispatch}]}]
    ),
    metl_mnesia:do_this_once(),
    metl_sup:start_link().

%%--------------------------------------------------------------------
stop(_State) ->
    ok.

%%====================================================================
%% Internal functions
%%====================================================================
