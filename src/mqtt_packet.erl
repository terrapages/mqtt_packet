%%%-------------------------------------------------------------------
%%% @author zhengyinyong
%%% @copyright (C) 2016, Yunba
%%% @doc
%%%
%%% @end
%%% Created : 22. 五月 2016 上午11:53
%%%-------------------------------------------------------------------
-module(mqtt_packet).

-include("mqtt_packet.hrl").

-export([parse/2, serialise/2]).

parse(MqttPackage, ProtocolVersion) ->
    case parse(MqttPackage, none, ProtocolVersion) of
        {ok, Frame, _} ->
            {ok, Frame};
        {error, Reason} ->
            {error, Reason}
    end.

serialise(#mqtt_frame{ fixed = Fixed,
                       variable = Variable,
                       payload  = Payload },
          ProtocolVersion) ->
    serialise_variable(Fixed, Variable, serialise_payload(Payload), ProtocolVersion).

%%%===================================================================
%%% Internal functions
%%%===================================================================
parse(<<>>, none, _ProtocolVersion) ->
    {more, fun(Bin, Ver) -> parse(Bin, none, Ver) end};
parse(<<MessageType:4, Dup:1, QoS:2, Retain:1, Rest/binary>>, none, ProtocolVersion) ->
    parse_remaining_len(Rest, #mqtt_frame_fixed{ type   = MessageType,
                                                 dup    = bool(Dup),
                                                 qos    = QoS,
                                                 retain = bool(Retain) }, ProtocolVersion);
parse(Bin, Cont, ProtocolVersion) -> Cont(Bin, ProtocolVersion).

parse_remaining_len(<<>>, Fixed, _ProtocolVersion) ->
    {more, fun(Bin, Ver) -> parse_remaining_len(Bin, Fixed, Ver) end};
parse_remaining_len(Rest, Fixed, ProtocolVersion) ->
    parse_remaining_len(Rest, Fixed, ProtocolVersion, 1, 0, 0).
parse_remaining_len(_Bin, _Fixed, _ProtocolVersion, _Multiplier, Length, _Bytecount)
    when Length > ?MAX_LEN ->
    {error, invalid_mqtt_frame_len};
parse_remaining_len(<<>>, Fixed, _ProtocolVersion, Multiplier, Length, ByteCount) ->
    {more, fun(Bin, Ver) -> parse_remaining_len(Bin, Fixed, Ver, Multiplier, Length, ByteCount) end};
parse_remaining_len(<<1:1, _Len:7, _Rest/binary>>, _Fixed, _ProtocolVersion, _Multiplier, _Value, Bytecount)
    when Bytecount =:= (?MAX_REMAIN_BYTE - 1) ->
    {error, invalid_mqtt_frame_len};
parse_remaining_len(<<1:1, Len:7, Rest/binary>>, Fixed, ProtocolVersion, Multiplier, Value, Bytecount) ->
    parse_remaining_len(Rest, Fixed, ProtocolVersion, Multiplier * ?HIGHBIT, Value + Len * Multiplier, Bytecount+1);
parse_remaining_len(<<0:1, Len:7, Rest/binary>>, Fixed, ProtocolVersion, Multiplier, Value, _Bytecout) ->
    parse_frame(Rest, Fixed, ProtocolVersion, Value + Len * Multiplier).

parse_frame(Bin, #mqtt_frame_fixed{ type = Type,
                                    qos  = QoS } = Fixed, ProtocolVersion, Length) ->

    MessageIdLen = message_id_len(ProtocolVersion),
    try
      case {Type, Bin} of
          {?CONNECT, <<FrameBin:Length/binary, Rest/binary>>} ->
              {ProtocolMagic, Rest1} = parse_utf(FrameBin),
              <<ProtoVersion : 8, Rest2/binary>> = Rest1,
              <<UsernameFlag : 1,
                PasswordFlag : 1,
                WillRetain   : 1,
                WillQos      : 2,
                WillFlag     : 1,
                CleanSession : 1,
                Reserved     : 1,
                KeepAlive    : 16/big,
                Rest3/binary>>   = Rest2,
              {ClientId,  Rest4} = parse_utf(Rest3),
              {WillTopic, Rest5} = parse_utf(Rest4, WillFlag),
              {WillMsg,   Rest6} = parse_msg(Rest5, WillFlag),
              {UserName,  Rest7} = parse_utf(Rest6, UsernameFlag),
              {PasssWord, <<>>}  = parse_utf(Rest7, PasswordFlag),
              case ProtocolMagic == ?PROTOCOL_MAGIC of
                  true ->
                      wrap(Fixed,
                           #mqtt_frame_connect{
                             proto_ver   = ProtoVersion,
                             username_flag    = UsernameFlag,
                             password_flag    = PasswordFlag,
                             will_retain = bool(WillRetain),
                             will_qos    = WillQos,
                             will_flag   = bool(WillFlag),
                             clean_sess  = bool(CleanSession),
                             reserved    = Reserved,
                             keep_alive  = KeepAlive,
                             client_id   = ClientId,
                             will_topic  = WillTopic,
                             will_msg    = WillMsg,
                             username    = UserName,
                             password    = PasssWord}, Rest3, Rest);
                 false ->
                      {error, protocol_header_corrupt}
              end;
          {?PUBLISH, <<FrameBin:Length/binary, Rest/binary>>} ->
              {TopicName, Rest1} = parse_utf(FrameBin),
              {MessageId, Payload} = case QoS of
                                         0 -> {undefined, Rest1};
                                         _ -> <<M:MessageIdLen/big, R/binary>> = Rest1,
                                              {M, R}
                                     end,
              wrap(Fixed, #mqtt_frame_publish {topic_name = TopicName,
                                               message_id = MessageId },
                   Payload, Rest);
          {?PUBACK, <<FrameBin:Length/binary, Rest/binary>>} ->
              <<MessageId:MessageIdLen/big>> = FrameBin,
              wrap(Fixed, #mqtt_frame_publish{message_id = MessageId}, Rest);
          {?PUBREC, <<FrameBin:Length/binary, Rest/binary>>} ->
              <<MessageId:MessageIdLen/big>> = FrameBin,
              wrap(Fixed, #mqtt_frame_publish{message_id = MessageId}, Rest);
          {?PUBREL, <<FrameBin:Length/binary, Rest/binary>>} ->
              <<MessageId:MessageIdLen/big>> = FrameBin,
              wrap(Fixed, #mqtt_frame_publish { message_id = MessageId }, Rest);
          {?PUBCOMP, <<FrameBin:Length/binary, Rest/binary>>} ->
              <<MessageId:MessageIdLen/big>> = FrameBin,
              wrap(Fixed, #mqtt_frame_publish { message_id = MessageId }, Rest);
          {?UNSUBACK, <<FrameBin:Length/binary, Rest/binary>>} ->
              <<MessageId:MessageIdLen/big>> = FrameBin,
              wrap(Fixed, #mqtt_frame_unsuback{message_id = MessageId}, Rest);
          {?EXTCMD, <<FrameBin:Length/binary, Rest/binary>>} ->
              <<MessageId:MessageIdLen/big, Payload/binary>> = FrameBin,
              wrap(Fixed, #mqtt_frame_publish {message_id = MessageId},
                       Payload, Rest);
          {?SUBACK, <<FrameBin:Length/binary, Rest/binary>>} ->
              <<MessageId:MessageIdLen/big, QosTable/binary>> = FrameBin,
              wrap(Fixed, #mqtt_frame_suback {message_id = MessageId,
                  qos_table = binary_to_list(QosTable)}, Rest);
          {Subs, <<FrameBin:Length/binary, Rest/binary>>}
            when Subs =:= ?SUBSCRIBE orelse Subs =:= ?UNSUBSCRIBE ->
              1 = QoS,
              <<MessageId:MessageIdLen/big, Rest1/binary>> = FrameBin,
              Topics = parse_topics(Subs, Rest1, []),
              wrap(Fixed, #mqtt_frame_subscribe { message_id  = MessageId,
                                                  topic_table = Topics }, Rest1, Rest);
          {Minimal, Rest}
            when Minimal =:= ?DISCONNECT orelse Minimal =:= ?PINGREQ ->
              Length = 0,
              wrap(Fixed, Rest);
          {_, TooShortBin} ->
              {more, fun(BinMore, Ver) ->
                             parse_frame(<<TooShortBin/binary, BinMore/binary>>,
                                         Fixed, Ver, Length)
                     end}
      end
    catch
      _:_X ->
      {error, mqtt_corrupt}
    end.

message_id_len(ProtocolVersion) ->
    MessageIdLen =
        if
            ProtocolVersion == 16#13 ->
                64;
            true ->
                16
        end,
    MessageIdLen.

parse_topics(_, <<>>, Topics) ->
    Topics;
parse_topics(?SUBSCRIBE = Sub, Bin, Topics) ->
    {Name, <<_:6, QoS:2, Rest/binary>>} = parse_utf(Bin),
    parse_topics(Sub, Rest, [#mqtt_topic { name = Name, qos = QoS } | Topics]);
parse_topics(?UNSUBSCRIBE = Sub, Bin, Topics) ->
    {Name, <<Rest/binary>>} = parse_utf(Bin),
    parse_topics(Sub, Rest, [#mqtt_topic { name = Name } | Topics]).

wrap(Fixed, Variable, Payload, Rest) ->
    {ok, #mqtt_frame { variable = Variable, fixed = Fixed, payload = Payload }, Rest}.
wrap(Fixed, Variable, Rest) ->
    {ok, #mqtt_frame { variable = Variable, fixed = Fixed }, Rest}.
wrap(Fixed, Rest) ->
    {ok, #mqtt_frame { fixed = Fixed }, Rest}.

parse_utf(Bin, 0) ->
    {undefined, Bin};
parse_utf(Bin, _) ->
    parse_utf(Bin).

parse_utf(<<Len:16/big, Str:Len/binary, Rest/binary>>) ->
    {binary_to_list(Str), Rest}.

parse_msg(Bin, 0) ->
    {undefined, Bin};
parse_msg(<<Len:16/big, Msg:Len/binary, Rest/binary>>, _) ->
    {Msg, Rest}.

bool(0) -> false;
bool(1) -> true.

bool_to_integer(false) -> 0;
bool_to_integer(true) -> 1.

serialise_payload(undefined)           -> <<>>;
serialise_payload(B) when is_binary(B) -> B.

serialise_variable(#mqtt_frame_fixed   { type        = ?CONNECT } = Fixed,
                   #mqtt_frame_connect { 
                             proto_ver   = ProtoVer,
                             will_retain = WillRetain,
                             will_qos    = WillQos,
                             will_flag   = WillFlag,
                             clean_sess  = CleanSession,
                             keep_alive  = KeepAlive,
                             client_id   = _ClientId,
                             username_flag = UsernameFlag,
                             password_flag = PasswordFlag,
                             reserved    = Reserved},
                    PayloadBin, _ProtocolVersion) ->
    StringBin = unicode:characters_to_binary(?PROTOCOL_MAGIC),
    Len = size(StringBin),
    true = (Len =< 16#ffff),
    WillRetainInteger = bool_to_integer(WillRetain),
    WillFlagInteger = bool_to_integer(WillFlag),
    CleanSessionInteger = bool_to_integer(CleanSession),
    VariableBin = <<Len:16/big,
                    StringBin/binary, 
                    ProtoVer : 8,
                    UsernameFlag : 1,
                    PasswordFlag : 1,
                    WillRetainInteger   : 1,
                    WillQos      : 2,
                    WillFlagInteger     : 1,
                    CleanSessionInteger : 1,
                    Reserved    : 1,
                    KeepAlive    : 16/big>>,
    serialise_fixed(Fixed, VariableBin, PayloadBin);

serialise_variable(#mqtt_frame_fixed   { type        = ?CONNACK } = Fixed,
                   #mqtt_frame_connack { return_code = ReturnCode },
                   <<>> = PayloadBin, _ProtocolVersion) ->
    VariableBin = <<?RESERVED:8, ReturnCode:8>>,
    serialise_fixed(Fixed, VariableBin, PayloadBin);

serialise_variable(#mqtt_frame_fixed  { type       = SubAck } = Fixed,
                   #mqtt_frame_suback { message_id = MessageId,
                                        qos_table  = QoS },
                   <<>> = _PayloadBin, ProtocolVersion)
  when SubAck =:= ?SUBACK orelse SubAck =:= ?UNSUBACK ->
    MessageIdLen = message_id_len(ProtocolVersion),
    VariableBin = <<MessageId:MessageIdLen/big>>,
    QosBin = << <<?RESERVED:6, Q:2>> || Q <- QoS >>,
    serialise_fixed(Fixed, VariableBin, QosBin);

serialise_variable(#mqtt_frame_fixed   { type       = ?PUBLISH,
                                         qos        = QoS } = Fixed,
                   #mqtt_frame_publish { topic_name = TopicName,
                                         message_id = MessageId },
                   PayloadBin, ProtocolVersion) ->
    MessageIdLen = message_id_len(ProtocolVersion),
    TopicBin = serialise_utf(TopicName),
    MessageIdBin = case QoS of
                       0 -> <<>>;
                       1 -> <<MessageId:MessageIdLen/big>>;
                       2 -> <<MessageId:MessageIdLen/big>>
                   end,
    serialise_fixed(Fixed, <<TopicBin/binary, MessageIdBin/binary>>, PayloadBin);

serialise_variable(#mqtt_frame_fixed   { type       = ?PUBACK } = Fixed,
                   #mqtt_frame_publish { message_id = MessageId },
                   PayloadBin, ProtocolVersion) ->
    MessageIdLen = message_id_len(ProtocolVersion),
    MessageIdBin = <<MessageId:MessageIdLen/big>>,
    serialise_fixed(Fixed, MessageIdBin, PayloadBin);

serialise_variable(#mqtt_frame_fixed   { type       = ?EXTCMD } = Fixed,
    #mqtt_frame_publish { message_id = MessageId },
    PayloadBin, ProtocolVersion) ->
  MessageIdLen = message_id_len(ProtocolVersion),
  MessageIdBin = <<MessageId:MessageIdLen/big>>,
  serialise_fixed(Fixed, MessageIdBin, PayloadBin);

serialise_variable(#mqtt_frame_fixed   { type       = ?SUBSCRIBE } = Fixed,
                   #mqtt_frame_subscribe { message_id = MessageId,
                                           topic_table = _Topics },
                   PayloadBin, ProtocolVersion) ->
    MessageIdLen = message_id_len(ProtocolVersion),
    MessageIdBin = <<MessageId:MessageIdLen/big>>,
    serialise_fixed(Fixed, MessageIdBin, PayloadBin);

serialise_variable(#mqtt_frame_fixed   { type       = ?UNSUBSCRIBE } = Fixed,
                   #mqtt_frame_subscribe { message_id = MessageId,
                                           topic_table = _Topics },
                   PayloadBin, ProtocolVersion) ->
    MessageIdLen = message_id_len(ProtocolVersion),
    MessageIdBin = <<MessageId:MessageIdLen/big>>,
    serialise_fixed(Fixed, MessageIdBin, PayloadBin);

serialise_variable(#mqtt_frame_fixed   { type       = ?UNSUBACK } = Fixed,
    #mqtt_frame_unsuback { message_id = MessageId },
    PayloadBin, ProtocolVersion) ->
  MessageIdLen = message_id_len(ProtocolVersion),
  MessageIdBin = <<MessageId:MessageIdLen/big>>,
  serialise_fixed(Fixed, MessageIdBin, PayloadBin);

serialise_variable(#mqtt_frame_fixed { type = ?PUBREC } = Fixed,
                   #mqtt_frame_publish{ message_id = MsgId}, PayloadBin, ProtocolVersion) ->
    MessageIdLen = message_id_len(ProtocolVersion),
    serialise_fixed(Fixed, <<MsgId:MessageIdLen/big>>, PayloadBin);

serialise_variable(#mqtt_frame_fixed { type = ?PUBREL } = Fixed,
                   #mqtt_frame_publish{ message_id = MsgId}, PayloadBin, ProtocolVersion) ->
    MessageIdLen = message_id_len(ProtocolVersion),
    serialise_fixed(Fixed, <<MsgId:MessageIdLen/big>>, PayloadBin);

serialise_variable(#mqtt_frame_fixed { type = ?PUBCOMP } = Fixed,
                   #mqtt_frame_publish{ message_id = MsgId}, PayloadBin, ProtocolVersion) ->
    MessageIdLen = message_id_len(ProtocolVersion),
    serialise_fixed(Fixed, <<MsgId:MessageIdLen/big>>, PayloadBin);

serialise_variable(#mqtt_frame_fixed { type = ?EXTCMD } = Fixed,
                   #mqtt_frame_extcmd_recvack { message_id = MsgId,
                       ext_cmd = ?EXTCMD_RECVACK, status = Status,
                       payload = Payload },
                   PayloadBin, ProtocolVersion) ->
    MessageIdLen = message_id_len(ProtocolVersion),
    Len = size(Payload),
    true = (Len < 65535),
    ExtCommandBin = <<?EXTCMD_RECVACK:8, Status:8, Len:16/integer-unsigned-big, Payload/binary, PayloadBin/binary>>,
    serialise_fixed(Fixed, <<MsgId:MessageIdLen/big>>, ExtCommandBin);

serialise_variable(#mqtt_frame_fixed {} = Fixed,
                   undefined,
                   <<>> = _PayloadBin, _ProtocolVersion) ->
    serialise_fixed(Fixed, <<>>, <<>>).

serialise_fixed(#mqtt_frame_fixed{ type   = Type,
                                   dup    = Dup,
                                   qos    = QoS,
                                   retain = Retain }, VariableBin, PayloadBin)
  when is_integer(Type) andalso ?CONNECT =< Type andalso Type =< ?EXTCMD ->
    Len = size(VariableBin) + size(PayloadBin),
    true = (Len =< ?MAX_LEN),
    LenBin = serialise_len(Len),
    <<Type:4, (opt(Dup)):1, (opt(QoS)):2, (opt(Retain)):1,
      LenBin/binary, VariableBin/binary, PayloadBin/binary>>.

serialise_utf(String) ->
    StringBin = unicode:characters_to_binary(String),
    Len = size(StringBin),
    true = (Len =< 16#ffff),
    <<Len:16/big, StringBin/binary>>.

serialise_len(N) when N =< ?LOWBITS ->
    <<0:1, N:7>>;
serialise_len(N) ->
    <<1:1, (N rem ?HIGHBIT):7, (serialise_len(N div ?HIGHBIT))/binary>>.

opt(undefined)            -> ?RESERVED;
opt(false)                -> 0;
opt(true)                 -> 1;
opt(X) when is_integer(X) -> X.
