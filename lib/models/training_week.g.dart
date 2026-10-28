// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'training_week.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class TrainingWeekAdapter extends TypeAdapter<TrainingWeek> {
  @override
  final int typeId = 9;

  @override
  TrainingWeek read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return TrainingWeek(
      id: fields[0] as String,
      splitId: fields[1] as String,
      blockId: fields[2] as String,
      number: fields[3] as int,
      createdAt: fields[4] as DateTime,
      userId: fields[5] as String?,
      updatedAt: fields[6] as DateTime?,
      deletedAt: fields[7] as DateTime?,
      dirty: fields[8] as bool?,
    );
  }

  @override
  void write(BinaryWriter writer, TrainingWeek obj) {
    writer
      ..writeByte(9)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.splitId)
      ..writeByte(2)
      ..write(obj.blockId)
      ..writeByte(3)
      ..write(obj.number)
      ..writeByte(4)
      ..write(obj.createdAt)
      ..writeByte(5)
      ..write(obj.userId)
      ..writeByte(6)
      ..write(obj.updatedAt)
      ..writeByte(7)
      ..write(obj.deletedAt)
      ..writeByte(8)
      ..write(obj.dirty);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TrainingWeekAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
