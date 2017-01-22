## Overview
---

`mqtt_packet` 是对 Yunba MQTT protocol 的解析和序列化。提供以下两个 API：

- `parse`

        mqtt_packet:parse(MqttPackage, ProtocolVersion);

     将 MQTT Package 解析成 `mqtt_frame{}(include/mqtt_packet.hrl)` 形式数据；


- `serialise`

        mqtt_packet:serialise(mqtt_frame{}, ProtocolVersion);

     这是 `parse` 的逆操作，将 `mqtt_frame{}` 变量数据序列化成 MQTT 二进制数据包。