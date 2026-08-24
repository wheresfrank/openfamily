import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:openfamily/models/member.dart';
import 'package:openfamily/widgets/member_avatar_bubble.dart';

const Member _driver = Member(
  id: 'diego',
  name: 'Diego Garcia',
  position: LatLng(37.782, -122.418),
  status: MemberStatus.normal,
  batteryPercent: 60,
  address: 'Driving',
  movement: MovementType.car,
  speedMph: 42,
);

const Member _speeding = Member(
  id: 'aki',
  name: 'Aki Tanaka',
  position: LatLng(37.79, -122.402),
  status: MemberStatus.normal,
  batteryPercent: 55,
  address: 'Driving',
  movement: MovementType.car,
  speedMph: 78,
);

const Member _still = Member(
  id: 'maria',
  name: 'Maria Garcia',
  position: LatLng(37.7749, -122.4194),
  status: MemberStatus.normal,
  batteryPercent: 92,
  address: 'Stationary',
);

Widget _host(Member member) {
  return MaterialApp(
    home: Scaffold(body: Center(child: MemberAvatarBubble(member: member))),
  );
}

void main() {
  testWidgets('driving speed hangs below the avatar as a caption', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_host(_driver));

    expect(find.text('42 mph'), findsOneWidget);
    // Initials stay visible — the speed is not a card covering the face.
    expect(find.text('DG'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('speeding caption uses the same number+unit treatment', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_host(_speeding));

    expect(find.text('78 mph'), findsOneWidget);
    expect(find.text('AT'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('still member has no speed caption', (WidgetTester tester) async {
    await tester.pumpWidget(_host(_still));

    expect(find.textContaining('mph'), findsNothing);
    expect(find.text('MG'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('marker grows when a speed caption is present', () {
    expect(
      MemberAvatarBubble.markerSizeFor(_still).height,
      MemberAvatarBubble.avatarBox,
    );
    expect(
      MemberAvatarBubble.markerSizeFor(_driver).height,
      MemberAvatarBubble.avatarBox +
          MemberAvatarBubble.speedGap +
          MemberAvatarBubble.speedCaptionH,
    );
  });
}
