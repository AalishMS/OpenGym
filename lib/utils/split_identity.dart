import 'package:uuid/uuid.dart';

const Uuid _splitUuid = Uuid();

String defaultSplitIdForUser(String userId) => _splitUuid.v5(
  Namespace.url.value,
  'https://opengym.app/users/$userId/default-split',
);
