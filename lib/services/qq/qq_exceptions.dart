class QqIntegrationException implements Exception {
  const QqIntegrationException(this.message);
  final String message;
  @override
  String toString() => message;
}

class QqConfigurationException extends QqIntegrationException {
  const QqConfigurationException(super.message);
}

class QqBindingException extends QqIntegrationException {
  const QqBindingException(super.message);
}

class OneBotConnectionException extends QqIntegrationException {
  const OneBotConnectionException(super.message);
}

class OneBotAuthenticationException extends OneBotConnectionException {
  const OneBotAuthenticationException(super.message);
}

class OneBotActionException extends QqIntegrationException {
  const OneBotActionException(super.message);
}

class QqReplyDeliveryException extends QqIntegrationException {
  const QqReplyDeliveryException(super.message);
}

class QqTargetVerificationException extends QqIntegrationException {
  const QqTargetVerificationException(super.message);
}

class QqOperationCancelledException extends QqIntegrationException {
  const QqOperationCancelledException(super.message);
}
