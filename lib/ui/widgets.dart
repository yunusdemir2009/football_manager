import 'package:flutter/material.dart';

/// Takim adindan sabit bir renk uretir (logo olmadan ayirt edilebilirlik icin).
Color teamColor(String name) {
  var h = 0;
  for (final c in name.codeUnits) {
    h = (h * 31 + c) & 0x7fffffff;
  }
  return HSLColor.fromAHSL(1, (h % 360).toDouble(), 0.55, 0.40).toColor();
}

String initials(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();
  if (parts.isEmpty) return '?';
  if (parts.length == 1) {
    final w = parts.first;
    return (w.length >= 2 ? w.substring(0, 2) : w).toUpperCase();
  }
  return (parts[0][0] + parts[1][0]).toUpperCase();
}

class TeamBadge extends StatelessWidget {
  final String name;
  final double size;
  const TeamBadge({super.key, required this.name, this.size = 32});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: teamColor(name),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white24, width: 1.5),
      ),
      child: Text(
        initials(name),
        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: size * 0.38),
      ),
    );
  }
}

/// Son maclarin W/D/L noktalari.
class FormDots extends StatelessWidget {
  final List<String> form;
  const FormDots({super.key, required this.form});

  @override
  Widget build(BuildContext context) {
    Color c(String r) => r == 'W' ? Colors.green : r == 'D' ? Colors.amber : Colors.redAccent;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      for (final r in form)
        Container(
          margin: const EdgeInsets.only(left: 2),
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: c(r), shape: BoxShape.circle),
        ),
    ]);
  }
}

/// Iki taraf icin karsilastirma cubugu.
class StatBar extends StatelessWidget {
  final String label;
  final num home, away;
  final String suffix;
  const StatBar({super.key, required this.label, required this.home, required this.away, this.suffix = ''});

  @override
  Widget build(BuildContext context) {
    final total = (home + away) == 0 ? 1 : (home + away);
    final hf = (home / total * 100).round().clamp(1, 99).toInt();
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Column(children: [
        Row(children: [
          SizedBox(width: 36, child: Text('$home$suffix', style: const TextStyle(fontWeight: FontWeight.bold))),
          Expanded(child: Text(label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12))),
          SizedBox(
              width: 36,
              child: Text('$away$suffix', textAlign: TextAlign.end, style: const TextStyle(fontWeight: FontWeight.bold))),
        ]),
        const SizedBox(height: 2),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: Row(children: [
            Expanded(flex: hf, child: Container(height: 5, color: scheme.primary)),
            const SizedBox(width: 2),
            Expanded(flex: 100 - hf, child: Container(height: 5, color: scheme.tertiary)),
          ]),
        ),
      ]),
    );
  }
}
