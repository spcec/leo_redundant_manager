%%======================================================================
%%
%% Leo Redundant Manager
%%
%% Copyright (c) 2012 Rakuten, Inc.
%%
%% This file is provided to you under the Apache License,
%% Version 2.0 (the "License"); you may not use this file
%% except in compliance with the License.  You may obtain
%% a copy of the License at
%%
%%   http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing,
%% software distributed under the License is distributed on an
%% "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
%% KIND, either express or implied.  See the License for the
%% specific language governing permissions and limitations
%% under the License.
%%
%% ---------------------------------------------------------------------
%% Leo Redundant Manager - API
%% @doc
%% @end
%%======================================================================
-module(leo_redundant_manager_api).

-author('Yosuke Hara').

-include("leo_redundant_manager.hrl").
-include_lib("eunit/include/eunit.hrl").

-export([create/0, create/1, create/2,
         set_options/1, get_options/0,
         attach/1, attach/2, attach/3, attach/4,
         reserve/3, reserve/5, detach/1, detach/2,
         suspend/1, suspend/2, append/3,
         checksum/1, synchronize/2, synchronize/3, adjust/1,
         get_ring/0, dump/1
        ]).

-export([get_redundancies_by_key/1, get_redundancies_by_key/2,
         get_redundancies_by_addr_id/1, get_redundancies_by_addr_id/2,
         range_of_vnodes/1, rebalance/0
        ]).

-export([has_member/1, has_charge_of_node/1,
         get_members/0, get_members/1, get_member_by_node/1, get_members_count/0,
         get_members_by_status/1,
         update_member/1, update_members/1, update_member_by_node/3,
         delete_member_by_node/1, get_ring/1, is_alive/0, table_info/1
        ]).

-type(method() :: put | get | delete | head).

%%--------------------------------------------------------------------
%% API-1  FUNCTIONS
%%--------------------------------------------------------------------
%% @doc Create the RING
%%
-spec(create() ->
             {ok, list(), list()} | {error, any()}).
create() ->
    case leo_redundant_manager:create() of
        {ok, Members} ->
            {ok, Chksums} = checksum(?CHECKSUM_RING),
            {CurRingHash, _PrevRingHash} = Chksums,
            ok = leo_misc:set_env(?APP, ?PROP_RING_HASH, CurRingHash),

            {ok, Chksum0} = checksum(?CHECKSUM_MEMBER),
            {ok, Members, [{?CHECKSUM_RING,   Chksums},
                           {?CHECKSUM_MEMBER, Chksum0}]};
        Error ->
            Error
    end.

-spec(create(list()) ->
             {ok, list(), list()} | {error, any()}).
create([]) ->
    create();
create([#member{node = Node, clock = Clock}|T]) ->
    ok = attach(Node, Clock),
    create(T).

-spec(create(list(), list()) ->
             {ok, list(), list()} | {error, any()}).
create([], Options) ->
    ok = set_options(Options),
    create();
create([#member{node = Node, clock = Clock}|T], Options) ->
    ok = attach(Node, Clock),
    create(T, Options).


%% @doc set routing-table's options.
%%
-spec(set_options(list()) ->
             ok).
set_options(Options) ->
    ok = leo_misc:set_env(?APP, ?PROP_OPTIONS, Options),
    ok.


%% @doc get routing-table's options.
%%
-spec(get_options() ->
             {ok, list()}).
get_options() ->
    leo_misc:get_env(?APP, ?PROP_OPTIONS).


%% @doc attach a node.
%%
-spec(attach(atom()) ->
             ok | {error, any()}).
attach(Node) ->
    attach(Node, [], leo_date:clock()).
-spec(attach(atom(), string()) ->
             ok | {error, any()}).
attach(Node, NumOfAwarenessL2) ->
    attach(Node, NumOfAwarenessL2, leo_date:clock()).
-spec(attach(atom(), string(), pos_integer()) ->
             ok | {error, any()}).
attach(Node, NumOfAwarenessL2, Clock) ->
    attach(Node, NumOfAwarenessL2, Clock, ?DEF_NUMBER_OF_VNODES).
-spec(attach(atom(), string(), pos_integer(), pos_integer()) ->
             ok | {error, any()}).
attach(Node, NumOfAwarenessL2, Clock, NumOfVNodes) ->
    case leo_redundant_manager:attach(
           Node, NumOfAwarenessL2, Clock, NumOfVNodes) of
        ok ->
            ok;
        Error ->
            Error
    end.


%% @doc reserve a node during in operation
%%
-spec(reserve(atom(), atom(), pos_integer()) ->
             ok | {error, any()}).
reserve(Node, CurState, Clock) ->
    reserve(Node, CurState, [], Clock, 0).

-spec(reserve(atom(), atom(), string(), pos_integer(), pos_integer()) ->
             ok | {error, any()}).
reserve(Node, CurState, NumOfAwarenessL2, Clock, NumOfVNodes) ->
    case leo_redundant_manager:reserve(
           Node, CurState, NumOfAwarenessL2, Clock, NumOfVNodes) of
        ok ->
            ok;
        Error ->
            Error
    end.


%% @doc detach a node.
%%
-spec(detach(atom()) ->
             ok | {error, any()}).
detach(Node) ->
    detach(Node, leo_date:clock()).
detach(Node, Clock) ->
    case leo_redundant_manager:detach(Node, Clock) of
        ok ->
            ok;
        Error ->
            Error
    end.


%% @doc suspend a node. (disable)
%%
-spec(suspend(atom()) ->
             ok | {error, any()}).
suspend(Node) ->
    suspend(Node, leo_date:clock()).
suspend(Node, Clock) ->
    case leo_redundant_manager:suspend(Node, Clock) of
        ok ->
            ok;
        Error ->
            Error
    end.


%% @doc append a node into the ring.
%%
-spec(append(?VER_CURRENT | ?VER_PREV, integer(), atom()) ->
             ok).
append(?VER_CURRENT, VNodeId, Node) ->
    TblInfo = table_info(?VER_CURRENT),
    ok = leo_redundant_manager_chash:append(TblInfo, VNodeId, Node),
    ok;
append(?VER_PREV,    VNodeId, Node) ->
    TblInfo = table_info(?VER_PREV),
    ok = leo_redundant_manager_chash:append(TblInfo, VNodeId, Node),
    ok.


%% @doc get routing_table's checksum.
%%
-spec(checksum(?CHECKSUM_RING |?CHECKSUM_MEMBER) ->
             {ok, binary()} | {ok, atom()}).
checksum(?CHECKSUM_MEMBER = Type) ->
    leo_redundant_manager:checksum(Type);
checksum(?CHECKSUM_RING) ->
    TblInfo0 = table_info(?VER_CURRENT),
    TblInfo1 = table_info(?VER_PREV),

    {ok, Chksum0} = leo_redundant_manager_chash:checksum(TblInfo0),
    {ok, Chksum1} = leo_redundant_manager_chash:checksum(TblInfo1),
    {ok, {Chksum0, Chksum1}};
checksum(_) ->
    {error, badarg}.


%% @doc synchronize member-list and routing-table.
%%
-spec(synchronize(sync_mode() | list(), list(), list()) ->
             {ok, list(), list()} | {error, any()}).
synchronize(?SYNC_MODE_BOTH, Members, Options) ->
    case leo_redundant_manager:update_members(Members) of
        ok ->
            create(Members, Options);
        Error ->
            Error
    end;

synchronize([],_Ring0,_Acc) ->
    checksum(?CHECKSUM_RING);

synchronize([RingVer|T], Ring0, Acc) ->
    Ret = synchronize(RingVer, Ring0),
    synchronize(T, Ring0, [Ret|Acc]).


-spec(synchronize(sync_mode(), list()) ->
             {ok, integer()} | {error, any()}).
synchronize(?SYNC_MODE_MEMBERS, Members) ->
    case leo_redundant_manager:update_members(Members) of
        ok ->
            leo_redundant_manager:checksum(?CHECKSUM_MEMBER);
        Error ->
            Error
    end;

synchronize(?SYNC_MODE_CUR_RING = Ver, Ring0) ->
    {ok, Ring1} = get_ring(Ver),
    TblInfo = table_info(?VER_CURRENT),

    case leo_redundant_manager:synchronize(TblInfo, Ring0, Ring1) of
        ok ->
            {ok, {CurRingHash, _PrevRingHash}} = checksum(?CHECKSUM_RING),
            ok = leo_misc:set_env(?APP, ?PROP_RING_HASH, CurRingHash),
            checksum(?CHECKSUM_RING);
        Error ->
            Error
    end;

synchronize(?SYNC_MODE_PREV_RING = Ver, Ring0) ->
    {ok, Ring1} = get_ring(Ver),
    TblInfo = table_info(?VER_PREV),

    case leo_redundant_manager:synchronize(TblInfo, Ring0, Ring1) of
        ok ->
            checksum(?CHECKSUM_RING);
        Error ->
            Error
    end;

synchronize(Ver, Ring0) when is_list(Ver) ->
    synchronize(Ver, Ring0, []);

synchronize(_, _) ->
    {error, badarg}.


%% @doc Adjust current vnode to previous vnode.
%%
-spec(adjust(integer()) ->
             ok | {error, any()}).
adjust(VNodeId) ->
    TblInfo0 = table_info(?VER_CURRENT),
    TblInfo1 = table_info(?VER_PREV),

    case leo_redundant_manager:adjust(TblInfo0, TblInfo1, VNodeId) of
        ok ->
            ok;
        Error ->
            Error
    end.


%% @doc Retrieve Current Ring
%%
-spec(get_ring() ->
             {ok, list()} | {error, any()}).
get_ring() ->
    {ok, ets:tab2list(?CUR_RING_TABLE)}.


%% @doc Dump table-records.
%%
-spec(dump(member | ring) ->
             ok).
dump(Type) ->
    leo_redundant_manager:dump(Type).


%%--------------------------------------------------------------------
%% API-2  FUNCTIONS (leo_routing_table_provide_server)
%%--------------------------------------------------------------------
%% @doc Retrieve redundancies from the ring-table.
%%
-spec(get_redundancies_by_key(string()) ->
             {ok, list(), integer(), integer(), list()} | {error, any()}).
get_redundancies_by_key(Key) ->
    get_redundancies_by_key(default, Key).

-spec(get_redundancies_by_key(method(), string()) ->
             {ok, list(), integer(), integer(), list()} | {error, any()}).
get_redundancies_by_key(Method, Key) ->
    case leo_misc:get_env(?APP, ?PROP_OPTIONS) of
        {ok, Options} ->
            BitOfRing = leo_misc:get_value(?PROP_RING_BIT, Options),
            AddrId = leo_redundant_manager_chash:vnode_id(BitOfRing, Key),

            get_redundancies_by_addr_id(ring_table(Method), AddrId, Options);
        _ ->
            {error, not_found}
    end.


%% @doc Retrieve redundancies from the ring-table.
%%
get_redundancies_by_addr_id(AddrId) ->
    get_redundancies_by_addr_id(default, AddrId).

-spec(get_redundancies_by_addr_id(method(), integer()) ->
             {ok, list(), integer(), integer(), list()} | {error, any()}).
get_redundancies_by_addr_id(Method, AddrId) ->
    case leo_misc:get_env(?APP, ?PROP_OPTIONS) of
        {ok, Options} ->
            get_redundancies_by_addr_id(ring_table(Method), AddrId, Options);
        _ ->
            {error, not_found}
    end.

get_redundancies_by_addr_id(TblInfo, AddrId, Options) ->
    {ok, ServerType} = leo_misc:get_env(?APP, ?PROP_SERVER_TYPE),
    get_redundancies_by_addr_id(ServerType, TblInfo, AddrId, Options).

get_redundancies_by_addr_id(?SERVER_MANAGER, TblInfo, AddrId, Options) ->
    Ret = leo_redundant_manager_table_member:find_all(),
    get_redundancies_by_addr_id_1(Ret, TblInfo, AddrId, Options);

get_redundancies_by_addr_id(_ServerType, TblInfo, AddrId, Options) ->
    Ret = leo_redundant_manager_table_member:find_all(),
    get_redundancies_by_addr_id_1(Ret, TblInfo, AddrId, Options).

get_redundancies_by_addr_id_1({ok, Members}, TblInfo, AddrId, Options) ->
    %% checkout worker's ref from the pool
    case catch poolboy:checkout(?RING_WORKER_POOL_NAME) of
        {'EXIT', Cause} ->
            {error, Cause};
        ServerRef ->
            Ret = get_redundancies_by_addr_id_1_1(ServerRef, TblInfo, Members, AddrId, Options),
            _ = poolboy:checkin(?RING_WORKER_POOL_NAME, ServerRef),
            Ret
        end;
get_redundancies_by_addr_id_1(Error, _TblInfo, _AddrId, _Options) ->
    error_logger:warning_msg("~p,~p,~p,~p~n",
                             [{module, ?MODULE_STRING}, {function, "get_redundancies_by_addr_id_1/4"},
                              {line, ?LINE}, {body, Error}]),
    {error, not_found}.

%% @private
get_redundancies_by_addr_id_1_1(ServerRef, TblInfo, Members, AddrId, Options) ->
    N = leo_misc:get_value(?PROP_N, Options),
    R = leo_misc:get_value(?PROP_R, Options),
    W = leo_misc:get_value(?PROP_W, Options),
    D = leo_misc:get_value(?PROP_D, Options),

    %% for rack-awareness replica placement
    L2 = leo_misc:get_value(?PROP_L2, Options, 0),

    case leo_redundant_manager_chash:redundancies(
           {ServerRef, TblInfo}, AddrId, N, L2, Members) of
        {ok, Redundancies} ->
            CurRingHash =
                case leo_misc:get_env(?APP, ?PROP_RING_HASH) of
                    {ok, RingHash} ->
                        RingHash;
                    undefined ->
                        {ok, {RingHash, _}} = checksum(?CHECKSUM_RING),
                        ok = leo_misc:set_env(?APP, ?PROP_RING_HASH, RingHash),
                        RingHash
                end,
            {ok, Redundancies#redundancies{n = N,
                                           r = R,
                                           w = W,
                                           d = D,
                                           ring_hash = CurRingHash}};
        Error ->
            Error
    end.


%% @doc Retrieve range of vnodes.
%%
-spec(range_of_vnodes(atom()) ->
             {ok, list()} | {error, any()}).
range_of_vnodes(ToVNodeId) ->
    TblInfo = table_info(?VER_CURRENT),
    leo_redundant_manager_chash:range_of_vnodes(TblInfo, ToVNodeId).


%% @doc Re-balance objects in the cluster.
%%
-spec(rebalance() ->
             {ok, list()} | {error, any()}).
rebalance() ->
    case leo_misc:get_env(?APP, ?PROP_OPTIONS) of
        {ok, Options} ->
            N  = leo_misc:get_value(?PROP_N,  Options),
            L2 = leo_misc:get_value(?PROP_L2, Options),

            ServerType = leo_misc:get_env(?APP, ?PROP_SERVER_TYPE),
            rebalance(ServerType, N, L2);
        Error ->
            Error
    end.

rebalance(?SERVER_MANAGER, N, L2) ->
    Ret = leo_redundant_manager_table_member:find_all(),
    rebalance_1(Ret, N, L2);
rebalance(_, N, L2) ->
    Ret = leo_redundant_manager_table_member:find_all(),
    rebalance_1(Ret, N, L2).

rebalance_1({ok, Members}, N, L2) ->
    TblInfo0 = table_info(?VER_CURRENT),
    TblInfo1 = table_info(?VER_PREV),

    leo_redundant_manager_chash:rebalance({TblInfo0, TblInfo1}, N, L2, Members);
rebalance_1(Error,_N,_L2) ->
    Error.


%%--------------------------------------------------------------------
%% API-3  FUNCTIONS (leo_member_management_server)
%%--------------------------------------------------------------------
%% @doc Has a member ?
%%
-spec(has_member(atom()) ->
             boolean()).
has_member(Node) ->
    leo_redundant_manager:has_member(Node).


%% @doc Has charge of node?
%%
-spec(has_charge_of_node(string()) ->
             boolean()).
has_charge_of_node(Key) ->
    case get_redundancies_by_key(put, Key) of
        {ok, #redundancies{nodes = Nodes}} ->
            lists:foldl(fun({N, _}, false) -> N == erlang:node();
                           ({_, _}, true ) -> true
                        end, false, Nodes);
        _ ->
            false
    end.


%% @doc get members.
%%
get_members() ->
    get_members(?VER_CURRENT).

-spec(get_members(?VER_CURRENT | ?VER_PREV) ->
             {ok, list()} | {error, any()}).
get_members(?VER_CURRENT = Ver) ->
    leo_redundant_manager:get_members(Ver);

get_members(?VER_PREV = Ver) ->
    leo_redundant_manager:get_members(Ver).


%% @doc get a member by node-name.
%%
-spec(get_member_by_node(atom()) ->
             {ok, #member{}} | {error, any()}).
get_member_by_node(Node) ->
    leo_redundant_manager:get_member_by_node(Node).


%% @doc get # of members.
%%
-spec(get_members_count() ->
             integer() | {error, any()}).
get_members_count() ->
    leo_redundant_manager_table_member:size().


%% @doc get members by status
%%
-spec(get_members_by_status(atom()) ->
             {ok, list(#member{})} | {error, any()}).
get_members_by_status(Status) ->
    leo_redundant_manager:get_members_by_status(Status).


%% @doc update members.
%%
-spec(update_member(#member{}) ->
             ok | {error, any()}).
update_member(Member) ->
    case leo_redundant_manager:update_member(Member) of
        ok ->
            ok;
        Error ->
            Error
    end.


%% @doc update members.
%%
-spec(update_members(list()) ->
             ok | {error, any()}).
update_members(Members) ->
    case leo_redundant_manager:update_members(Members) of
        ok ->
            ok;
        Error ->
            Error
    end.


%% @doc update a member by node-name.
%%
-spec(update_member_by_node(atom(), integer(), atom()) ->
             ok | {error, any()}).
update_member_by_node(Node, Clock, State) ->
    leo_redundant_manager:update_member_by_node(Node, Clock, State).


%% @doc remove a member by node-name.
%%
-spec(delete_member_by_node(atom()) ->
             ok | {error, any()}).
delete_member_by_node(Node) ->
    leo_redundant_manager:delete_member_by_node(Node).


%% @doc Retrieve ring by version.
%%
-spec(get_ring(?SYNC_MODE_CUR_RING | ?SYNC_MODE_PREV_RING) ->
             {ok, list()}).
get_ring(?SYNC_MODE_CUR_RING) ->
    TblInfo = table_info(?VER_CURRENT),
    Ring = leo_redundant_manager_table_ring:tab2list(TblInfo),
    {ok, Ring};
get_ring(?SYNC_MODE_PREV_RING) ->
    TblInfo = table_info(?VER_PREV),
    Ring = leo_redundant_manager_table_ring:tab2list(TblInfo),
    {ok, Ring}.


%% @doc stop membership.
%%
is_alive() ->
    leo_membership:heartbeat().


%% @doc Retrieve table-info by version.
%%
-spec(table_info(?VER_CURRENT | ?VER_PREV) ->
             ring_table_info()).


-ifdef(TEST).
table_info(?VER_CURRENT) -> {ets, ?CUR_RING_TABLE };
table_info(?VER_PREV   ) -> {ets, ?PREV_RING_TABLE}.
-else.
table_info(?VER_CURRENT) ->
    case leo_misc:get_env(?APP, ?PROP_SERVER_TYPE) of
        {ok, ?SERVER_MANAGER} ->
            {mnesia, ?CUR_RING_TABLE};
        _ ->
            {ets, ?CUR_RING_TABLE}
    end;

table_info(?VER_PREV) ->
    case leo_misc:get_env(?APP, ?PROP_SERVER_TYPE) of
        {ok, ?SERVER_MANAGER} ->
            {mnesia, ?PREV_RING_TABLE};
        _ ->
            {ets, ?PREV_RING_TABLE}
    end.
-endif.


%%--------------------------------------------------------------------
%% INNTERNAL FUNCTIONS
%%--------------------------------------------------------------------
%% @doc Specify ETS's table.
%% @private
-spec(ring_table(method()) ->
             ring_table_info()).
ring_table(default) -> table_info(?VER_CURRENT);
ring_table(put)     -> table_info(?VER_CURRENT);
ring_table(get)     -> table_info(?VER_PREV);
ring_table(delete)  -> table_info(?VER_CURRENT);
ring_table(head)    -> table_info(?VER_PREV).

