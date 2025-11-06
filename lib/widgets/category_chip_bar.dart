import 'package:flutter/material.dart';

class CategoryChipBar extends StatefulWidget {
  const CategoryChipBar({super.key, required this.onChanged});
  final ValueChanged<int> onChanged;

  @override
  State<CategoryChipBar> createState() => _CategoryChipBarState();
}

class _CategoryChipBarState extends State<CategoryChipBar> {
  final cats = [
    '전체상품','주방/생활','의류/잡화','PC/디지털','가전제품','취미/이용',
    '캠핑/스포츠','차량/모빌리티','기타','생활/무형용품'
  ];
  int selected = 0;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: cats.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final isSel = i == selected;
          return ChoiceChip(
            label: Text(cats[i]),
            selected: isSel,
            onSelected: (_) {
              setState(() => selected = i);
              widget.onChanged(i);
            },
          );
        },
      ),
    );
  }
}
