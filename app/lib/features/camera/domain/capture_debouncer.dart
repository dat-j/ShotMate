/// Debounce chống double-capture (spec-sprint-1 EC-7: "bấm chụp liên tiếp
/// nhanh (< 500ms) → nút disable; không double record trong Drift").
///
/// Pure, không phụ thuộc Flutter — chỉ theo dõi trạng thái "đang xử lý 1 lần
/// chụp". Widget gọi [tryStart] trước khi bắt đầu capture; nếu trả về false
/// nghĩa là đã có 1 lần chụp đang xử lý, bỏ qua tap này. Khi xong (thành
/// công hay lỗi) widget PHẢI gọi [finish].
library;

class CaptureDebouncer {
  bool _inProgress = false;

  bool get inProgress => _inProgress;

  /// Trả true nếu bắt đầu được (chuyển sang inProgress); false nếu đã có 1
  /// lần chụp đang chạy — caller phải bỏ qua tap hiện tại.
  bool tryStart() {
    if (_inProgress) return false;
    _inProgress = true;
    return true;
  }

  /// Đánh dấu lần chụp hiện tại đã xong — cho phép lần chụp tiếp theo.
  void finish() {
    _inProgress = false;
  }
}
