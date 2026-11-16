import 'package:can_werkbank/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Startseite öffnet die Simulation', (tester) async {
    await tester.pumpWidget(const CanWerkbankApp());
    expect(find.text('CAN-Werkbank'), findsOneWidget);
    expect(find.text('CAN-Leser suchen'), findsOneWidget);

    await tester.tap(find.text('Simulation starten'));
    await tester.pumpAndSettle(const Duration(milliseconds: 300));
    expect(find.text('Simulation'), findsOneWidget);
    expect(find.text('0B6'), findsOneWidget);

    // Zurück: Die Simulation wird beendet (sonst liefe ihr Timer weiter).
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('CAN-Leser suchen'), findsOneWidget);
  });
}
