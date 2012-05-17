%% @doc http://en.wikipedia.org/wiki/Circular_buffer

-module(rbuf).

-compile([export_all]).

-export([
	new/1, new/2, new/3,
	set/2, set/3,
	get/1, get/2
	]).

%% SERIAL element access ring buffer structure
-record(srb, {
	size :: integer(),
	startp = 0 :: integer(), %% start reading from array pointer
	endp = 0 :: integer(), %% end read at array pointer
	empty = true :: boolean(),
	array :: term()
	}).

%% RANDOM element access ring buffer structure
-record(rrb, {
	size :: integer(),
	startp = 0 :: integer(), %% start reading from array pointer
	default = undefined,
	array :: term()
	}).

-type ring_buffer() :: #srb{} | #rrb{}.

%% @doc Create new serial access ring buffer
%% with size = Size
new(Size) when is_integer(Size) ->
	new(Size, serial, undefined).

new(Size, Default) ->
	new(Size, serial, Default).

-spec new(Size :: integer(), Type :: atom(), Default :: term()) -> ring_buffer().
new(Size, serial, Default) ->
	Array = array:new([{default, Default}, {size, Size}]),
	#srb{array = Array, size = Size};
new(Size, random, Default) ->
	Array = array:new([{default, Default}, {size, Size}]),
	#rrb{array = Array, size = Size, default = Default}.


%% @doc Set next element.
-spec set(Item :: term(), RB1 :: ring_buffer()) ->
	{ok, RB2 :: ring_buffer()}.

set(Item, RB = #srb{	array = A,
					empty = true,
					endp = P,
					startp = P}) ->
	I = P,
	NewA = array:set(I, Item, A),
	{ok, RB#srb{array = NewA, empty = false}};

set(Item, RB = #srb{	array = A,
						empty = false,
						endp = EndP,
						startp = SP,
						size = Size}) ->
	NextEndP = get_next(Size, EndP),
	I = NextEndP,
	NewA = array:set(I, Item, A),
	case NextEndP == SP of
		true ->
			{ok, RB#srb{array = NewA, endp = NextEndP, startp = get_next(Size, SP)}};
		false ->
			{ok, RB#srb{array = NewA, endp = NextEndP}}
	end.

%% @doc Get get next element, delete it & retuns new buffer.
-spec get(RB1 :: ring_buffer()) -> 
	{{value, Item :: term()}, RB2 :: ring_buffer()} |
	{empty, RB2 :: ring_buffer()}.

%% get/1 function for serial access buffer

get(RB = #srb{empty = true}) ->
	{empty, RB};
get(RB = #srb{array = A, startp = P, endp = P}) ->
	I = P,
	Item = array:get(I, A),
	{{value, Item}, RB#srb{empty = true}};
get(RB = #srb{array = A, startp = SP, size = S}) ->
	I = SP,
	Item = array:get(I, A),
	{{value, Item}, RB#srb{startp = get_next(S, SP)}};

%% get/1 function for random access buffer

get(RB = #rrb{array = A, startp = SP, default = DValue, size = S}) ->
	I = SP,
	Item = array:get(I, A),
	NewA = array:set(I, DValue, A),
	{{value, Item}, RB#rrb{array = NewA, startp = get_next(S, SP)}}.

%% Extended API

%% @doc Set specified element. Only for random access buffer type.
-spec set(Item :: term(), Position :: integer(), RB1 :: ring_buffer()) ->
	{ok, RB2 :: ring_buffer()} |
	{error, out_of_range}.
set(_Item, Pos, _RB = #rrb{size = S}) when Pos > S orelse Pos =< 0 ->
	{error, out_of_range};
set(Item, Pos, RB = #rrb{array = A, startp = SP, size = S}) ->
	I = get_position(S, SP, Pos),
	NewA = array:set(I, Item, A),
	{ok, RB#rrb{array = NewA}}.

%% @doc Get specified element. Element leavs in buffer.
%% Only for random access buffer type.
-spec get(Position :: integer(), RB1 :: ring_buffer()) -> 
	{{value, Item :: term()}, RB1 :: ring_buffer()} |
	{empty, RB2 :: ring_buffer()} |
	{error, out_of_range}.
get(Pos, #rrb{size = Size}) when Pos =< 0 orelse Pos > Size ->
	{error, out_of_range};
get(Pos, RB = #rrb{array = A, startp = SP, size = S}) ->
	I = get_position(S, SP, Pos),
	Item = array:get(I, A),
	{{value, Item}, RB}.

%% Local functions definitions

get_next(Size, Index) ->
	get_position(Size, Index, 2).

get_position(Size, StartPoint, Position) ->
	Sn = Size - 1,
	Pn = Position -1,
	Point = StartPoint + Pn,
	if
		Point =< Sn ->
			Point;
		true ->
			Point - Sn -1
	end.

%% TEST FUNCTIONS DEFINITIONS

test_get_next() ->
	Size = 3,
	io:format("get next test~n", []),
	lists:foreach(fun(CurrentPoint)->
		GP = get_next(Size, CurrentPoint),
		io:format("Size: ~p, CurrentPoint: ~p, GotPoint: ~p~n", 
			[Size, CurrentPoint, GP])
	end, lists:seq(0, Size - 1)).


test_get_position() ->
	Size = 3,
	lists:foreach(fun(CurrentPoint) ->
		lists:foreach(fun(Pos)->
			GP = get_position(Size, CurrentPoint, Pos),
			io:format("Size: ~p, CurrentPoint: ~p, Pos: ~p, GotPoint: ~p~n", 
				[Size, CurrentPoint, Pos, GP])
		end, lists:seq(1, Size))
	end, lists:seq(0, Size - 1)).

test() ->
	Size = 3,
	RB = rbuf:new(3, random, undefined),
	lists:foreach(fun(Pos) -> 
		{{value, undefined}, RB} = rbuf:get(Pos, RB)
	end, lists:seq(1, Size)),

	RB2 = lists:foldr(fun(Pos, Buf) ->
		{ok, NewBuf} = rbuf:set({item, Pos}, Pos, Buf),
		NewBuf
		end, RB, lists:seq(1, Size)),

	{{value, {item, 1}}, RB3} = rbuf:get(RB2),

	{{value, {item, 2}}, RB4} = rbuf:get(RB3),

	{{value, {item, 3}}, _RB5} = rbuf:get(RB4),

	{error, out_of_range} = rbuf:get(Size + 1, RB),

	{error, out_of_range} = rbuf:get(0, RB),

	{error, out_of_range} = rbuf:get(-1, RB),

	ok.