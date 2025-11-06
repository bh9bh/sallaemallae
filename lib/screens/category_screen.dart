// FILE: lib/screens/category_screen.dart
import 'package:flutter/material.dart';

class CategoryScreen extends StatelessWidget {
  const CategoryScreen({super.key});

  static const cats = [
    {"key": "living", "label": "생활/가전", "icon": Icons.home_filled},
    {"key": "kitchen", "label": "주방/요리", "icon": Icons.restaurant},
    {"key": "electronics", "label": "PC/전자기기", "icon": Icons.computer},
    {"key": "creator", "label": "촬영/크리에이터", "icon": Icons.videocam},
    {"key": "camping", "label": "캠핑/레저", "icon": Icons.park},
    {"key": "fashion", "label": "의류/패션 소품", "icon": Icons.checkroom},
    {"key": "hobby", "label": "취미/게임", "icon": Icons.sports_esports},
    {"key": "kids", "label": "유아/키즈", "icon": Icons.child_friendly},
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('카테고리'), centerTitle: true),
      body: GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: .9,
        ),
        itemCount: cats.length,
        itemBuilder: (_, i) {
          final k = cats[i]["key"] as String;
          final label = cats[i]["label"] as String;
          final icon = cats[i]["icon"] as IconData;
          return InkWell(
            onTap: () => Navigator.pop(context, {"key": k, "label": label}),
            borderRadius: BorderRadius.circular(12),
            child: Ink(
              decoration: BoxDecoration(
                color: const Color(0xFFF4F5F7),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 34),
                  const SizedBox(height: 8),
                  Text(
                    label,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
