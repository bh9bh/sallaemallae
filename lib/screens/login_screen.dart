// FILE: lib/screens/login_screen.dart
import 'package:flutter/material.dart';
import '../services/api_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _loading = false;
  bool _obscure = true;
  bool _autoLogin = true;
  String? _error;
  bool _navigated = false;

  ApiService get _api => ApiService.instance;

  @override
  void initState() {
    super.initState();
    // 이미 토큰이 있으면 프로필 동기화 후 바로 /home
    Future.microtask(() async {
      if (_api.isAuthenticated) {
        await _routeAfterAuth();
      }
    });
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  void _replaceAllTo(String route) {
    if (_navigated || !mounted) return;
    _navigated = true;
    Navigator.pushNamedAndRemoveUntil(context, route, (r) => false);
  }

  /// 관리자 개념 제거: 검증 후 항상 /home으로
  Future<void> _routeAfterAuth() async {
    final ok = await _api.refreshMe(silent: true);
    if (!mounted) return;
    if (ok) {
      _replaceAllTo('/home');
    }
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    final token = await _api.login(_email.text.trim(), _password.text);

    if (!mounted) return;
    setState(() => _loading = false);

    if (token != null && token.isNotEmpty) {
      await _routeAfterAuth();
    } else {
      setState(() => _error = '로그인에 실패했습니다. 이메일/비밀번호를 확인해주세요.');
    }
  }

  // ------- find-id / reset-pw bottom sheets -------
  void _showFindId() => _simpleSheet(
        title: '아이디 찾기',
        subtitle: '가입 이메일로 안내를 보내드립니다.',
        action: _api.forgotUsername,
      );

  void _showResetPw() => _simpleSheet(
        title: '비밀번호 재설정',
        subtitle: '가입 이메일로 재설정 링크를 보내드립니다.',
        action: _api.forgotPassword,
      );

  void _simpleSheet({
    required String title,
    required String subtitle,
    required Future<bool> Function(String email) action,
  }) {
    final c = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        bool sending = false;
        String? err;
        return StatefulBuilder(builder: (ctx, setBS) {
          Future<void> submit() async {
            final email = c.text.trim();
            if (!email.contains('@')) {
              setBS(() => err = '올바른 이메일을 입력해주세요.');
              return;
            }
            setBS(() {
              sending = true;
              err = null;
            });
            final ok = await action(email);
            if (!mounted) return;
            setBS(() => sending = false);
            if (ok) {
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('$title 메일을 발송했어요.')),
              );
            } else {
              setBS(() => err = '서버에서 아직 지원되지 않습니다. 관리자에게 문의해주세요.');
            }
          }

          return Padding(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 8,
              bottom: 16 + MediaQuery.of(ctx).viewInsets.bottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(ctx).textTheme.titleLarge),
                const SizedBox(height: 6),
                Text(subtitle, style: TextStyle(color: cs.outline)),
                const SizedBox(height: 12),
                TextField(
                  controller: c,
                  keyboardType: TextInputType.emailAddress,
                  style: const TextStyle(color: Colors.black87),
                  cursorColor: Colors.black87,
                  decoration: const InputDecoration(
                    labelText: '이메일',
                    border: OutlineInputBorder(),
                    hintText: 'example@domain.com',
                  ),
                  onSubmitted: (_) => submit(),
                ),
                const SizedBox(height: 10),
                if (err != null) Text(err!, style: TextStyle(color: cs.error)),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: FilledButton.icon(
                    onPressed: sending ? null : submit,
                    icon: sending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send),
                    label: Text(sending ? '발송 중...' : '메일 보내기'),
                  ),
                ),
              ],
            ),
          );
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // ======= Color & Theme (readability) =======
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
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        side: const BorderSide(color: Colors.black38),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),
    );

    return Theme(
      data: theme,
      child: Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
              child: Card(
                elevation: 0,
                color: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(height: 6),
                        const Text(
                          '살래말래',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                            color: textColor,
                            letterSpacing: -0.2,
                          ),
                        ),
                        const SizedBox(height: 20),

                        const _FieldLabel('이메일 주소'),
                        TextFormField(
                          controller: _email,
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.next,
                          style: const TextStyle(color: textColor),
                          cursorColor: textColor,
                          decoration: const InputDecoration(hintText: 'example@domain.com'),
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
                          controller: _password,
                          obscureText: _obscure,
                          textInputAction: TextInputAction.done,
                          style: const TextStyle(color: textColor),
                          cursorColor: textColor,
                          onFieldSubmitted: (_) {
                            if (!_loading) _submit();
                          },
                          validator: (v) => (v ?? '').isEmpty ? '비밀번호를 입력해주세요.' : null,
                          decoration: InputDecoration(
                            suffixIcon: IconButton(
                              tooltip: _obscure ? '표시' : '숨기기',
                              icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility),
                              onPressed: () => setState(() => _obscure = !_obscure),
                            ),
                          ),
                        ),

                        const SizedBox(height: 10),
                        CheckboxListTile(
                          value: _autoLogin,
                          onChanged: (v) => setState(() => _autoLogin = v ?? true),
                          contentPadding: EdgeInsets.zero,
                          controlAffinity: ListTileControlAffinity.leading,
                          title: const Text('자동 로그인'),
                          dense: true,
                        ),

                        if (_error != null) ...[
                          const SizedBox(height: 2),
                          Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
                        ],

                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            onPressed: _loading ? null : _submit,
                            child: _loading
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Text('로그인'),
                          ),
                        ),

                        const SizedBox(height: 16),
                        const Divider(height: 24),

                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            TextButton(onPressed: _showFindId, child: const Text('아이디 찾기')),
                            const Text(' · ', style: TextStyle(color: Colors.black45)),
                            TextButton(onPressed: _showResetPw, child: const Text('비밀번호 재설정')),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Text('처음이신가요?', style: TextStyle(color: Colors.black54)),
                            TextButton(
                              onPressed: () => Navigator.pushNamed(context, '/register'),
                              child: const Text('회원가입'),
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
