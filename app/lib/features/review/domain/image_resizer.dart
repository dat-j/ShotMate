/// Resize ảnh trước khi upload cloud review (spec FR-S3-2, FR-S4-9): cạnh
/// dài ≤ 1568px, encode JPEG quality 85. Chạy trong Isolate riêng
/// (`Isolate.run` — Dart SDK hiện tại hỗ trợ, đơn giản hơn `compute()`) để
/// không block UI thread khi decode/resize ảnh 12MP (đo mục tiêu <4s trên
/// reference device, "UI không giật" — spec Non-Functional Requirements).
library;

import 'dart:isolate';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Cạnh dài tối đa sau resize (spec FR-S3-2/FR-S4-9).
const kMaxLongEdge = 1568;

/// JPEG quality khi encode lại (spec FR-S3-2/FR-S4-9).
const kJpegQuality = 85;

/// Resize [bytes] ảnh gốc (bất kỳ format `image` decode được) sao cho cạnh
/// dài ≤ [kMaxLongEdge], giữ tỉ lệ, encode JPEG chất lượng [kJpegQuality].
///
/// Nếu ảnh đã nhỏ hơn hoặc bằng ngưỡng, KHÔNG upscale — chỉ re-encode JPEG
/// q85 (giữ hành vi nhất quán về định dạng output, tránh gửi PNG/HEIC gốc
/// lên storage).
///
/// Throws [FormatException] nếu không decode được ảnh (input hỏng/không hỗ
/// trợ) — caller (review_controller) nên bắt và hiển thị lỗi rõ ràng thay vì
/// upload bytes gốc không kiểm soát định dạng. `package:image` có thể ném
/// lỗi khác (vd `RangeError`) khi input là dữ liệu rác/không hoàn chỉnh thay
/// vì trả `null` — gói lại thành `FormatException` để caller chỉ cần bắt 1
/// loại lỗi.
Uint8List resizeForUpload(Uint8List bytes) {
  img.Image? decoded;
  try {
    decoded = img.decodeImage(bytes);
  } catch (e) {
    throw FormatException('Không đọc được dữ liệu ảnh để resize: $e');
  }
  if (decoded == null) {
    throw const FormatException('Không đọc được dữ liệu ảnh để resize');
  }

  final longEdge =
      decoded.width > decoded.height ? decoded.width : decoded.height;

  final img.Image resized;
  if (longEdge <= kMaxLongEdge) {
    resized = decoded;
  } else if (decoded.width >= decoded.height) {
    resized = img.copyResize(
      decoded,
      width: kMaxLongEdge,
      interpolation: img.Interpolation.average,
    );
  } else {
    resized = img.copyResize(
      decoded,
      height: kMaxLongEdge,
      interpolation: img.Interpolation.average,
    );
  }

  return img.encodeJpg(resized, quality: kJpegQuality);
}

/// Chạy [resizeForUpload] trong isolate riêng (spec FR-S4-9: "chạy trong
/// isolate ... hiện resize đang thiếu/chạy thread chính"). `resizeForUpload`
/// là hàm top-level thuần (không capture state ngoài) nên an toàn truyền
/// trực tiếp cho `Isolate.run`.
Future<Uint8List> resizeForUploadInIsolate(Uint8List bytes) {
  return Isolate.run(() => resizeForUpload(bytes));
}
