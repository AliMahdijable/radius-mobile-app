class OntOpticalInfo {
  final String txPower;
  final String rxPower;
  final String voltage;
  final String temperature;
  final String bias;
  final String sendStatus;

  const OntOpticalInfo({
    required this.txPower,
    required this.rxPower,
    required this.voltage,
    required this.temperature,
    required this.bias,
    required this.sendStatus,
  });

  bool get txOk {
    final v = double.tryParse(txPower);
    return v != null && v >= 0.5 && v <= 5.0;
  }

  bool get rxOk {
    final v = double.tryParse(rxPower);
    return v != null && v >= -27.0 && v <= -3.0;
  }

  bool get voltageOk {
    final v = double.tryParse(voltage);
    return v != null && v >= 3100 && v <= 3500;
  }

  bool get biasOk {
    final v = double.tryParse(bias);
    return v != null && v >= 0 && v <= 90;
  }

  bool get tempOk {
    final v = double.tryParse(temperature);
    return v != null && v >= -10 && v <= 85;
  }
}

class OntLoginResult {
  final String sessionCookie;
  final String baseUrl;

  const OntLoginResult({required this.sessionCookie, required this.baseUrl});
}

class OntVoipLine {
  final int index;
  final String directoryNumber;
  final String status;
  final String callState;
  final String registerError;

  const OntVoipLine({
    required this.index,
    required this.directoryNumber,
    required this.status,
    required this.callState,
    required this.registerError,
  });

  bool get isUp => status.toLowerCase() == 'up';
  bool get isDisabled => status.toLowerCase() == 'disabled';
  bool get isRegistered => isUp && registerError.isEmpty;
}
