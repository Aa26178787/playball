import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import '../api/api_service.dart';
import '../screens/game/game_detail_screen.dart';
import '../screens/player/player_detail_screen.dart';
import '../screens/team/team_detail_screen.dart';
import '../screens/stadium/stadium_screen.dart';

// @경기 5/20 KT LG  |  @경기 5월20일 KT LG
// @선수 강백호
// @팀 KT | @팀 두산 | @팀 KIA
// @구장 잠실
class MentionText extends StatelessWidget {
  final String text;
  final TextStyle? style;
  final Color mentionColor;

  const MentionText({
    super.key,
    required this.text,
    this.style,
    this.mentionColor = const Color(0xFF1A237E),
  });

  static final _pattern = RegExp(
    r'@경기[ \t]+\d{1,2}[/월]\d{1,2}일?[ \t]+\S+[ \t]+\S+'
    r'|@선수[ \t]+\S+'
    r'|@팀[ \t]+\S+'
    r'|@구장[ \t]+\S+',
    unicode: true,
  );

  // user input → home_team_code (from CLAUDE.md short_names)
  static const _nameToCode = {
    'KT': 'KT', 'LG': 'LG', 'SSG': 'SK', 'SK': 'SK', 'NC': 'NC',
    'OB': 'OB', 'HT': 'HT', 'LT': 'LT', 'SS': 'SS', 'HH': 'HH', 'WO': 'WO',
    '두산': 'OB', 'KIA': 'HT', '롯데': 'LT', '삼성': 'SS', '한화': 'HH', '키움': 'WO',
  };

  static const _teamByCode = {
    'KT': {'id': 1,  'name': 'KT 위즈',      'short_name': 'KT'},
    'HT': {'id': 2,  'name': 'KIA 타이거즈',  'short_name': 'HT'},
    'LT': {'id': 4,  'name': '롯데 자이언츠', 'short_name': 'LT'},
    'HH': {'id': 5,  'name': '한화 이글스',   'short_name': 'HH'},
    'NC': {'id': 6,  'name': 'NC 다이노스',   'short_name': 'NC'},
    'OB': {'id': 7,  'name': '두산 베어스',   'short_name': 'OB'},
    'WO': {'id': 8,  'name': '키움 히어로즈', 'short_name': 'WO'},
    'LG': {'id': 9,  'name': 'LG 트윈스',    'short_name': 'LG'},
    'SK': {'id': 10, 'name': 'SSG 랜더스',   'short_name': 'SK'},
    'SS': {'id': 11, 'name': '삼성 라이온즈', 'short_name': 'SS'},
  };

  @override
  Widget build(BuildContext context) {
    final base = style ?? DefaultTextStyle.of(context).style;
    final mentionStyle = base.copyWith(
      color: mentionColor,
      fontWeight: FontWeight.bold,
      decoration: TextDecoration.underline,
      decorationColor: mentionColor.withValues(alpha: 0.5),
    );

    final spans = <TextSpan>[];
    int lastEnd = 0;
    for (final m in _pattern.allMatches(text)) {
      if (m.start > lastEnd) {
        spans.add(TextSpan(text: text.substring(lastEnd, m.start), style: base));
      }
      final mention = m.group(0)!;
      spans.add(TextSpan(
        text: mention,
        style: mentionStyle,
        recognizer: TapGestureRecognizer()
          ..onTap = () => _handleTap(context, mention),
      ));
      lastEnd = m.end;
    }
    if (lastEnd < text.length) {
      spans.add(TextSpan(text: text.substring(lastEnd), style: base));
    }

    return RichText(text: TextSpan(children: spans));
  }

  void _handleTap(BuildContext context, String mention) {
    if (mention.startsWith('@경기')) {
      _navigateGame(context, mention);
    } else if (mention.startsWith('@선수')) {
      _navigatePlayer(context, mention);
    } else if (mention.startsWith('@팀')) {
      _navigateTeam(context, mention);
    } else if (mention.startsWith('@구장')) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => const StadiumScreen()));
    }
  }

  Future<void> _navigateGame(BuildContext context, String mention) async {
    final parts = mention.trim().split(RegExp(r'[ \t]+'));
    if (parts.length < 4) return;
    final datePart = parts[1];
    final rawTeam1 = parts[2].toUpperCase();
    final rawTeam2 = parts[3].toUpperCase();

    final slash = RegExp(r'^(\d{1,2})/(\d{1,2})$').firstMatch(datePart);
    final korean = RegExp(r'^(\d{1,2})월(\d{1,2})일?$').firstMatch(datePart);
    final match = slash ?? korean;
    if (match == null) return;

    final mm = match.group(1)!.padLeft(2, '0');
    final dd = match.group(2)!.padLeft(2, '0');
    final dateStr = '2026-$mm-$dd';

    final code1 = _nameToCode[rawTeam1] ?? rawTeam1;
    final code2 = _nameToCode[rawTeam2] ?? rawTeam2;

    try {
      final data = await ApiService.getGamesByDate(dateStr);
      final games = (data['games'] as List?) ?? [];
      for (final g in games) {
        final hc = (g['home_team_code'] as String? ?? '').toUpperCase();
        final ac = (g['away_team_code'] as String? ?? '').toUpperCase();
        if ((hc == code1 && ac == code2) || (hc == code2 && ac == code1)) {
          if (context.mounted) {
            Navigator.push(context, MaterialPageRoute(
              builder: (_) => GameDetailScreen(gameId: g['id'] as int),
            ));
          }
          return;
        }
      }
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$mm월$dd일 ${parts[2]} vs ${parts[3]} 경기를 찾을 수 없습니다')),
        );
      }
    } catch (_) {}
  }

  Future<void> _navigatePlayer(BuildContext context, String mention) async {
    final name = mention.replaceFirst(RegExp(r'^@선수[ \t]+'), '').trim();
    if (name.isEmpty) return;
    try {
      final data = await ApiService.search(name);
      final players = (data['players'] as List?) ?? [];
      if (players.isEmpty) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('$name 선수를 찾을 수 없습니다')),
          );
        }
        return;
      }
      if (players.length == 1) {
        if (context.mounted) {
          Navigator.push(context, MaterialPageRoute(
            builder: (_) => PlayerDetailScreen(playerId: players[0]['id'] as int),
          ));
        }
      } else {
        if (!context.mounted) return;
        final chosen = await showDialog<int>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('선수 선택'),
            content: SizedBox(
              width: 280,
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: players.length,
                itemBuilder: (ctx, i) {
                  final p = players[i];
                  return ListTile(
                    dense: true,
                    title: Text(p['name'] as String,
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text('${p['team'] ?? ''} · ${p['position'] ?? ''}',
                        style: const TextStyle(fontSize: 11)),
                    onTap: () => Navigator.pop(ctx, p['id'] as int),
                  );
                },
              ),
            ),
          ),
        );
        if (chosen != null && context.mounted) {
          Navigator.push(context, MaterialPageRoute(
            builder: (_) => PlayerDetailScreen(playerId: chosen),
          ));
        }
      }
    } catch (_) {}
  }

  void _navigateTeam(BuildContext context, String mention) {
    final raw = mention.replaceFirst(RegExp(r'^@팀[ \t]+'), '').trim().toUpperCase();
    final code = _nameToCode[raw] ?? _nameToCode[raw.toLowerCase()] ?? raw;
    final teamData = _teamByCode[code];
    if (teamData == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$raw 팀을 찾을 수 없습니다')),
      );
      return;
    }
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => TeamDetailScreen(team: Map<String, dynamic>.from(teamData)),
    ));
  }
}
