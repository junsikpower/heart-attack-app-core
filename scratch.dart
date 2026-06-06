import 'dart:io';
import 'dart:math';

List<double> normalize(List<double> rawBuffer) {
  if (rawBuffer.isEmpty) return [];
  final minVal = rawBuffer.reduce((a, b) => a < b ? a : b);
  final maxVal = rawBuffer.reduce((a, b) => a > b ? a : b);
  final range = (maxVal - minVal) == 0 ? 1.0 : (maxVal - minVal);
  return rawBuffer.map((v) => (v - minVal) / range).toList();
}

Map<String, List<dynamic>> resampleSignal(List<int> timeMs, List<double> values, int targetHz) {
  if (timeMs.length < 2 || timeMs.length != values.length) return {'times': <int>[], 'values': <double>[]};
  final int startTime = timeMs.first;
  final int endTime = timeMs.last;
  final double intervalMs = 1000.0 / targetHz;
  List<int> resampledTimes = [];
  List<double> resampledValues = [];
  double targetTimeDouble = startTime.toDouble();
  int currentIndex = 0;
  while (targetTimeDouble <= endTime) {
    int targetTime = targetTimeDouble.round();
    while (currentIndex < timeMs.length - 2 && timeMs[currentIndex + 1] < targetTime) {
      currentIndex++;
    }
    int t0 = timeMs[currentIndex];
    double v0 = values[currentIndex];
    int t1 = timeMs[currentIndex + 1];
    double v1 = values[currentIndex + 1];
    double interpolatedValue = v0;
    if (t1 > t0) {
      double ratio = (targetTime - t0) / (t1 - t0);
      interpolatedValue = v0 + (v1 - v0) * ratio;
    }
    resampledTimes.add(targetTime);
    resampledValues.add(interpolatedValue);
    targetTimeDouble += intervalMs;
  }
  return {'times': resampledTimes, 'values': resampledValues};
}

List<double> applyBandPassFilter(List<double> signal) {
  if (signal.length < 3) return List.from(signal);
  final double alphaLp = 0.42;
  List<double> lpSignal = List.filled(signal.length, 0.0);
  lpSignal[0] = signal[0];
  for (int i = 1; i < signal.length; i++) {
    lpSignal[i] = lpSignal[i - 1] + alphaLp * (signal[i] - lpSignal[i - 1]);
  }
  final double alphaHp = 0.87;
  List<double> hpSignal = List.filled(signal.length, 0.0);
  hpSignal[0] = 0.0;
  for (int i = 1; i < signal.length; i++) {
    hpSignal[i] = alphaHp * hpSignal[i - 1] + alphaHp * (lpSignal[i] - lpSignal[i - 1]);
  }
  return hpSignal;
}

List<int> findPeaksWithProminence(List<double> signal, double minProminence) {
  List<int> peaks = [];
  if (signal.length < 3) return peaks;
  for (int i = 1; i < signal.length - 1; i++) {
    if (signal[i] > signal[i - 1] && signal[i] > signal[i + 1]) {
      double leftValley = signal[i];
      for (int j = i - 1; j >= 0; j--) {
        if (signal[j] > signal[i]) break;
        if (signal[j] < leftValley) leftValley = signal[j];
      }
      double rightValley = signal[i];
      for (int j = i + 1; j < signal.length; j++) {
        if (signal[j] > signal[i]) break;
        if (signal[j] < rightValley) rightValley = signal[j];
      }
      double prominence = signal[i] - max(leftValley, rightValley);
      if (prominence >= minProminence) {
        peaks.add(i);
      }
    }
  }
  return peaks;
}

void main() async {
  final file = File('predata/heart_attack_debug_log_1779237978626.csv');
  final lines = await file.readAsLines();
  List<int> times = [];
  List<double> reds = [];
  
  for (int i = 1; i < lines.length; i++) {
    final parts = lines[i].split(',');
    if (parts.length >= 3) {
      times.add(int.parse(parts[0]));
      reds.add(double.parse(parts[1]));
    }
  }
  
  if (times.length < 150) return;
  
  // Pick one window somewhere in the middle
  int start = 100;
  if (start + 150 > times.length) return;
  
  List<int> winTimes = times.sublist(start, start + 150);
  List<double> winReds = reds.sublist(start, start + 150);
  
  var resampled = resampleSignal(winTimes, winReds, 30);
  var rTimes = resampled['times'] as List<int>;
  var rVals = resampled['values'] as List<double>;
  
  var filtered = applyBandPassFilter(rVals);
  if (filtered.length > 60) {
    filtered = filtered.sublist(60);
    rTimes = rTimes.sublist(60);
  }
  
  var norm = normalize(filtered);
  
  print("Filtered signal size: \${filtered.length}");
  // Print some normalized values to see what the wave looks like
  for (int i = 0; i < 20; i++) {
    print("norm[\$i]: \${norm[i].toStringAsFixed(3)}");
  }
  
  for (double prom in [0.2, 0.3, 0.4, 0.5]) {
    var peaks = findPeaksWithProminence(norm, prom);
    print("Prominence \$prom found \${peaks.length} peaks: \$peaks");
  }
}
