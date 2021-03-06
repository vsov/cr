-module(cr_config).
-compile(export_all).
-include("rafter.hrl").

quorum_max(_Me, #config{state=blank}, _) -> 0;
quorum_max(Me, #config{state=stable, newservers=OldServers}, Responses) -> quorum_max(Me, OldServers, Responses);
quorum_max(Me, #config{state=staging, newservers=OldServers}, Responses) -> quorum_max(Me, OldServers, Responses);
quorum_max(Me, #config{state=transitional, oldservers=Old, newservers=New}, Responses) -> min(quorum_max(Me, Old, Responses), quorum_max(Me, New, Responses));

quorum_max(_, [], _) -> 0;
quorum_max(Me, Servers, Responses) when (length(Servers) rem 2) =:= 0->
    Values = sorted_values(Me, Servers, Responses),
    lists:nth(length(Values) div 2, Values);
quorum_max(Me, Servers, Responses) ->
    Values = sorted_values(Me, Servers, Responses),
    lists:nth(length(Values) div 2 + 1, Values).

quorum(_Me, #config{state=blank}, _Responses) -> false;
quorum(Me, #config{state=stable,newservers=Servers}, Responses) -> quorum(Me, Servers, Responses);
quorum(Me, #config{state=staging,newservers=Servers}, Responses) -> quorum(Me, Servers, Responses);
quorum(Me, #config{state=transitional,oldservers=Old, newservers=New}, Responses) -> quorum(Me, Old, Responses) andalso quorum(Me, New, Responses);
quorum(Me, Servers, Responses) ->
    TrueResponses = [R || {Peer, R} <- dict:to_list(Responses),
                          R =:= true,
                          lists:member(Peer, Servers)],
    case lists:member(Me, Servers) of
        true -> length(TrueResponses) + 1 > length(Servers)/2;
        false -> length(TrueResponses) > length(Servers)/2 end.

voters(Me, Config) -> lists:delete(Me, voters(Config)).
voters(#config{oldservers=Old, newservers=New}) -> sets:to_list(sets:from_list(Old ++ New));
voters(#config{newservers=Old}) -> Old.

has_vote(_Me, #config{state=blank}) -> false;
has_vote(Me, #config{oldservers=Old, newservers=New})-> lists:member(Me, Old) orelse lists:member(Me, New);
has_vote(Me, #config{newservers=Old}) -> lists:member(Me, Old).

followers(Me, #config{oldservers=Old, newservers=New}) -> lists:delete(Me, sets:to_list(sets:from_list(Old ++ New)));
followers(Me, #config{newservers=Old}) -> lists:delete(Me, Old).

reconfig(#config{state=Blank,newservers=OldNew}=Config, Servers) ->
    Config#config{state=stable,oldservers=OldNew, newservers=Servers}.

allow_config(#config{state=blank}, _NewServers) -> true;
allow_config(#config{newservers=OldServers}, NewServers) when NewServers =/= OldServers -> true;
allow_config(_Config, _NewServers) -> {error, config_not_allowed}.

sorted_values(Me, Servers, Responses) ->
    Vals = lists:sort(lists:map(fun(S) -> value(S, Responses) end, Servers)),
    case lists:member(Me, Servers) of
        true -> [_ | T] = Vals, lists:reverse([lists:max(Vals) | lists:reverse(T)]);
        false -> Vals end.

value(Peer, Responses) ->
    case dict:find(Peer, Responses) of
        {ok, Value} -> Value;
        error -> 0 end.
