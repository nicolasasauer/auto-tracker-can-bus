import 'package:can_link/can_link.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Simulation liefert Übersichten und Status', () async {
    final c = DemoConnection(interval: const Duration(hours: 1));
    final view = BusView();
    final sub = c.monitor.listen(view.add);
    final status = c.status.first;
    final diagnostics = c.diagnostics.first;
    c.tick(200);
    c.tick(200);
    expect((await status).state, BusState.ok);
    final d = await diagnostics;
    expect(d.loadNowPct, greaterThan(0));
    expect(d.ringCapacity, 512);
    await Future<void>.delayed(Duration.zero);
    expect(view.ids.map((s) => s.label), containsAll(['0B6', '128', '7E8']));
    expect(view[0x7E8]!.obd, isA<ObdResponse>());
    expect(view.lostMessages, 0);
    await sub.cancel();
    await c.close();
  });

  test('Simulation merkt sich Befehle', () async {
    final c = DemoConnection(interval: const Duration(hours: 1));
    await c.send(CanLinkCommands.resetStats());
    expect(c.sentCommands.single, [0x10]);
    await c.close();
  });
}
