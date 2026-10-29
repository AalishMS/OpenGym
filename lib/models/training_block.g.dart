// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'training_block.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class TrainingBlockAdapter extends TypeAdapter<TrainingBlock> {
  @override
  final int typeId = 8;

  @override
  TrainingBlock read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return TrainingBlock(
      id: fields[0] as String,
      splitId: fields[1] as String,
      name: fields[2] as String,
      position: fields[3] as int,
      createdAt: fields[4] as DateTime,
      userId: fields[5] as String?,
      updatedAt: fields[6] as DateTime?,
      deletedAt: fields[7] as DateTime?,
      dirty: fields[8] as bool?,
      plannedWeekCount: fields[9] as int?,
    );
  }

  @override
  void write(BinaryWriter writer, TrainingBlock obj) {
    writer
      ..writeByte(10)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.splitId)
      ..writeByte(2)
      ..write(obj.name)
      ..writeByte(3)
      ..write(obj.position)
      ..writeByte(4)
      ..write(obj.createdAt)
      ..writeByte(5)
      ..write(obj.userId)
      ..writeByte(6)
      ..write(obj.updatedAt)
      ..writeByte(7)
      ..write(obj.deletedAt)
      ..writeByte(8)
      ..write(obj.dirty)
      ..writeByte(9)
      ..write(obj.plannedWeekCount);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TrainingBlockAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
