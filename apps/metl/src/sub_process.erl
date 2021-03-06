%%%-------------------------------------------------------------------
%%% @author linzexin
%%% @copyright (C) 2017, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 25. 十二月 2017 10:47
%%%-------------------------------------------------------------------
-module(sub_process).
-author("linzexin").

-behaviour(gen_server).

%% API
-export([start_link/1]).

%% gen_server callbacks
-export([init/1,
    handle_call/3,
    handle_cast/2,
    handle_info/2,
    terminate/2,
    code_change/3,
    select_data/1]
).

-define(SERVER, ?MODULE).

-record(state, {}).

%%%===================================================================
%%% API
%%%===================================================================

%%--------------------------------------------------------------------
%% @doc
%% Starts the server
%%
%% @end
%%--------------------------------------------------------------------
%%-spec(start_link() ->
%%    {ok, Pid :: pid()} | ignore | {error, Reason :: term()}).
start_link(Name) ->
    gen_server:start_link({local, list_to_atom(Name)}, ?MODULE, [Name], []).

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Initializes the server
%%
%% @spec init(Args) -> {ok, State} |
%%                     {ok, State, Timeout} |
%%                     ignore |
%%                     {stop, Reason}
%% @end
%%--------------------------------------------------------------------
-spec(init(Args :: term()) ->
    {ok, State :: #state{}} | {ok, State :: #state{}, timeout() | hibernate} |
    {stop, Reason :: term()} | ignore).
init(Name) ->
    [H|_] = Name,
    [AppId|[LogType|_]] = string:tokens(H,"/"),
    erlang:put(app_id,AppId),
    erlang:put(log_type,LogType),
    erlang:put(processname,erlang:list_to_atom(H)),
    erlang:send_after(1000,erlang:self(),loop),
    {ok, #state{}}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling call messages
%%
%% @end
%%--------------------------------------------------------------------
-spec(handle_call(Request :: term(), From :: {pid(), Tag :: term()},
    State :: #state{}) ->
    {reply, Reply :: term(), NewState :: #state{}} |
    {reply, Reply :: term(), NewState :: #state{}, timeout() | hibernate} |
    {noreply, NewState :: #state{}} |
    {noreply, NewState :: #state{}, timeout() | hibernate} |
    {stop, Reason :: term(), Reply :: term(), NewState :: #state{}} |
    {stop, Reason :: term(), NewState :: #state{}}).

content([],_,Sql)  ->
    Sql2 = string:sub_string(Sql,1,string:len(Sql)-1),
    emysql:execute(hello_pool,Sql2),
    ok;
content([H1|L1],B,Sql) ->
    Temp = maps:get(H1,B),
    Sql1 = lists:concat([Sql,binary_to_list(H1)," = ","'",binary_to_list(Temp),"'",","]),
    content(L1,B,Sql1).

write_mysql([]) ->
    io:format("~p~n",["write success"]),
    ok;
write_mysql([H|L]) ->
    [Logs|_] = maps:get(H,maps:from_list(ets:lookup(erlang:get(processname),H))),
    AppId = list_to_binary(erlang:get(app_id)),
    LogType = list_to_binary(erlang:get(log_type)),
    Fields = maps:get({AppId,LogType},maps:from_list(ets:lookup(app_log,{AppId,LogType}))),
    Database = maps:get(<<"database">>,Fields),
    Table = maps:get(<<"table">>,Fields),
    DbS = binary_to_list(Database),
    TbS = binary_to_list(Table),
    TableInfo = maps:get({Database,Table},maps:from_list(ets:lookup(table_info,{Database,Table}))),
    TableFields = maps:get(<<"fields">>,TableInfo),
    Sql = lists:concat(["INSERT INTO ",DbS,".",TbS," SET "]),
    case content(TableFields,Logs,Sql) of
        ok -> write_mysql(L);
        _ ->
            error_logger:format("One data write fail ~p~n",[]),
            write_mysql([H|L])
    end.

handle_call(_Request, _From, State) ->
    {reply, ok, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling cast messages
%%
%% @end
%%--------------------------------------------------------------------
-spec(handle_cast(Request :: term(), State :: #state{}) ->
    {noreply, NewState :: #state{}} |
    {noreply, NewState :: #state{}, timeout() | hibernate} |
    {stop, Reason :: term(), NewState :: #state{}}).
handle_cast(_Request, State) ->
    {noreply, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling all non call/cast messages
%%
%% @spec handle_info(Info, State) -> {noreply, State} |
%%                                   {noreply, State, Timeout} |
%%                                   {stop, Reason, State}
%% @end
%%--------------------------------------------------------------------
-spec(handle_info(Info :: timeout() | term(), State :: #state{}) ->
    {noreply, NewState :: #state{}} |
    {noreply, NewState :: #state{}, timeout() | hibernate} |
    {stop, Reason :: term(), NewState :: #state{}}).

delete_datas([]) -> ok;
delete_datas([H|L]) ->
    ets:delete(erlang:get(processname),H),
    mnesia:dirty_delete(req,H),
    delete_datas(L).

select_data(Keys) ->
    case write_mysql(Keys) of
          ok ->delete_datas(Keys);
          _  ->
              error_logger:format("Fail to write ！！！~p~n",[]),
              write_mysql(Keys)
    end.


do_loop() ->
    Keys = ets:select(erlang:get(processname),[{{'$1','_'},[],['$1']}]),
    if
        erlang:length(Keys) =:= 0 -> ok;
        true -> select_data(Keys)
    end,
    erlang:send_after(5000,erlang:self(),loop).


handle_info(loop, State) ->
     do_loop(),
    {noreply, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% This function is called by a gen_server when it is about to
%% terminate. It should be the opposite of Module:init/1 and do any
%% necessary cleaning up. When it returns, the gen_server terminates
%% with Reason. The return value is ignored.
%%
%% @spec terminate(Reason, State) -> void()
%% @end
%%--------------------------------------------------------------------
-spec(terminate(Reason :: (normal | shutdown | {shutdown, term()} | term()),
    State :: #state{}) -> term()).
terminate(_Reason, _State) ->
    ok.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Convert process state when code is changed
%%
%% @spec code_change(OldVsn, State, Extra) -> {ok, NewState}
%% @end
%%--------------------------------------------------------------------
-spec(code_change(OldVsn :: term() | {down, term()}, State :: #state{},
    Extra :: term()) ->
    {ok, NewState :: #state{}} | {error, Reason :: term()}).
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================
