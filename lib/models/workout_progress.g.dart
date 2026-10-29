// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'workout_progress.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class WorkoutProgressAdapter extends TypeAdapter<WorkoutProgress> {
  @override
  final int typeId = 10;

  @override
  WorkoutProgress read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return WorkoutProgress(
      id: fields[0] as String,
      splitId: fields[1] as String,
      planId: fields[2] as String,
      activeWeekId: fields[3] as String,
      state: fields[4] as String,
      revision: fields[5] as String,
      userId: fields[6] as String?,
      updatedAt: fields[7] as DateTime?,
      deletedAt: fields[8] as DateTime?,
      dirty: fields[9] as bool?,
      availableWeekIds: (fields[10] as List?)?.cast<String>(),
    );
  }

  @override
  void write(BinaryWriter writer, WorkoutProgress obj) {
    writer
      ..writeByte(11)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.splitId)
      ..writeByte(2)
      ..write(obj.planId)
      ..writeByte(3)
      ..write(obj.activeWeekId)
      ..writeByte(4)
      ..write(obj.state)
      ..writeByte(5)
      ..write(obj.revision)
      ..writeByte(6)
      ..write(obj.userId)
      ..writeByte(7)
      ..write(obj.updatedAt)
      ..writeByte(8)
      ..write(obj.deletedAt)
      ..writeByte(9)
      ..write(obj.dirty)
      ..writeByte(10)
      ..write(obj.availableWeekIds);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WorkoutProgressAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
