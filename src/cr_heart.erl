-module(cr_heart).
-copyright('Maxim Sokhatsky').
-include("cr.hrl").
-compile(export_all).
-record(state, {name,nodes,timers}).
-export(?GEN_SERVER).

start_link(UniqueName,HashRing) ->
    gen_server:start_link(?MODULE, [UniqueName,HashRing], []).

init([UniqueName,Nodes]) ->

    Timers = [ begin
          [_,Addr]=string:tokens(atom_to_list(erlang:node()),"@"),
          {ok,Parsed}=inet:parse_address(Addr),
          Timer = erlang:send_after(1000,self(),{timer,ping,{Parsed,P2},Node,undefined}),
          {Node,Timer}
      end || {Node,_,P2,_}<-Nodes],

    error_logger:info_msg("HEART PROTOCOL: started: ~p~n"
                                   "Nodes: ~p~n",[UniqueName,Timers]),

    {ok,#state{name=UniqueName,nodes=Nodes,timers=Timers}}.

timer_restart(Diff,Connect,Node,Socket) ->
    {X,Y,Z} = Diff,
    erlang:send_after(1000*(Z+60*Y+60*60*X),self(),{timer,ping,Connect,Node,Socket}).

setkey(Name,Pos,List,New) ->
    case lists:keyfind(Name,Pos,List) of
        false -> [New|List];
        _Element -> lists:keyreplace(Name,Pos,List,New) end.

handle_info({'EXIT', Pid,_}, #state{} = State) ->
    error_logger:info_msg("HEART: EXIT~n",[]),
    {noreply, State};

handle_info({carrier,lost,N}, State=#state{timers=Timer}) ->
    error_logger:info_msg("HOST CARRIER LOST ~p~n",[N]),
    {noreply,State};

handle_info({timer,ping,{A,P},N,S}, State=#state{timers=Timers}) ->

    error_logger:info_msg("PING STATE: ~p~n"
                              "Timers: ~p~n",[{A,P,N,S},Timers]),

    {N,Timer} = lists:keyfind(N,1,Timers),
    case Timer of undefined -> skip; _ -> erlang:cancel_timer(Timer) end,

    Socket = case S of
              S -> try gen_tcp:send(S,term_to_binary({ping})), S catch _:_ -> undefined end;
      undefined ->
             try {ok,S1} = gen_tcp:connect(A,P,[{packet,0}]),
                           gen_tcp:send(S1,term_to_binary({ping})),
                           S1 catch _:_ -> undefined end end,

    T = case try gen_tcp:recv(Socket,0) catch _:_ -> {error,recv} end of
         {error,_} -> timer_restart({0,0,5},{A,P},N,undefined);
         {ok,_}    -> timer_restart({0,0,5},{A,P},N,Socket) end,

    {noreply,State#state{timers=setkey(N,1,Timers,{N,T})}};

handle_info(_Info, State) ->
    error_logger:info_msg("HEART: Info ~p~n",[_Info]),
    {noreply, State}.

handle_call(Request,_,Proc) ->
    error_logger:info_msg("HEART: Call ~p~n",[Request]),
    {reply,ok,Proc}.

handle_cast(Msg, State) ->
    error_logger:info_msg("HEART: Cast ~p", [Msg]),
    {stop, {error, {unknown_cast, Msg}}, State}.

terminate(_Reason, #state{}) -> ok.
code_change(_OldVsn, State, _Extra) -> {ok, State}.

