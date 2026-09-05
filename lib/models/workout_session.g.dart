// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'workout_session.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class WorkoutSessionAdapter extends TypeAdapter<WorkoutSession> {
  @override
  final int typeId = 4;

  @override
  WorkoutSession read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return WorkoutSession(
      date: fields[0] as DateTime,
      planName: fields[1] as String,
      exercises: (fields[2] as List).cast<Exercise>(),
      weekNumber: fields[3] as int,
      id: fields[4] as String?,
      userId: fields[5] as String?,
      planId: fields[6] as String?,
      updatedAt: fields[7] as DateTime?,
      deletedAt: fields[8] as DateTime?,
      dirty: fields[9] as bool?,
      splitId: fields[10] as String?,
      isCompleted: fields[11] == null ? true : fields[11] as bool,
      startedAt: fields[12] as DateTime?,
      timerStartedAt: fields[13] as DateTime?,
      durationSeconds: fields[14] as int?,
    );
  }

  @override
  void write(BinaryWriter writer, WorkoutSession obj) {
    writer
      ..writeByte(15)
      ..writeByte(0)
      ..write(obj.date)
      ..writeByte(1)
      ..write(obj.planName)
      ..writeByte(2)
      ..write(obj.exercises)
      ..writeByte(3)
      ..write(obj.weekNumber)
      ..writeByte(4)
      ..write(obj.id)
      ..writeByte(5)
      ..write(obj.userId)
      ..writeByte(6)
      ..write(obj.planId)
      ..writeByte(7)
      ..write(obj.updatedAt)
      ..writeByte(8)
      ..write(obj.deletedAt)
      ..writeByte(9)
      ..write(obj.dirty)
      ..writeByte(10)
      ..write(obj.splitId)
      ..writeByte(11)
      ..write(obj.isCompleted)
      ..writeByte(12)
      ..write(obj.startedAt)
      ..writeByte(13)
      ..write(obj.timerStartedAt)
      ..writeByte(14)
      ..write(obj.durationSeconds);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WorkoutSessionAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
