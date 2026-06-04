import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

// 일반 사이즈 (size < 200): Naver CDN f92_88 (기존 원본)
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

// overlay (size >= 200): 위키피디아 500px PNG — 고화질
// LG: en wiki 2017 logo (최신 트윈스 로고)
const Map<String, String> kTeamOverlayLogoUrls = {
  'LG': 'https://upload.wikimedia.org/wikipedia/en/thumb/a/a7/LG_Twins_2017_logo.svg/500px-LG_Twins_2017_logo.svg.png',
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
    var resolvedUrl = (logoUrl != null && logoUrl!.isNotEmpty)
        ? logoUrl!
        : kTeamLogoUrls[teamCode];

    // overlay (size >= 200): 위키피디아 고화질 URL swap (logoUrl override 없을 때만)
    if (size >= 200 && (logoUrl == null || logoUrl!.isEmpty)) {
      final overlayUrl = kTeamOverlayLogoUrls[teamCode];
      if (overlayUrl != null) resolvedUrl = overlayUrl;
    }
    // 고해상도 요청: size >= 80이면 Naver CDN f400_400로 upgrade
    else if (resolvedUrl != null && size >= 80) {
      resolvedUrl = resolvedUrl.replaceAll('type=f92_88', 'type=f400_400');
    }

    if (resolvedUrl != null) {
      // 큰 사이즈일수록 고품질 보간
      final fq = size >= 80 ? FilterQuality.high : FilterQuality.medium;
      final isOverlay = size >= 200;
      final img = CachedNetworkImage(
        imageUrl: resolvedUrl,
        width: size,
        height: size,
        fit: isOverlay ? BoxFit.contain : BoxFit.cover,
        filterQuality: fq,
        memCacheWidth: (size * 2).toInt().clamp(100, 800),
        memCacheHeight: (size * 2).toInt().clamp(100, 800),
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
