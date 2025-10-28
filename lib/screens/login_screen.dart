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
  String? _error;

  ApiService get _api => ApiService.instance;

  @override
  void initState() {
    super.initState();
    _autoNavigateIfTokenExists();
  }

  // ----- Navigation helpers -----
  void _pushReplace(String route) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, route);
    });
  }

  void _push(String route) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.pushNamed(context, route);
    });
  }

  Future<void> _routeAfterAuth() async {
    // 토큰 기준으로 /auth/me 갱신 (관리자 여부 확보)
    final ok = await _api.refreshMe(silent: true);
    if (!mounted) return;

    if (ok && _api.isAdmin) {
      _pushReplace('/admin/pending');
    } else if (ok) {
      // 일반 사용자는 마이페이지가 더 직관적이면 /mypage, 아니면 /home
      _pushReplace('/mypage');
    } else {
      // 토큰이 무효했을 수도 있으니 로그인 화면 유지
      setState(() {
        _error = "세션이 만료되었거나 인증에 실패했습니다. 다시 로그인해주세요.";
      });
    }
  }

  Future<void> _autoNavigateIfTokenExists() async {
    // main()에서 initToken()이 선행된 상태 가정
    final t = _api.token;
    if (t != null && t.isNotEmpty) {
      await _routeAfterAuth();
    }
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    final token = await _api.login(
      _email.text.trim(),
      _password.text,
    );

    if (!mounted) return;
    setState(() => _loading = false);

    if (token != null && token.isNotEmpty) {
      // 로그인 성공 → 사용자 정보 갱신 후 권한에 따라 라우팅
      await _routeAfterAuth();
    } else {
      setState(() {
        _error = "로그인에 실패했습니다. 이메일/비밀번호를 확인해주세요.";
      });
    }
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('로그인'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Form(
                key: _formKey,
                child: ListView(
                  children: [
                    const SizedBox(height: 16),
                    Text(
                      'Sallae Mallae',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 32),

                    // 이메일
                    TextFormField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        labelText: '이메일',
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) {
                        final value = v?.trim() ?? '';
                        if (value.isEmpty) return '이메일을 입력해주세요.';
                        if (!value.contains('@')) return '올바른 이메일 형식이 아닙니다.';
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),

                    // 비밀번호
                    TextFormField(
                      controller: _password,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: '비밀번호',
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) {
                        if ((v ?? '').isEmpty) return '비밀번호를 입력해주세요.';
                        return null;
                      },
                    ),

                    const SizedBox(height: 12),
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          _error!,
                          style: const TextStyle(color: Colors.red),
                        ),
                      ),

                    const SizedBox(height: 8),
                    SizedBox(
                      height: 48,
                      child: FilledButton(
                        onPressed: _loading ? null : _submit,
                        child: _loading
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Text('로그인'),
                      ),
                    ),

                    const SizedBox(height: 16),
                    TextButton(
                      onPressed: _loading ? null : () => _push('/register'),
                      child: const Text('아직 계정이 없으신가요? 회원가입'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
