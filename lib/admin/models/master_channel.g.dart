// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'master_channel.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class MasterChannelAdapter extends TypeAdapter<MasterChannel> {
  @override
  final int typeId = 20;

  @override
  MasterChannel read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return MasterChannel(
      id: fields[0] as String,
      displayName: fields[1] as String,
      logoUrl: fields[2] as String,
      epgId: fields[3] as String,
      categoryName: fields[4] as String,
      aliases: (fields[5] as List).cast<String>(),
      updatedAt: fields[6] as DateTime?,
      language: fields[7] as String? ?? 'Malayalam',
    );
  }

  @override
  void write(BinaryWriter writer, MasterChannel obj) {
    writer
      ..writeByte(8)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.displayName)
      ..writeByte(2)
      ..write(obj.logoUrl)
      ..writeByte(3)
      ..write(obj.epgId)
      ..writeByte(4)
      ..write(obj.categoryName)
      ..writeByte(5)
      ..write(obj.aliases)
      ..writeByte(6)
      ..write(obj.updatedAt)
      ..writeByte(7)
      ..write(obj.language);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MasterChannelAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
