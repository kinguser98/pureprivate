// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'iptv_channel.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class IptvChannelAdapter extends TypeAdapter<IptvChannel> {
  @override
  final int typeId = 1;

  @override
  IptvChannel read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return IptvChannel(
      id: fields[0] as int,
      name: fields[1] as String,
      customName: fields[2] as String?,
      logoUrl: fields[3] as String,
      cmd: fields[4] as String,
      categoryName: fields[5] as String,
      enabled: fields[6] as bool,
      position: fields[7] as int,
      portalId: fields[8] as int,
      portalName: fields[9] as String?,
      stalkerId: fields[10] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, IptvChannel obj) {
    writer.writeByte(11);
    writer.writeByte(0);
    writer.write(obj.id);
    writer.writeByte(1);
    writer.write(obj.name);
    writer.writeByte(2);
    writer.write(obj.customName);
    writer.writeByte(3);
    writer.write(obj.logoUrl);
    writer.writeByte(4);
    writer.write(obj.cmd);
    writer.writeByte(5);
    writer.write(obj.categoryName);
    writer.writeByte(6);
    writer.write(obj.enabled);
    writer.writeByte(7);
    writer.write(obj.position);
    writer.writeByte(8);
    writer.write(obj.portalId);
    writer.writeByte(9);
    writer.write(obj.portalName);
    writer.writeByte(10);
    writer.write(obj.stalkerId);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is IptvChannelAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
