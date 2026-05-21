import 'package:flutter/material.dart';

const Map<String, String> kTeamLogoUrls = {
  'LG': 'https://sports-phinf.pstatic.net/team/kbo/default/LG.png?type=f92_88',
  'KT': 'https://sports-phinf.pstatic.net/team/kbo/default/KT.png?type=f92_88',
  'SK': 'https://sports-phinf.pstatic.net/team/kbo/default/SK.png?type=f92_88',
  'NC': 'https://sports-phinf.pstatic.net/team/kbo/default/NC.png?type=f92_88',
  'OB': 'https://sports-phinf.pstatic.net/team/kbo/default/OB.png?type=f92_88',
  'HT': 'https://sports-phinf.pstatic.net/team/kbo/default/HT.png?type=f92_88',
  'LT': 'https://sports-phinf.pstatic.net/team/kbo/default/LT.png?type=f92_88',
  'SS': 'https://sports-phinf.pstatic.net/team/kbo/default/SS.png?type=f92_88',
  'HH': 'https://sports-phinf.pstatic.net/team/kbo/default/HH.png?type=f92_88',
  'WO': 'https://sports-phinf.pstatic.net/team/kbo/default/WO.png?type=f92_88',
};

const Map<String, Color> kTeamColors = {
  'LG': Color(0xFFC30452),
  'KT': Color(0xFF1A1A1A),
  'SK': Color(0xFFCE0E2D),  // SSG
  'NC': Color(0xFF071D49),
  'OB': Color(0xFF131E3E),  // 두산
  'HT': Color(0xFFEA0029),  // KIA
  'LT': Color(0xFFE4003C),  // 롯데
  'SS': Color(0xFF1B4BAB),  // 삼성
  'HH': Color(0xFFFF6600),  // 한화
  'WO': Color(0xFF820024),  // 키움
};

const Map<String, String> kTeamDisplayNames = {
  'LG': 'LG',
  'KT': 'KT',
  'SK': 'SSG',
  'NC': 'NC',
  'OB': '두산',
  'HT': 'KIA',
  'LT': '롯데',
  'SS': '삼성',
  'HH': '한화',
  'WO': '키움',
};

Color teamColor(String? code) =>
    kTeamColors[code] ?? const Color(0xFF607D8B);

String teamDisplayName(String? code) =>
    kTeamDisplayNames[code] ?? (code ?? '');

class TeamLogo extends StatelessWidget {
  final String teamCode;
  final double size;
  final String? logoUrl;

  const TeamLogo({
    required this.teamCode,
    this.size = 36,
    this.logoUrl,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final color = teamColor(teamCode);
    final abbr = teamDisplayName(teamCode);
    final resolvedUrl = (logoUrl != null && logoUrl!.isNotEmpty)
        ? logoUrl!
        : kTeamLogoUrls[teamCode];

    if (resolvedUrl != null) {
      return ClipOval(
        child: Image.network(
          resolvedUrl,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (ctx, err, trace) => _avatar(color, abbr),
        ),
      );
    }
    return _avatar(color, abbr);
  }

  Widget _avatar(Color color, String text) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
      alignment: Alignment.center,
      child: Text(
        text,
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: size * 0.28,
        ),
      ),
    );
  }
}
