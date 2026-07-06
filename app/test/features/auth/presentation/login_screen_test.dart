import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shotmate_app/features/auth/data/auth_repository.dart';
import 'package:shotmate_app/features/auth/presentation/login_screen.dart';

class _MockAuthRepository extends Mock implements AuthRepository {}

void main() {
  late _MockAuthRepository mockAuthRepository;

  setUp(() {
    mockAuthRepository = _MockAuthRepository();
  });

  Future<void> pumpLoginScreen(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(mockAuthRepository),
        ],
        child: const MaterialApp(home: LoginScreen()),
      ),
    );
  }

  testWidgets('gửi magic link thành công hiển thị màn hình "kiểm tra hộp thư"',
      (tester) async {
    when(() => mockAuthRepository.requestMagicLink(any()))
        .thenAnswer((_) async {});

    await pumpLoginScreen(tester);

    await tester.enterText(find.byType(TextField), 'user@example.com');
    await tester.tap(find.text('Gửi liên kết đăng nhập'));
    await tester.pump(); // rebuild loading state
    await tester.pumpAndSettle();

    expect(find.textContaining('Đã gửi liên kết đăng nhập tới'), findsOneWidget);
    verify(() => mockAuthRepository.requestMagicLink('user@example.com')).called(1);
  });

  testWidgets('email không hợp lệ hiển thị lỗi, không gọi repository',
      (tester) async {
    await pumpLoginScreen(tester);

    await tester.enterText(find.byType(TextField), 'khong-hop-le');
    await tester.tap(find.text('Gửi liên kết đăng nhập'));
    await tester.pump();

    expect(find.text('Email không hợp lệ'), findsOneWidget);
    verifyNever(() => mockAuthRepository.requestMagicLink(any()));
  });

  testWidgets('lỗi mạng hiển thị thông báo thử lại', (tester) async {
    when(() => mockAuthRepository.requestMagicLink(any()))
        .thenThrow(Exception('network error'));

    await pumpLoginScreen(tester);

    await tester.enterText(find.byType(TextField), 'user@example.com');
    await tester.tap(find.text('Gửi liên kết đăng nhập'));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(
      find.text('Không gửi được liên kết — kiểm tra kết nối mạng và thử lại'),
      findsOneWidget,
    );
  });
}
