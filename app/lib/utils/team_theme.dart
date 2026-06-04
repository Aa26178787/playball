import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

// 모든 사이즈에서 위키피디아 500px PNG 사용 — Naver f92_88 작은 사이즈 깨짐 fix
// 한 번 다운로드 후 모든 표시 사이즈 재사용 (memCacheWidth로 사이즈별 decode)
const Map<String, String> kTeamLogoUrls = {
  'LG': 'https://upload.wikimedia.org/wikipedia/commons/thumb/3/36/LG_Twins_insignia.svg/500px-LG_Twins_insignia.svg.png',
  'KT': 'https://upload.wikimedia.org/wikipedia/en/thumb/e/e5/KT_Wiz.svg/500px-KT_Wiz.svg.png',
  'SK': 'https://upload.wikimedia.org/wikipedia/en/thumb/8/86/SSG_Landers.png/500px-SSG_Landers.png',
  'NC': 'https://upload.wikimedia.org/wikipedia/en/thumb/5/54/NC_Dinos_Emblem.svg/500px-NC_Dinos_Emblem.svg.png',
  'OB': 'https://upload.wikimedia.org/wikipedia/en/thumb/9/98/Doosan_Bears.svg/500px-Doosan_Bears.svg.png',
  'HT': 'https://upload.wikimedia.org/wikipedia/en/thumb/e/e0/Kia_Tigers_2017_New_Team_Logo.png/500px-Kia_Tigers_2017_New_Team_Logo.png',
  'LT': 'https://upload.wikimedia.org/wikipedia/en/thumb/e/ef/Lotte_Giants_logo.svg/500px-Lotte_Giants_logo.svg.png',
  'SS': 'https://upload.wikimedia.org/wikipedia/en/thumb/0/0e/Samsung_Lions.svg/500px-Samsung_Lions.svg.png',
  'HH': 'https://upload.wikimedia.org/wikipedia/en/thumb/a/af/Hanwha_Eagles_2025.svg/500px-Hanwha_Eagles_2025.svg.png',
  'WO': 'https://upload.wikimedia.org/wikipedia/en/thumb/4/4f/Kiwoom_Heroes.png/500px-Kiwoom_Heroes.png',
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
      // overlay (size >= 200): 원형 clip X + contain (로고 비율 유지)
      final isOverlay = size >= 200;
      final img = CachedNetworkImage(
        imageUrl: resolvedUrl,
        width: size,
        height: size,
        fit: isOverlay ? BoxFit.contain : BoxFit.cover,
        filterQuality: FilterQuality.high,
        memCacheWidth: (size * 2).toInt().clamp(80, 800),
        memCacheHeight: (size * 2).toInt().clamp(80, 800),
        fadeInDuration: Duration.zero,
        fadeOutDuration: Duration.zero,
        errorWidget: (ctx, url, err) => _avatar(color, abbr),
        placeholder: (ctx, url) => _avatar(color, abbr),
      );
      return isOverlay ? img : ClipOval(child: img);
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
