// FILE: lib/screens/add_product_screen.dart
import 'dart:io' show File;
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../services/api_service.dart';

class AddProductScreen extends StatefulWidget {
  const AddProductScreen({super.key});

  @override
  State<AddProductScreen> createState() => _AddProductScreenState();
}

class _AddProductScreenState extends State<AddProductScreen> {
  final _formKey = GlobalKey<FormState>();

  // 입력 컨트롤러
  final _title = TextEditingController();
  final _desc = TextEditingController();
  final _category = TextEditingController(); // 선택 바가 값 채움
  final _region = TextEditingController();   // 선택 바가 값 채움
  final _dailyPrice = TextEditingController();
  final _deposit = TextEditingController();
  final _imageUrl = TextEditingController();

  // 상태
  bool _loading = false;
  bool _useFile = true; // 파일 업로드 vs URL 입력

  /// 여러 장 로컬 이미지 선택 경로
  final List<String> _pickedPaths = [];

  // 피그마용 토글(현재 API 전송은 하지 않음)
  bool _isRentable = true;
  bool _isPurchasable = true;

  final _api = ApiService.instance;

  // ---------- 카테고리/지역 데이터 & 상태 ----------
  static const List<Map<String, dynamic>> kCategories = [
    {"key": "living", "label": "생활/가전", "icon": Icons.home_filled},
    {"key": "kitchen", "label": "주방/요리", "icon": Icons.restaurant},
    {"key": "electronics", "label": "PC/전자기기", "icon": Icons.computer},
    {"key": "creator", "label": "촬영/크리에이터", "icon": Icons.videocam},
    {"key": "camping", "label": "캠핑/레저", "icon": Icons.park},
    {"key": "fashion", "label": "의류/패션 소품", "icon": Icons.checkroom},
    {"key": "hobby", "label": "취미/게임", "icon": Icons.sports_esports},
    {"key": "kids", "label": "유아/키즈", "icon": Icons.child_friendly},
  ];
  int _selectedCatIndex = -1;

  static const Map<String, List<String>> kRegion = {
    '서울': [
      '강남구','강동구','강북구','강서구','관악구','광진구','구로구','금천구',
      '노원구','도봉구','동대문구','동작구','마포구','서대문구','서초구','성동구',
      '성북구','송파구','양천구','영등포구','용산구','은평구','종로구','중구','중랑구',
    ],
    '경기': [
      '수원시','성남시','용인시','고양시','안양시','부천시','화성시','광명시',
      '남양주시','평택시','의정부시','파주시','시흥시','김포시','광주시','군포시',
    ],
    '인천': ['중구','동구','미추홀구','연수구','남동구','부평구','계양구','서구'],
    '부산': ['해운대구','수영구','연제구','남구','동래구','부산진구','사하구','사상구'],
  };
  late final List<String> _sidoList = kRegion.keys.toList();
  int _selectedSidoIndex = -1;
  int _selectedGuIndex = -1;

  List<String> get _guList {
    if (_selectedSidoIndex < 0) return const [];
    final sido = _sidoList[_selectedSidoIndex];
    return kRegion[sido] ?? const [];
  }

  // 가로 스크롤 컨트롤러(부드러운 칩 바)
  final ScrollController _catCtrl = ScrollController();
  final ScrollController _sidoCtrl = ScrollController();
  final ScrollController _guCtrl = ScrollController();

  @override
  void dispose() {
    _title.dispose();
    _desc.dispose();
    _category.dispose();
    _region.dispose();
    _dailyPrice.dispose();
    _deposit.dispose();
    _imageUrl.dispose();

    _catCtrl.dispose();
    _sidoCtrl.dispose();
    _guCtrl.dispose();
    super.dispose();
  }

  // 숫자 파서 (콤마/공백 허용)
  double? _parseNumber(String raw) {
    final t = raw.replaceAll(',', '').trim();
    if (t.isEmpty) return 0.0;
    return double.tryParse(t);
  }

  /// 여러 장 선택 (append=true면 추가, false면 갈아끼움)
  Future<void> _pickImageFiles({required bool append}) async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: true,
      withData: false,
    );
    if (res == null || res.files.isEmpty) return;

    final newPaths = res.files
        .map((f) => f.path)
        .whereType<String>()
        .where((p) => p.isNotEmpty)
        .toList();

    setState(() {
      if (append) {
        for (final p in newPaths) {
          if (!_pickedPaths.contains(p)) _pickedPaths.add(p);
        }
      } else {
        _pickedPaths
          ..clear()
          ..addAll(newPaths);
      }
    });
  }

  void _removePickedAt(int index) {
    setState(() {
      _pickedPaths.removeAt(index);
    });
  }

  /// 대표(커버) 사진으로 지정: 선택된 이미지를 맨 앞으로 이동
  void _makeCover(int index) {
    if (index <= 0 || index >= _pickedPaths.length) return;
    final chosen = _pickedPaths.removeAt(index);
    _pickedPaths.insert(0, chosen);
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('대표 사진을 변경했습니다.')),
    );
  }

  // ---------- 선택 핸들러 ----------
  void _selectCategory(int index) {
    setState(() {
      _selectedCatIndex = index;
      final key = kCategories[index]['key'] as String;
      _category.text = key; // 서버에는 key 전송
    });
  }

  void _selectSido(int index) {
    setState(() {
      _selectedSidoIndex = index;
      _selectedGuIndex = -1; // 시/도 바꾸면 구/군 초기화
      _region.clear();
    });
  }

  void _selectGu(int index) {
    setState(() {
      _selectedGuIndex = index;
      if (_selectedSidoIndex >= 0 && _selectedGuIndex >= 0) {
        final sido = _sidoList[_selectedSidoIndex];
        final gu = _guList[_selectedGuIndex];
        _region.text = '$sido $gu';
      }
    });
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;

    // 카테고리/지역 필수 체크
    if (_category.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('카테고리를 선택해주세요.')),
      );
      return;
    }
    if (_region.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('지역을 선택해주세요.')),
      );
      return;
    }

    final dPrice = _parseNumber(_dailyPrice.text);
    final depo = _parseNumber(_deposit.text);
    if (dPrice == null || dPrice <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('일일 대여료를 올바르게 입력해주세요.')),
      );
      return;
    }
    if (depo == null || depo < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('보증금을 올바르게 입력해주세요.')),
      );
      return;
    }

    setState(() => _loading = true);
    bool ok = false;

    try {
      if (_useFile) {
        if (_pickedPaths.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('이미지 파일을 한 장 이상 선택해주세요.')),
          );
          setState(() => _loading = false);
          return;
        }

        ok = await _api.createProductWithImage(
          title: _title.text.trim(),
          description: _desc.text.trim().isEmpty ? null : _desc.text.trim(),
          category: _category.text.trim().isEmpty ? null : _category.text.trim(),
          region: _region.text.trim().isEmpty ? null : _region.text.trim(),
          dailyPrice: dPrice,
          securityDeposit: depo, // ← ApiService와 매칭
          filePath: _pickedPaths.first, // 대표 1장
        );

        if (_pickedPaths.length > 1 && ok) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('현재는 대표 1장만 업로드됩니다. (멀티 업로드는 서버 지원 후 적용)'),
            ),
          );
        }
      } else {
        ok = await _api.createProduct(
          title: _title.text.trim(),
          description: _desc.text.trim().isEmpty ? null : _desc.text.trim(),
          imageUrl: _imageUrl.text.trim().isEmpty ? null : _imageUrl.text.trim(),
          category: _category.text.trim().isEmpty ? null : _category.text.trim(),
          region: _region.text.trim().isEmpty ? null : _region.text.trim(),
          dailyPrice: dPrice,
          securityDeposit: depo, // ← ApiService와 매칭
        );
      }
    } finally {
      if (!mounted) return;
      setState(() => _loading = false);
    }

    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('상품이 등록되었습니다.')),
      );
      Navigator.pop(context, true); // Home에서 true 받으면 목록 갱신
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('상품 등록에 실패했습니다. 잠시 후 다시 시도해주세요.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // 라이트 톤
    const bg = Color(0xFFF5F6F8);
    const fill = Color(0xFFF1F2F5);
    const textColor = Colors.black87;
    const hintColor = Colors.black45;
    const btn = Color(0xFF3E4E86);

    final base = Theme.of(context);
    final theme = base.copyWith(
      useMaterial3: true,
      scaffoldBackgroundColor: bg,
      textTheme: base.textTheme.apply(
        bodyColor: textColor,
        displayColor: textColor,
      ),
      colorScheme: ColorScheme.fromSeed(
        seedColor: btn,
        brightness: Brightness.light,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: fill,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        hintStyle: const TextStyle(color: hintColor),
        labelStyle: const TextStyle(color: textColor),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Colors.black26),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: btn,
          minimumSize: const Size.fromHeight(48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        side: const BorderSide(color: Colors.black38),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),
      switchTheme: const SwitchThemeData(
        thumbColor: MaterialStatePropertyAll(btn),
        trackColor: MaterialStatePropertyAll(Color(0xFFBFC6E6)),
      ),
    );

    final cs = theme.colorScheme;

    return Theme(
      data: theme,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('상품 등록'),
          centerTitle: true,
          backgroundColor: bg,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              Card(
                elevation: 0,
                color: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      children: [
                        const _FieldLabel('상품명'),
                        TextFormField(
                          controller: _title,
                          textInputAction: TextInputAction.next,
                          validator: (v) =>
                              (v ?? '').trim().isEmpty ? '상품명을 입력해주세요.' : null,
                        ),
                        const SizedBox(height: 14),

                        const _FieldLabel('설명'),
                        TextFormField(
                          controller: _desc,
                          textInputAction: TextInputAction.newline,
                          maxLines: 3,
                          minLines: 3,
                          decoration: const InputDecoration(hintText: '간단한 설명을 입력하세요'),
                        ),
                        const SizedBox(height: 16),

                        // ===== 카테고리 선택 바 =====
                        Row(
                          children: const [
                            _FieldLabel('카테고리'),
                          ],
                        ),
                        const SizedBox(height: 6),
                        SizedBox(
                          height: 44,
                          child: ListView.separated(
                            controller: _catCtrl,
                            scrollDirection: Axis.horizontal,
                            itemCount: kCategories.length,
                            separatorBuilder: (_, __) => const SizedBox(width: 8),
                            itemBuilder: (_, i) {
                              final m = kCategories[i];
                              final selected = i == _selectedCatIndex;
                              return _ChipPill(
                                label: m['label'] as String,
                                icon: m['icon'] as IconData,
                                selected: selected,
                                onTap: () => _selectCategory(i),
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 8),
                        _InfoBadge(
                          text: _selectedCatIndex < 0
                              ? '예) 가전제품'
                              : '선택됨: ${kCategories[_selectedCatIndex]['label']}',
                          color: _selectedCatIndex < 0 ? cs.surface : cs.primaryContainer,
                        ),
                        const SizedBox(height: 16),

                        // ===== 지역 선택 바 (시/도 → 구/군) =====
                        Row(
                          children: const [
                            _FieldLabel('지역'),
                          ],
                        ),
                        const SizedBox(height: 6),
                        SizedBox(
                          height: 40,
                          child: ListView.separated(
                            controller: _sidoCtrl,
                            scrollDirection: Axis.horizontal,
                            itemCount: _sidoList.length,
                            separatorBuilder: (_, __) => const SizedBox(width: 8),
                            itemBuilder: (_, i) {
                              final s = _sidoList[i];
                              return _ChipPill(
                                label: s,
                                selected: i == _selectedSidoIndex,
                                onTap: () => _selectSido(i),
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 8),
                        if (_guList.isNotEmpty)
                          SizedBox(
                            height: 36,
                            child: ListView.separated(
                              controller: _guCtrl,
                              scrollDirection: Axis.horizontal,
                              itemCount: _guList.length,
                              separatorBuilder: (_, __) => const SizedBox(width: 8),
                              itemBuilder: (_, i) {
                                final g = _guList[i];
                                return _ChipPill(
                                  label: g,
                                  compact: true,
                                  selected: i == _selectedGuIndex,
                                  onTap: () => _selectGu(i),
                                );
                              },
                            ),
                          ),
                        const SizedBox(height: 8),
                        _InfoBadge(
                          text: _region.text.isEmpty
                              ? '예) 서울 강서구'
                              : '선택됨: ${_region.text}',
                          color: _region.text.isEmpty ? cs.surface : cs.primaryContainer,
                        ),

                        const SizedBox(height: 16),

                        // ===== 금액 =====
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const _FieldLabel('일일 대여료(원)'),
                                  TextFormField(
                                    controller: _dailyPrice,
                                    keyboardType: TextInputType.number,
                                    textInputAction: TextInputAction.next,
                                    validator: (v) =>
                                        (_parseNumber(v ?? '') ?? 0) <= 0 ? '금액을 입력하세요' : null,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const _FieldLabel('보증금(원)'),
                                  TextFormField(
                                    controller: _deposit,
                                    keyboardType: TextInputType.number,
                                    textInputAction: TextInputAction.done,
                                    validator: (v) =>
                                        (_parseNumber(v ?? '') ?? -1) < 0 ? '0 이상 입력' : null,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // 판매/대여 가능 스위치 (UI만, 서버 전송 X)
                        Row(
                          children: [
                            Expanded(
                              child: SwitchListTile(
                                value: _isRentable,
                                onChanged: (v) => setState(() => _isRentable = v),
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                title: const Text('대여 가능'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: SwitchListTile(
                                value: _isPurchasable,
                                onChanged: (v) => setState(() => _isPurchasable = v),
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                title: const Text('구매 가능'),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),

                        // ===== 이미지 업로드 섹션 (여러 장 + 대표 지정) =====
                        Row(
                          children: [
                            const Icon(Icons.image_outlined),
                            const SizedBox(width: 8),
                            const Text('상품 이미지', style: TextStyle(fontWeight: FontWeight.w700)),
                            const Spacer(),
                            SegmentedButton<bool>(
                              segments: const [
                                ButtonSegment<bool>(value: true, label: Text('파일')),
                                ButtonSegment<bool>(value: false, label: Text('URL')),
                              ],
                              selected: {_useFile},
                              onSelectionChanged: (s) => setState(() => _useFile = s.first),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),

                        if (_useFile) ...[
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: _loading ? null : () => _pickImageFiles(append: true),
                                  icon: const Icon(Icons.add_photo_alternate_outlined),
                                  label: Text(
                                    _pickedPaths.isEmpty ? '이미지 선택(여러 장)' : '이미지 추가 선택',
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              OutlinedButton.icon(
                                onPressed: _loading ? null : () => _pickImageFiles(append: false),
                                icon: const Icon(Icons.refresh),
                                label: const Text('전체 다시 선택'),
                              ),
                              const SizedBox(width: 8),
                              if (_pickedPaths.isNotEmpty)
                                IconButton(
                                  tooltip: '목록 비우기',
                                  onPressed: _loading
                                      ? null
                                      : () => setState(() => _pickedPaths.clear()),
                                  icon: const Icon(Icons.clear_all),
                                ),
                            ],
                          ),
                          const SizedBox(height: 10),

                          if (_pickedPaths.isEmpty)
                            Container(
                              height: 140,
                              decoration: BoxDecoration(
                                color: const Color(0xFFF1F2F5),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.black12),
                              ),
                              alignment: Alignment.center,
                              child: const Text('선택된 이미지가 없습니다.'),
                            )
                          else
                            GridView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: _pickedPaths.length,
                              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 3,
                                mainAxisSpacing: 8,
                                crossAxisSpacing: 8,
                                childAspectRatio: 1,
                              ),
                              itemBuilder: (context, index) {
                                final p = _pickedPaths[index];
                                final isCover = index == 0;
                                return Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: Image.file(File(p), fit: BoxFit.cover),
                                    ),
                                    // 삭제 버튼 (우상단)
                                    Positioned(
                                      right: 4, top: 4,
                                      child: InkWell(
                                        onTap: _loading ? null : () => _removePickedAt(index),
                                        child: Container(
                                          padding: const EdgeInsets.all(4),
                                          decoration: BoxDecoration(
                                            color: Colors.black54,
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: const Icon(Icons.close, size: 16, color: Colors.white),
                                        ),
                                      ),
                                    ),
                                    // 대표/대표로 (좌상단)
                                    Positioned(
                                      left: 4, top: 4,
                                      child: InkWell(
                                        onTap: _loading ? null : () { if (!isCover) _makeCover(index); },
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: Colors.black54,
                                            borderRadius: BorderRadius.circular(6),
                                            border: Border.all(
                                              color: isCover ? Colors.yellowAccent : Colors.transparent,
                                              width: 1,
                                            ),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(isCover ? Icons.star : Icons.star_border_outlined,
                                                  size: 14, color: Colors.white),
                                              const SizedBox(width: 4),
                                              Text(isCover ? '대표' : '대표로',
                                                  style: const TextStyle(
                                                    color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold,
                                                  )),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),
                        ] else ...[
                          TextFormField(
                            controller: _imageUrl,
                            decoration: const InputDecoration(
                              hintText: 'https://example.com/image.jpg',
                              labelText: '이미지 URL(선택)',
                            ),
                            keyboardType: TextInputType.url,
                            onChanged: (_) => setState(() {}),
                          ),
                          const SizedBox(height: 10),
                          if (_imageUrl.text.trim().isNotEmpty)
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.network(
                                _imageUrl.text.trim(),
                                height: 180,
                                width: double.infinity,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Container(
                                  height: 140,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF1F2F5),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: Colors.black12),
                                  ),
                                  child: const Text('이미지를 불러오지 못했습니다.'),
                                ),
                              ),
                            ),
                        ],

                        const SizedBox(height: 18),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: _loading ? null : _submit,
                            icon: _loading
                                ? const SizedBox(
                                    width: 18, height: 18,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Icon(Icons.check_circle_outline),
                            label: Text(_loading ? '등록 중...' : '상품 등록'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  final String text;
  const _FieldLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 6),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.black87,
          fontSize: 13,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _InfoBadge extends StatelessWidget {
  final String text;
  final Color? color;
  const _InfoBadge({required this.text, this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color ?? Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.black12),
      ),
      alignment: Alignment.centerLeft,
      child: Text(text, style: const TextStyle(fontSize: 12)),
    );
  }
}

class _ChipPill extends StatelessWidget {
  final String label;
  final IconData? icon;
  final bool selected;
  final bool compact;
  final VoidCallback? onTap;

  const _ChipPill({
    super.key,
    required this.label,
    this.icon,
    this.selected = false,
    this.compact = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bg = selected ? const Color(0xFF111827) : const Color(0xFFEDEEF1);
    final fg = selected ? Colors.white : Colors.black87;
    final border = selected ? Colors.black : Colors.black12;

    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Container(
        height: compact ? 34 : 40,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: border),
        ),
        alignment: Alignment.center,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 16, color: fg),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: compact ? 12 : 13,
                fontWeight: FontWeight.w700,
                color: fg,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
