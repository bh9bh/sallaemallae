// FILE: lib/screens/register_screen.dart
import 'package:flutter/material.dart';
import '../services/api_service.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});
  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _pw = TextEditingController();
  final _pw2 = TextEditingController();

  bool _loading = false;
  bool _obscure1 = true;
  bool _obscure2 = true;
  String? _error;

  final _api = ApiService.instance;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _pw.dispose();
    _pw2.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    final ok = await _api.register(
      _email.text.trim(),
      _pw.text,
      _name.text.trim(),
    );

    if (!mounted) return;
    setState(() => _loading = false);

    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('회원가입이 완료되었습니다. 로그인해주세요.')),
      );
      Navigator.pushNamedAndRemoveUntil(context, '/login', (r) => false);
    } else {
      setState(() => _error = '회원가입에 실패했습니다. 잠시 후 다시 시도해주세요.');
    }
  }

  @override
  Widget build(BuildContext context) {
    // 고정 스타일(반응형 비율 조절 없음)
    const bg = Color(0xFFF5F6F8);
    const fill = Color(0xFFF1F2F5);
    const btn = Color(0xFF3E4E86);
    const textColor = Colors.black87;
    const hintColor = Colors.black45;

    final base = Theme.of(context);
    final theme = base.copyWith(
      useMaterial3: true,
      scaffoldBackgroundColor: bg,
      textTheme: base.textTheme.apply(
        bodyColor: textColor,
        displayColor: textColor,
      ),
      colorScheme: ColorScheme.fromSeed(
          seedColor: btn, brightness: Brightness.light),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: fill,
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        hintStyle: const TextStyle(color: hintColor),
        labelStyle: const TextStyle(color: textColor),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Colors.black26),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Colors.black26),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Colors.black54, width: 1.4),
        ),
      ),
      textSelectionTheme: const TextSelectionThemeData(
        cursorColor: textColor,
        selectionColor: Color(0xFFCAD3F7),
        selectionHandleColor: textColor,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: btn,
          minimumSize: const Size.fromHeight(48),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8)),
        ),
      ),
    );

    return Theme(
      data: theme,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('회원가입'),
          centerTitle: true,
          backgroundColor: bg,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
        ),
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
              child: Card(
                elevation: 0,
                color: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(height: 6),
                        const Text(
                          '계정 만들기',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                            color: textColor,
                            letterSpacing: -0.2,
                          ),
                        ),
                        const SizedBox(height: 20),

                        const _FieldLabel('이름'),
                        TextFormField(
                          controller: _name,
                          textInputAction: TextInputAction.next,
                          style: const TextStyle(color: textColor),
                          cursorColor: textColor,
                          validator: (v) => (v ?? '').trim().isEmpty
                              ? '이름을 입력해주세요.'
                              : null,
                        ),
                        const SizedBox(height: 14),

                        const _FieldLabel('이메일'),
                        TextFormField(
                          controller: _email,
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.next,
                          style: const TextStyle(color: textColor),
                          cursorColor: textColor,
                          decoration: const InputDecoration(
                              hintText: 'example@domain.com'),
                          validator: (v) {
                            final t = (v ?? '').trim();
                            if (t.isEmpty) return '이메일을 입력해주세요.';
                            if (!t.contains('@') || !t.contains('.')) {
                              return '올바른 이메일 형식이 아닙니다.';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 14),

                        const _FieldLabel('비밀번호'),
                        TextFormField(
                          controller: _pw,
                          obscureText: _obscure1,
                          textInputAction: TextInputAction.next,
                          style: const TextStyle(color: textColor),
                          cursorColor: textColor,
                          validator: (v) => (v ?? '').length < 6
                              ? '비밀번호는 6자 이상이어야 합니다.'
                              : null,
                          decoration: InputDecoration(
                            suffixIcon: IconButton(
                              tooltip: _obscure1 ? '표시' : '숨기기',
                              icon: Icon(_obscure1
                                  ? Icons.visibility_off
                                  : Icons.visibility),
                              onPressed: () =>
                                  setState(() => _obscure1 = !_obscure1),
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),

                        const _FieldLabel('비밀번호 확인'),
                        TextFormField(
                          controller: _pw2,
                          obscureText: _obscure2,
                          textInputAction: TextInputAction.done,
                          style: const TextStyle(color: textColor),
                          cursorColor: textColor,
                          onFieldSubmitted: (_) {
                            if (!_loading) _submit();
                          },
                          validator: (v) => (v ?? '') != _pw.text
                              ? '비밀번호가 일치하지 않습니다.'
                              : null,
                          decoration: InputDecoration(
                            suffixIcon: IconButton(
                              tooltip: _obscure2 ? '표시' : '숨기기',
                              icon: Icon(_obscure2
                                  ? Icons.visibility_off
                                  : Icons.visibility),
                              onPressed: () =>
                                  setState(() => _obscure2 = !_obscure2),
                            ),
                          ),
                        ),

                        if (_error != null) ...[
                          const SizedBox(height: 8),
                          Text(_error!,
                              style:
                                  TextStyle(color: theme.colorScheme.error)),
                        ],

                        const SizedBox(height: 14),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            onPressed: _loading ? null : _submit,
                            child: _loading
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2),
                                  )
                                : const Text('회원가입'),
                          ),
                        ),

                        const SizedBox(height: 14),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Text('이미 계정이 있으신가요?',
                                style: TextStyle(color: Colors.black54)),
                            TextButton(
                              onPressed: () =>
                                  Navigator.pushNamedAndRemoveUntil(
                                      context, '/login', (r) => false),
                              child: const Text('로그인'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
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
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          text,
          style: const TextStyle(
            color: Colors.black87,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
