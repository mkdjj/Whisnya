import '../../models/theater.dart';

sealed class TheaterGenerationEvent {
  const TheaterGenerationEvent();
}

final class TheaterMessageStarted extends TheaterGenerationEvent {
  const TheaterMessageStarted(this.message);
  final TheaterMessage message;
}

final class TheaterMessageDelta extends TheaterGenerationEvent {
  const TheaterMessageDelta(this.messageId, this.delta);
  final String messageId;
  final String delta;
}

final class TheaterMessageFinished extends TheaterGenerationEvent {
  const TheaterMessageFinished(this.message);
  final TheaterMessage message;
}

final class TheaterMessageRemoved extends TheaterGenerationEvent {
  const TheaterMessageRemoved(this.messageId);
  final String messageId;
}

final class TheaterGenerationFailed extends TheaterGenerationEvent {
  const TheaterGenerationFailed(this.message);
  final TheaterMessage message;
}
