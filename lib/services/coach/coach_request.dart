// The request the app sends the Coach proxy. Kept free of Flutter so
// tool/coach_eval can build requests with the same types.

/// The request and response shape this build speaks. The proxy must support
/// it before an app that sends it ships (see docs/coach.md, "Contract
/// versioning").
const int kCoachContractVersion = 1;

/// The proxy rejects more than this many messages.
const int kCoachMaxMessages = 12;

/// The proxy rejects bodies over 32 KB. The client keeps a margin under it.
const int kCoachMaxBodyBytes = 30 * 1024;

class CoachMessage {
  /// `user` or `assistant`.
  final String role;
  final String content;

  const CoachMessage.user(this.content) : role = 'user';
  const CoachMessage.assistant(this.content) : role = 'assistant';

  Map<String, dynamic> toJson() => {'role': role, 'content': content};
}

/// The second attempt of a turn: the output that failed validation and the
/// errors, so the model can correct it.
class CoachRetry {
  final String previousOutput;
  final List<String> errors;

  const CoachRetry({required this.previousOutput, required this.errors});

  Map<String, dynamic> toJson() => {
    'previousOutput': previousOutput,
    'errors': errors,
  };
}

class CoachRequest {
  final Map<String, dynamic> context;

  /// Oldest first; the last one is the user's.
  final List<CoachMessage> messages;
  final CoachRetry? retry;

  const CoachRequest({
    required this.context,
    required this.messages,
    this.retry,
  });

  Map<String, dynamic> toJson() => {
    'contractVersion': kCoachContractVersion,
    'context': context,
    'messages': [for (final message in messages) message.toJson()],
    if (retry != null) 'retry': retry!.toJson(),
  };
}
