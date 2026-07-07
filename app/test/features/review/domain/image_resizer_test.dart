/// Unit test cho `resizeForUpload`/`resizeForUploadInIsolate` (spec-sprint-4
/// FR-S4-9): cạnh dài ≤1568px, giữ tỉ lệ, encode JPEG q85. Dùng `img.Image`
/// synthetic — không cần ảnh thật.
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:shotmate_app/features/review/domain/image_resizer.dart';

void main() {
  group('resizeForUpload', () {
    test('ảnh ngang lớn hơn ngưỡng -> resize cạnh dài xuống 1568, giữ tỉ lệ', () {
      final original = img.Image(width: 3000, height: 2000);
      final inputBytes = img.encodeJpg(original);

      final outputBytes = resizeForUpload(inputBytes);
      final decoded = img.decodeImage(outputBytes)!;

      expect(decoded.width, kMaxLongEdge);
      // Tỉ lệ giữ nguyên (3000:2000 = 3:2) => height = 1568 * 2/3 ~ 1045.
      expect(decoded.height, closeTo(1045, 2));
      expect(decoded.width, lessThanOrEqualTo(kMaxLongEdge));
      expect(decoded.height, lessThanOrEqualTo(kMaxLongEdge));
    });

    test('ảnh dọc lớn hơn ngưỡng -> resize cạnh dài (height) xuống 1568', () {
      final original = img.Image(width: 2000, height: 4000);
      final inputBytes = img.encodeJpg(original);

      final outputBytes = resizeForUpload(inputBytes);
      final decoded = img.decodeImage(outputBytes)!;

      expect(decoded.height, kMaxLongEdge);
      // Tỉ lệ 2000:4000 = 1:2 => width = 1568 / 2 = 784.
      expect(decoded.width, closeTo(784, 2));
    });

    test('ảnh đã nhỏ hơn ngưỡng -> không upscale, giữ nguyên kích thước', () {
      final original = img.Image(width: 800, height: 600);
      final inputBytes = img.encodeJpg(original);

      final outputBytes = resizeForUpload(inputBytes);
      final decoded = img.decodeImage(outputBytes)!;

      expect(decoded.width, 800);
      expect(decoded.height, 600);
    });

    test('ảnh vuông đúng bằng ngưỡng -> giữ nguyên', () {
      final original = img.Image(width: kMaxLongEdge, height: kMaxLongEdge);
      final inputBytes = img.encodeJpg(original);

      final outputBytes = resizeForUpload(inputBytes);
      final decoded = img.decodeImage(outputBytes)!;

      expect(decoded.width, kMaxLongEdge);
      expect(decoded.height, kMaxLongEdge);
    });

    test('output luôn là JPEG hợp lệ decode được lại', () {
      final original = img.Image(width: 2000, height: 2000);
      final inputBytes = img.encodeJpg(original);

      final outputBytes = resizeForUpload(inputBytes);

      // JPEG bắt đầu bằng magic bytes 0xFFD8.
      expect(outputBytes[0], 0xFF);
      expect(outputBytes[1], 0xD8);
      expect(img.decodeImage(outputBytes), isNotNull);
    });

    test('input không decode được -> throws FormatException', () {
      final garbage = Uint8List.fromList([1, 2, 3, 4, 5]);
      expect(() => resizeForUpload(garbage), throwsFormatException);
    });
  });

  group('resizeForUploadInIsolate', () {
    test('chạy trong isolate cho kết quả giống hàm đồng bộ', () async {
      final original = img.Image(width: 3000, height: 1500);
      final inputBytes = img.encodeJpg(original);

      final outputBytes = await resizeForUploadInIsolate(inputBytes);
      final decoded = img.decodeImage(outputBytes)!;

      expect(decoded.width, kMaxLongEdge);
      expect(decoded.height, lessThanOrEqualTo(kMaxLongEdge));
    });
  });
}
