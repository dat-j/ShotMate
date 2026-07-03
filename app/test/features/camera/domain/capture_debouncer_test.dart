import 'package:flutter_test/flutter_test.dart';
import 'package:shotmate_app/features/camera/domain/capture_debouncer.dart';

void main() {
  test('tryStart trả true lần đầu, false khi đang xử lý (EC-7)', () {
    final debouncer = CaptureDebouncer();

    expect(debouncer.tryStart(), isTrue);
    expect(debouncer.inProgress, isTrue);
    // Bấm liên tiếp trong lúc đang xử lý — phải bị chặn.
    expect(debouncer.tryStart(), isFalse);
    expect(debouncer.tryStart(), isFalse);
  });

  test('finish() cho phép lần chụp tiếp theo bắt đầu', () {
    final debouncer = CaptureDebouncer();

    expect(debouncer.tryStart(), isTrue);
    debouncer.finish();
    expect(debouncer.inProgress, isFalse);
    expect(debouncer.tryStart(), isTrue);
  });
}
