// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'split_preference.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class SplitPreferenceAdapter extends TypeAdapter<SplitPreference> {
  @override
  final int typeId = 7;

  @override
  SplitPreference read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return SplitPreference(
      userId: fields[0] as String,
      activeSplitId: fields[1] as String,
      updatedAt: fields[2] as DateTime?,
      dirty: fields[3] as bool?,
    );
  }

  @override
  void write(BinaryWriter writer, SplitPreference obj) {
    writer
      ..writeByte(4)
      ..writeByte(0)
      ..write(obj.userId)
      ..writeByte(1)
      ..write(obj.activeSplitId)
      ..writeByte(2)
      ..write(obj.updatedAt)
      ..writeByte(3)
      ..write(obj.dirty);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SplitPreferenceAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
