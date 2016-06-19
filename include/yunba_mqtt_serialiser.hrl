%%%-------------------------------------------------------------------
%%% @author zhengyinyong
%%% @copyright (C) 2016, Yunba
%%% @doc
%%%
%%% @end
%%% Created : 06. 五月 2016 上午10:18
%%%-------------------------------------------------------------------
-define(MQTT_PROTO_MAJOR, 3).
-define(MQTT_PROTO_MINOR, 1).

-define(CLOS_MQTT_PROTO_MAJAR, 19).

-define(RESERVED, 0).
-define(PROTOCOL_MAGIC, "MQIsdp").
-define(MAX_LEN, 16#fffffff).
-define(MAX_REMAIN_BYTE, 4).
-define(HIGHBIT, 2#10000000).
-define(LOWBITS, 2#01111111).

%% frame types
-define(CONNECT,      1).
-define(CONNACK,      2).
-define(PUBLISH,      3).
-define(PUBACK,       4).
-define(PUBREC,       5).
-define(PUBREL,       6).
-define(PUBCOMP,      7).
-define(SUBSCRIBE,    8).
-define(SUBACK,       9).
-define(UNSUBSCRIBE, 10).
-define(UNSUBACK,    11).
-define(PINGREQ,     12).
-define(PINGRESP,    13).
-define(DISCONNECT,  14).
-define(EXTCMD,      15).

-define(QOS_0, 0).
-define(QOS_1, 1).
-define(QOS_2, 2).

%% ext commands
-define(EXTCMD_RECVACK, 11).

%% connect return codes
-define(CONNACK_ACCEPT,      0).
-define(CONNACK_PROTO_VER,   1). %% unacceptable protocol version
-define(CONNACK_INVALID_ID,  2). %% identifier rejected
-define(CONNACK_SERVER,      3). %% server unavailable
-define(CONNACK_CREDENTIALS, 4). %% bad user name or password
-define(CONNACK_AUTH,        5). %% not authorized


-record(mqtt_frame, {fixed,
                     variable,
                     payload}).

-record(mqtt_frame_fixed,    {type   = 0,
                              dup    = 0,
                              qos    = 0,
                              retain = 0}).

-record(mqtt_frame_connect,  {proto_ver,
                              will_retain,
                              will_qos,
                              will_flag,
                              clean_sess,
                              keep_alive,
                              client_id,
                              will_topic,
                              will_msg,
                              username_flag,
                              password_flag,
                              username,
                              reserved,
                              password}).

-record(mqtt_frame_connack,  {return_code}).

-record(mqtt_frame_publish,  {topic_name,
                              message_id}).

-record(mqtt_frame_subscribe,{message_id,
                              topic_table}).

-record(mqtt_frame_suback,   {message_id,
                              qos_table = []}).

-record(mqtt_frame_unsuback,  {message_id}).

-record(mqtt_frame_extcmd_recvack, {message_id, ext_cmd, status, payload}).

-record(mqtt_topic,          {name,
                              qos}).

-record(mqtt_frame_other,    {other}).