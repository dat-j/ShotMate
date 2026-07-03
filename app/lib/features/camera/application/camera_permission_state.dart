/// Trạng thái quyền camera cho UI (spec-sprint-1 FR-S1-1, EC-3).
library;

enum CameraPermissionStatus {
  /// Chưa xác định — đang chờ check/xin quyền lần đầu.
  unknown,

  /// User đã cấp quyền — có thể init CameraController.
  granted,

  /// User từ chối (chưa "don't ask again") — có thể xin lại.
  denied,

  /// User từ chối vĩnh viễn (kể cả "don't ask again") — chỉ còn cách mở
  /// Settings (EC-3: "Không crash, không loop xin quyền").
  permanentlyDenied,
}
