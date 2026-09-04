// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'split.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class SplitAdapter extends TypeAdapter<Split> {
  @override
  final int typeId = 6;

  @override
  Split read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return Split(
      id: fields[0] as String,
      name: fields[1] as String,
      createdAt: fields[3] as DateTime,
      userId: fields[2] as String?,
      updatedAt: fields[4] as DateTime?,
      deletedAt: fields[5] as DateTime?,
      dirty: fields[6] as bool?,
    );
  }

  @override
  void write(BinaryWriter writer, Split obj) {
    writer
      ..writeByte(7)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.name)
      ..writeByte(2)
      ..write(obj.userId)
      ..writeByte(3)
      ..write(obj.createdAt)
      ..writeByte(4)
      ..write(obj.updatedAt)
      ..writeByte(5)
      ..write(obj.deletedAt)
      ..writeByte(6)
      ..write(obj.dirty);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SplitAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
