import 'dart:async';
import 'dart:io';
import 'dart:math';

// ── ANSI helpers ──────────────────────────────────────────────────────────────

const _reset = '\x1B[0m';
const _bold  = '\x1B[1m';
const _dim   = '\x1B[2m';
const _green = '\x1B[32m';
const _cyan  = '\x1B[36m';

bool get _ansi => stdout.hasTerminal && stdout.supportsAnsiEscapes;
String _c(String s, String code) => _ansi ? '$code$s$_reset' : s;

// ── ProgressBar ───────────────────────────────────────────────────────────────

/// Live progress bar for streaming file downloads.
///
/// ```
///   flutter_3.22.2-stable.zip  ████████████░░░░░░░░  62%  310.4 MB / 500.0 MB  ↓ 8.3 MB/s  ETA 22s
/// ```
///
/// Adapts its bar width to [stdout.terminalColumns].
/// On non-TTY output (CI pipes) rendering is a silent no-op.
class ProgressBar {
  /// Total expected bytes. Pass 0 when the server omits Content-Length.
  final int total;

  /// Short label shown to the left of the bar (filename, version, etc.).
  final String label;

  int _received = 0;

  final _sw = Stopwatch()..start();

  // Speed window: [(elapsed_ms, cumulative_bytes), ...]
  final _samples = <(int, int)>[];
  static const _windowMs = 4000; // 4-second sliding average

  ProgressBar({required this.total, required this.label});

  /// Call on every received chunk with the new cumulative byte count.
  void update(int received) {
    _received = received;
    final now = _sw.elapsedMilliseconds;
    _samples.add((now, received));
    _samples.removeWhere((s) => now - s.$1 > _windowMs);
    _draw();
  }

  /// Finalises the bar (snaps to 100 %, prints a newline).
  void complete() {
    if (total > 0) _received = total;
    _draw(done: true);
    if (_ansi) stdout.writeln();
  }

  void _draw({bool done = false}) {
    if (!_ansi) return;

    final cols    = stdout.terminalColumns.clamp(60, 220);
    final speed   = _computeSpeed();
    final fraction = total > 0 ? (_received / total).clamp(0.0, 1.0) : 0.0;
    final pct     = (fraction * 100).round();

    // ── Right side ──────────────────────────────────────────────────────────
    final pctStr   = '${pct.toString().padLeft(3)}%';
    final sizeStr  = total > 0
        ? '${_fmtBytes(_received)} / ${_fmtBytes(total)}'
        : _fmtBytes(_received);
    final speedStr = speed > 0 ? '↓ ${_fmtSpeed(speed)}' : '';
    final etaStr   = done
        ? 'done'
        : speed > 0 && total > 0
            ? 'ETA ${_fmtEta(((total - _received) / speed).round())}'
            : '';

    final right = [
      pctStr,
      sizeStr,
      if (speedStr.isNotEmpty) speedStr,
      if (etaStr.isNotEmpty)   etaStr,
    ].join('  ');

    // ── Left label ──────────────────────────────────────────────────────────
    // Truncate from the front so the version string at the end stays visible.
    const maxLabel = 32;
    final shortLabel = label.length > maxLabel
        ? '…${label.substring(label.length - maxLabel + 1)}'
        : label;

    // ── Bar width ───────────────────────────────────────────────────────────
    const leftPad = 2;
    const sepW    = 2; // spaces between label↔bar and bar↔right
    final fixedW  = leftPad + shortLabel.length + sepW + sepW + right.length;
    final barW    = max(8, cols - fixedW);

    final filled = (fraction * barW).round().clamp(0, barW);
    final empty  = barW - filled;

    final bar = '${_c('█' * filled, _cyan)}${_c('░' * empty, _dim)}';

    stdout.write(
      '\r\x1B[K'
      '${' ' * leftPad}$shortLabel  '
      '$bar  '
      '${_c(right, _bold)}',
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  double _computeSpeed() {
    if (_samples.length < 2) return 0;
    final dt = _samples.last.$1 - _samples.first.$1;
    if (dt <= 0) return 0;
    return (_samples.last.$2 - _samples.first.$2) / dt * 1000;
  }

  String _fmtBytes(int b) {
    if (b < 1024)            return '$b B';
    if (b < 1024 * 1024)     return '${(b / 1024).toStringAsFixed(1)} KB';
    if (b < 1024 * 1024 * 1024)
      return '${(b / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(b / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  String _fmtSpeed(double bps) {
    if (bps < 1024)        return '${bps.toStringAsFixed(0)} B/s';
    if (bps < 1024 * 1024) return '${(bps / 1024).toStringAsFixed(1)} KB/s';
    return '${(bps / (1024 * 1024)).toStringAsFixed(1)} MB/s';
  }

  String _fmtEta(int secs) {
    if (secs <= 0) return '0s';
    if (secs < 60) return '${secs}s';
    return '${secs ~/ 60}:${(secs % 60).toString().padLeft(2, '0')}';
  }
}

// ── Spinner ───────────────────────────────────────────────────────────────────

/// Animated braille spinner for indeterminate operations.
///
/// ```
///   ⠹ Verifying checksum…
/// ```
///
/// Falls back to a plain text line on non-TTY output.
class Spinner {
  static const _frames = ['⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏'];

  final String label;
  int    _frame = 0;
  Timer? _timer;

  Spinner(this.label);

  /// Starts animating. Safe to call on non-TTY (prints a static line instead).
  void start() {
    if (!_ansi) {
      stdout.writeln('  $label…');
      return;
    }
    _tick();
    _timer = Timer.periodic(const Duration(milliseconds: 80), (_) => _tick());
  }

  /// Stops animating and optionally prints a green success line.
  void stop({String? done}) {
    _timer?.cancel();
    _timer = null;
    if (_ansi) stdout.write('\r\x1B[K');
    if (done != null) stdout.writeln(_c('✓ $done', _green));
  }

  void _tick() {
    stdout.write('\r\x1B[K  ${_c(_frames[_frame], _cyan)} $label…');
    _frame = (_frame + 1) % _frames.length;
  }
}
