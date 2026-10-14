import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'firebase/firebase_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await FirebaseService.initialize();
  await ReminderService.initialize();
  runApp(const CicloDuploApp());
}

class ReminderService {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static const NotificationDetails _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'cycle_reminders',
      'Lembretes do ciclo',
      channelDescription: 'Lembretes locais configurados no app Ella',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
    ),
  );

  static Future<void> initialize() async {
    tzdata.initializeTimeZones();
    try {
      final zone = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(zone.identifier));
    } catch (_) {}
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
    );
  }

  static Future<bool> requestPermission() async {
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    return await android?.requestNotificationsPermission() ?? true;
  }

  static Future<void> schedule({
    required int id,
    required DateTime? nextPeriod,
  }) async {
    await _plugin.cancel(id: id);
    if (nextPeriod == null) return;
    final dayBefore = DateTime(
      nextPeriod.year,
      nextPeriod.month,
      nextPeriod.day - 1,
      9,
    );
    if (!dayBefore.isAfter(DateTime.now())) return;
    await _plugin.zonedSchedule(
      id: id,
      title: 'Um lembrete para você',
      body: 'A previsão do seu ciclo é amanhã. As datas são estimativas.',
      scheduledDate: tz.TZDateTime.from(dayBefore, tz.local),
      notificationDetails: _details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    );
  }
}

const ink = Color(0xFF191632);
const muted = Color(0xFF77748C);
const violet = Color(0xFF6838F5);
const purple = Color(0xFF9B63FF);
const coral = Color(0xFFFF5C70);
const aqua = Color(0xFF20CDB2);
const lemon = Color(0xFFFFCE4A);
const canvas = Color(0xFFF6F3FF);

class CicloDuploApp extends StatelessWidget {
  const CicloDuploApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Ella',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: canvas,
      colorScheme: ColorScheme.fromSeed(
        seedColor: violet,
        surface: Colors.white,
      ),
      fontFamily: 'Roboto',
    ),
    home: const HomePage(),
  );
}

class AccountDialog extends StatefulWidget {
  const AccountDialog({
    super.key,
    required this.onSync,
    required this.onAccountChanged,
  });

  final Future<void> Function() onSync;
  final Future<void> Function() onAccountChanged;

  @override
  State<AccountDialog> createState() => _AccountDialogState();
}

class _AccountDialogState extends State<AccountDialog> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _creating = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  String _authMessage(FirebaseAuthException error) => switch (error.code) {
    'invalid-email' => 'Confira o formato do e-mail.',
    'user-not-found' ||
    'wrong-password' ||
    'invalid-credential' => 'E-mail ou senha incorretos.',
    'email-already-in-use' => 'Já existe uma conta com este e-mail.',
    'weak-password' => 'Use uma senha com pelo menos 6 caracteres.',
    'too-many-requests' =>
      'Muitas tentativas. Aguarde um pouco e tente de novo.',
    _ => 'Não foi possível acessar a conta. Tente novamente.',
  };

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final service = AccountService();
      if (_creating) {
        await service.createAccount(
          email: _email.text,
          password: _password.text,
        );
      } else {
        await service.signIn(email: _email.text, password: _password.text);
      }
      await widget.onAccountChanged();
      if (mounted) {
        setState(() => _busy = false);
      }
    } on FirebaseAuthException catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = _authMessage(error);
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'Firebase ainda não está configurado neste app.';
        });
      }
    }
  }

  Future<void> _sync() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onSync();
      if (mounted) {
        setState(() => _error = 'Cópia enviada com segurança para sua conta.');
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Não foi possível salvar no Firestore. Confira a conexão e as regras.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseService.isReady ? AccountService().currentUser : null;
    return AlertDialog(
      icon: const Icon(Icons.cloud_outlined, color: violet, size: 32),
      title: Text(user == null ? 'Conta Ella' : 'Conta conectada'),
      content: SizedBox(
        width: 360,
        child: user != null
            ? Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    user.email ?? 'Sessão iniciada',
                    style: const TextStyle(color: muted),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'Sua cópia local continua neste aparelho. Ao tocar abaixo, seus registros pessoais serão enviados à sua área privada no Firestore.',
                    style: TextStyle(color: muted, height: 1.4),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _busy ? null : _sync,
                    icon: const Icon(Icons.cloud_upload_outlined),
                    label: const Text('Enviar cópia para a nuvem'),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 8),
                    Text(_error!, style: const TextStyle(color: violet)),
                  ],
                ],
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (!FirebaseService.isReady)
                    const Text(
                      'Adicione a configuração Android do Firebase e ative E-mail/senha no Authentication para conectar uma conta.',
                      style: TextStyle(color: muted, height: 1.4),
                    )
                  else ...[
                    TextField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.email],
                      decoration: const InputDecoration(labelText: 'E-mail'),
                    ),
                    TextField(
                      controller: _password,
                      obscureText: true,
                      autofillHints: const [AutofillHints.password],
                      decoration: const InputDecoration(labelText: 'Senha'),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 8),
                      Text(_error!, style: const TextStyle(color: coral)),
                    ],
                    const SizedBox(height: 10),
                    FilledButton(
                      onPressed: _busy ? null : _submit,
                      child: _busy
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(_creating ? 'Criar conta' : 'Entrar'),
                    ),
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => setState(() {
                              _creating = !_creating;
                              _error = null;
                            }),
                      child: Text(
                        _creating ? 'Já tenho uma conta' : 'Criar uma conta',
                      ),
                    ),
                  ],
                ],
              ),
      ),
      actions: [
        if (user != null)
          TextButton(
            onPressed: _busy
                ? null
                : () async {
                    await AccountService().signOut();
                    if (context.mounted) setState(() => _error = null);
                  },
            child: const Text('Sair da conta'),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Fechar'),
        ),
      ],
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  static const _storage = FlutterSecureStorage();
  static const _storageKey = 'cycle_data_v1';
  final DateTime _today = DateUtils.dateOnly(DateTime.now());
  List<DateTime> _ownStarts = [];
  List<DateTime> _sharedStarts = [];
  Map<DateTime, DateTime> _ownEnds = {};
  Map<DateTime, DateTime> _sharedEnds = {};
  Map<String, DailyLog> _ownLogs = {};
  Map<String, DailyLog> _sharedLogs = {};
  bool _ownReminderEnabled = false;
  bool _sharedReminderEnabled = false;
  bool _sharedMode = false;
  bool _loading = true;
  bool _storageError = false;
  PairConnection? _pairConnection;
  StreamSubscription<dynamic>? _pairSubscription;
  StreamSubscription<dynamic>? _cycleSubscription;

  List<DateTime> get _starts => _sharedMode ? _sharedStarts : _ownStarts;
  Map<DateTime, DateTime> get _ends => _sharedMode ? _sharedEnds : _ownEnds;
  String get _todayKey => _dateKey(_today);

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _pairSubscription?.cancel();
    _cycleSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadData() async {
    try {
      final raw = await _storage.read(key: _storageKey);
      if (raw != null) {
        final decoded = jsonDecode(raw);
        List<DateTime> parseDates(dynamic values) =>
            (values as List<dynamic>? ?? [])
                .map(
                  (value) =>
                      DateUtils.dateOnly(DateTime.parse(value as String)),
                )
                .toSet()
                .toList()
              ..sort();
        Map<DateTime, DateTime> parseEndDates(dynamic values) {
          if (values is! Map) return {};
          final ends = <DateTime, DateTime>{};
          for (final entry in values.entries) {
            try {
              final start = DateUtils.dateOnly(
                DateTime.parse(entry.key as String),
              );
              final end = DateUtils.dateOnly(
                DateTime.parse(entry.value as String),
              );
              if (!end.isBefore(start)) ends[start] = end;
            } catch (_) {}
          }
          return ends;
        }

        if (decoded is List<dynamic>) {
          _ownStarts = parseDates(decoded);
        } else if (decoded is Map<String, dynamic>) {
          _ownStarts = parseDates(decoded['own']);
          _sharedStarts = parseDates(decoded['shared']);
          _ownEnds = parseEndDates(decoded['own_ends']);
          _sharedEnds = parseEndDates(decoded['shared_ends']);
          _ownLogs = _parseLogs(decoded['own_logs']);
          _sharedLogs = _parseLogs(decoded['shared_logs']);
          _ownReminderEnabled = decoded['own_reminder'] == true;
          _sharedReminderEnabled = decoded['shared_reminder'] == true;
        }
        try {
          await ReminderService.schedule(id: 101, nextPeriod: null);
          if (_ownReminderEnabled) {
            await ReminderService.schedule(
              id: 100,
              nextPeriod: _nextPeriodFor(_ownStarts),
            );
          }
          if (_sharedReminderEnabled) {
            await ReminderService.schedule(
              id: 101,
              nextPeriod: _nextPeriodFor(_sharedStarts),
            );
          }
        } catch (_) {}
        if (mounted) setState(() {});
      }
    } catch (_) {
      if (mounted) setState(() => _storageError = true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
    await _refreshPairing();
  }

  Future<void> _refreshPairing() async {
    if (!FirebaseService.isReady) return;
    final user = AccountService().currentUser;
    if (user == null) {
      await _pairSubscription?.cancel();
      await _cycleSubscription?.cancel();
      if (mounted) {
        setState(() {
          _pairConnection = null;
          _sharedStarts = [];
          _sharedEnds = {};
          _sharedLogs = {};
        });
      }
      return;
    }
    try {
      final connection = await CyclePairService().current(user.uid);
      await _setPairConnection(connection);
    } catch (_) {
      // Preserve the last known connection when the phone is temporarily offline.
    }
  }

  Future<void> _setPairConnection(PairConnection? connection) async {
    final oldCode = _pairConnection?.code;
    if (oldCode != connection?.code) {
      await _pairSubscription?.cancel();
      await _cycleSubscription?.cancel();
      _pairSubscription = null;
      _cycleSubscription = null;
    }
    if (mounted) {
      setState(() {
        _pairConnection = connection;
        if (connection == null && oldCode != null) {
          _sharedStarts = [];
          _sharedEnds = {};
          _sharedLogs = {};
        }
      });
    }
    if (connection == null) {
      if (oldCode != null) unawaited(_persistData());
      return;
    }
    if (oldCode == connection.code) return;

    _pairSubscription = CyclePairService().watchPair(connection.code).listen((
      snapshot,
    ) {
      final data = snapshot.data();
      if (data == null || data['status'] == 'closed') {
        unawaited(_handlePairEnded(connection.code));
        return;
      }
      final updated = PairConnection.fromMap(connection.code, data);
      if (mounted) setState(() => _pairConnection = updated);
    }, onError: (_) {});

    if (!connection.isOwner && connection.isActive) {
      _cycleSubscription = CyclePairService()
          .watchCycle(connection.code)
          .listen(
            (snapshot) {
              final data = snapshot.data();
              if (data != null) unawaited(_applySharedCycle(data));
            },
            onError: (_) {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'A sincronização foi interrompida. Confira a conexão.',
                    ),
                  ),
                );
              }
            },
          );
    } else if (connection.isOwner) {
      await _syncPairCycleIfOwner();
    }
  }

  Future<void> _handlePairEnded(String code) async {
    if (_pairConnection?.code != code) return;
    final user = AccountService().currentUser;
    await _pairSubscription?.cancel();
    await _cycleSubscription?.cancel();
    _pairSubscription = null;
    _cycleSubscription = null;
    if (user != null) {
      try {
        final connection = _pairConnection;
        if (connection?.isOwner == true) {
          await CyclePairService().closePair(
            code: code,
            uid: user.uid,
            isOwner: true,
          );
        } else {
          await CyclePairService().clearMembership(user.uid);
        }
      } catch (_) {}
    }
    if (!mounted) return;
    setState(() {
      _pairConnection = null;
      _sharedStarts = [];
      _sharedEnds = {};
      _sharedLogs = {};
    });
    await _persistData();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('O compartilhamento foi encerrado.')),
      );
    }
  }

  Future<void> _applySharedCycle(Map<String, dynamic> data) async {
    List<DateTime> parseDates(dynamic values) {
      if (values is! List) return [];
      final dates = <DateTime>[];
      for (final value in values) {
        try {
          dates.add(DateUtils.dateOnly(DateTime.parse(value as String)));
        } catch (_) {}
      }
      return dates.toSet().toList()..sort();
    }

    final ends = <DateTime, DateTime>{};
    final rawEnds = data['ends'];
    if (rawEnds is Map) {
      for (final entry in rawEnds.entries) {
        try {
          ends[DateUtils.dateOnly(DateTime.parse(entry.key as String))] =
              DateUtils.dateOnly(DateTime.parse(entry.value as String));
        } catch (_) {}
      }
    }
    if (!mounted) return;
    setState(() {
      _sharedStarts = parseDates(data['starts']);
      _sharedEnds = ends;
      _sharedLogs = _parseLogs(data['dailyLogs']);
    });
    try {
      await _persistData();
    } catch (_) {
      if (mounted) setState(() => _storageError = true);
    }
  }

  Map<String, dynamic> _ownCycleCloudData() => {
    'starts': _ownStarts.map((date) => date.toIso8601String()).toList(),
    'ends': _serializeEndDates(_ownEnds),
    'dailyLogs': _serializeLogs(_ownLogs),
  };

  Future<void> _syncPairCycleIfOwner() async {
    final connection = _pairConnection;
    final user = AccountService().currentUser;
    if (connection == null || !connection.isOwner || user == null) return;
    try {
      if (mounted) {
        setState(() {
          _sharedStarts = List<DateTime>.from(_ownStarts);
          _sharedEnds = Map<DateTime, DateTime>.from(_ownEnds);
          _sharedLogs = Map<String, DailyLog>.from(_ownLogs);
        });
      }
      await _persistData();
      await CyclePairService().saveCycle(
        code: connection.code,
        uid: user.uid,
        data: _ownCycleCloudData(),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Registro salvo neste celular; a sincronização será retomada quando houver conexão.',
            ),
          ),
        );
      }
    }
  }

  Future<void> _saveStart(DateTime date, {required bool add}) async {
    final shared = _sharedMode;
    final current = shared ? _sharedStarts : _ownStarts;
    final next = [...current];
    final nextEnds = Map<DateTime, DateTime>.from(
      shared ? _sharedEnds : _ownEnds,
    );
    if (add) {
      if (!next.contains(date)) next.add(date);
    } else {
      next.remove(date);
      nextEnds.remove(date);
    }
    next.sort();
    if (mounted) {
      setState(() {
        if (shared) {
          _sharedStarts = next;
          _sharedEnds = nextEnds;
        } else {
          _ownStarts = next;
          _ownEnds = nextEnds;
        }
      });
    }
    try {
      await _persistData();
      if (!shared) await _syncPairCycleIfOwner();
      final enabled = shared ? _sharedReminderEnabled : _ownReminderEnabled;
      if (enabled) {
        await ReminderService.schedule(
          id: shared ? 101 : 100,
          nextPeriod: _nextPeriodFor(next),
        );
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _storageError = true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Não foi possível salvar este registro neste aparelho.',
          ),
        ),
      );
    }
  }

  Future<void> _saveEnd(
    DateTime start,
    DateTime end, {
    required bool add,
  }) async {
    final shared = _sharedMode;
    final next = Map<DateTime, DateTime>.from(shared ? _sharedEnds : _ownEnds);
    if (add) {
      next[start] = end;
    } else {
      next.remove(start);
    }
    if (mounted) {
      setState(() => shared ? _sharedEnds = next : _ownEnds = next);
    }
    try {
      await _persistData();
      if (!shared) await _syncPairCycleIfOwner();
    } catch (_) {
      if (!mounted) return;
      setState(() => _storageError = true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Não foi possível salvar o fim da menstruação.'),
        ),
      );
    }
  }

  Future<void> _persistData() => _storage.write(
    key: _storageKey,
    value: jsonEncode({
      'own': _ownStarts.map((value) => value.toIso8601String()).toList(),
      'shared': _sharedStarts.map((value) => value.toIso8601String()).toList(),
      'own_ends': _serializeEndDates(_ownEnds),
      'shared_ends': _serializeEndDates(_sharedEnds),
      'own_logs': _serializeLogs(_ownLogs),
      'shared_logs': _serializeLogs(_sharedLogs),
      'own_reminder': _ownReminderEnabled,
      'shared_reminder': _sharedReminderEnabled,
    }),
  );

  Future<void> _openDailyLog() async {
    final shared = _sharedMode;
    final existing = (shared ? _sharedLogs : _ownLogs)[_todayKey];
    final result = await showModalBottomSheet<DailyLogEdit>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) =>
          DailyLogSheet(date: _today, initial: existing, sharedMode: shared),
    );
    if (result == null) return;
    final logs = Map<String, DailyLog>.from(shared ? _sharedLogs : _ownLogs);
    if (result.log == null) {
      logs.remove(_todayKey);
    } else {
      logs[_todayKey] = result.log!;
    }
    if (mounted) setState(() => shared ? _sharedLogs = logs : _ownLogs = logs);
    try {
      await _persistData();
      if (!shared) await _syncPairCycleIfOwner();
    } catch (_) {
      if (!mounted) return;
      setState(() => _storageError = true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Não foi possível salvar o diário neste aparelho.'),
        ),
      );
    }
  }

  Future<void> _toggleReminder(bool enabled) async {
    final shared = _sharedMode;
    if (enabled && !await ReminderService.requestPermission()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Permita notificações nas configurações do aparelho para receber lembretes.',
            ),
          ),
        );
      }
      return;
    }
    if (mounted) {
      setState(
        () => shared
            ? _sharedReminderEnabled = enabled
            : _ownReminderEnabled = enabled,
      );
    }
    try {
      await _persistData();
      if (enabled) {
        await ReminderService.schedule(
          id: shared ? 101 : 100,
          nextPeriod: _nextPeriodFor(shared ? _sharedStarts : _ownStarts),
        );
      } else {
        await ReminderService.schedule(
          id: shared ? 101 : 100,
          nextPeriod: null,
        );
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _storageError = true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Não foi possível configurar o lembrete.'),
        ),
      );
    }
  }

  Future<void> _openCalendar() async {
    if (_sharedMode) {
      if (_pairConnection?.isActive != true) {
        await _showPairingInfo(createCode: false);
        return;
      }
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => CalendarPage(
            starts: _sharedStarts,
            ends: _sharedEnds,
            sharedMode: true,
            readOnly: true,
          ),
        ),
      );
      return;
    }
    final edit = await Navigator.of(context).push<CycleEdit>(
      MaterialPageRoute(
        builder: (_) =>
            CalendarPage(starts: _starts, ends: _ends, sharedMode: _sharedMode),
      ),
    );
    if (edit == null) return;
    if (edit.startDateForEnd != null) {
      await _saveEnd(edit.startDateForEnd!, edit.date, add: edit.add);
    } else {
      await _saveStart(edit.date, add: edit.add);
    }
  }

  Future<void> _showPairingInfo({required bool createCode}) async {
    if (!await _requireAccount()) return;
    if (createCode) {
      await _createPairInvite();
    } else {
      await _enterPairCode();
    }
  }

  Future<bool> _requireAccount() async {
    if (!FirebaseService.isReady) {
      _showMessage('O Firebase ainda não está disponível neste app.');
      return false;
    }
    if (AccountService().currentUser == null) await _openAccount();
    if (AccountService().currentUser != null) return true;
    _showMessage('Entre ou crie uma conta para compartilhar um ciclo.');
    return false;
  }

  Future<void> _createPairInvite() async {
    final user = AccountService().currentUser;
    if (user == null) return;
    final existing = _pairConnection;
    if (existing != null) {
      if (existing.isOwner && existing.isPending) {
        await _showInviteCode(existing.code);
      } else {
        _showMessage('Esta conta já está conectada a um ciclo.');
      }
      return;
    }
    try {
      final code = await CyclePairService().createInvite(
        uid: user.uid,
        cycleData: _ownCycleCloudData(),
      );
      await _refreshPairing();
      if (mounted) await _showInviteCode(code);
    } on StateError catch (error) {
      _showMessage(error.message.toString());
    } catch (_) {
      _showMessage(
        'Não foi possível criar o convite. Confira a internet e o Firebase.',
      );
    }
  }

  Future<void> _showInviteCode(String code) => showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      icon: const Icon(Icons.qr_code_2_rounded, color: violet, size: 34),
      title: const Text('Convide alguém para acompanhar'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Envie este código para a outra pessoa. Ele pode ser usado uma vez e expira em 30 minutos.',
            style: TextStyle(color: muted, height: 1.4),
          ),
          const SizedBox(height: 18),
          SelectableText(
            code,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: violet,
              fontSize: 25,
              fontWeight: FontWeight.w900,
              letterSpacing: 3,
            ),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: code));
              if (dialogContext.mounted) Navigator.pop(dialogContext);
              _showMessage('Código copiado. Compartilhe com segurança.');
            },
            icon: const Icon(Icons.copy_rounded),
            label: const Text('Copiar código'),
          ),
        ],
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('Concluído'),
        ),
      ],
    ),
  );

  Future<void> _enterPairCode() async {
    final controller = TextEditingController();
    var busy = false;
    String? error;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          icon: const Icon(Icons.key_rounded, color: violet, size: 32),
          title: const Text('Inserir código recebido'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Ao conectar, você poderá consultar o ciclo compartilhado. Os registros pessoais deste aparelho permanecem privados.',
                style: TextStyle(color: muted, height: 1.4),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: controller,
                autofocus: true,
                textCapitalization: TextCapitalization.characters,
                maxLength: 10,
                decoration: const InputDecoration(
                  labelText: 'Código de convite',
                  counterText: '',
                ),
              ),
              if (error != null)
                Text(error!, style: const TextStyle(color: coral)),
            ],
          ),
          actions: [
            TextButton(
              onPressed: busy ? null : () => Navigator.pop(dialogContext),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: busy
                  ? null
                  : () async {
                      setDialogState(() {
                        busy = true;
                        error = null;
                      });
                      try {
                        final user = AccountService().currentUser;
                        if (user == null) {
                          throw StateError('Entre na sua conta primeiro.');
                        }
                        await CyclePairService().joinInvite(
                          uid: user.uid,
                          code: controller.text,
                        );
                        await _refreshPairing();
                        if (dialogContext.mounted) Navigator.pop(dialogContext);
                        _showMessage(
                          'Conectado. O ciclo será atualizado automaticamente.',
                        );
                      } on StateError catch (exception) {
                        setDialogState(() {
                          busy = false;
                          error = exception.message.toString();
                        });
                      } catch (_) {
                        setDialogState(() {
                          busy = false;
                          error = 'Não foi possível conectar. Confira o código e a internet.';
                        });
                      }
                    },
              child: busy
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Conectar'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
  }

  Future<void> _leavePair() async {
    final connection = _pairConnection;
    final user = AccountService().currentUser;
    if (connection == null || user == null) return;
    final leave = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Encerrar compartilhamento?'),
        content: const Text(
          'O outro aparelho deixará de receber atualizações deste ciclo.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Continuar conectado'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Encerrar'),
          ),
        ],
      ),
    );
    if (leave != true) return;
    try {
      await CyclePairService().closePair(
        code: connection.code,
        uid: user.uid,
        isOwner: connection.isOwner,
      );
      await _refreshPairing();
    } catch (_) {
      _showMessage('Não foi possível encerrar agora. Confira a internet.');
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _openAccount() async => showDialog<void>(
    context: context,
    builder: (_) =>
        AccountDialog(onSync: _syncToCloud, onAccountChanged: _refreshPairing),
  ).then((_) => _refreshPairing());

  Future<void> _syncToCloud() async {
    final user = AccountService().currentUser;
    if (user == null) throw StateError('Entre na sua conta primeiro.');
    await CycleCloudStore().save(
      uid: user.uid,
      data: {
        'starts': _ownStarts.map((date) => date.toIso8601String()).toList(),
        'ends': _serializeEndDates(_ownEnds),
        'dailyLogs': _serializeLogs(_ownLogs),
        'reminderEnabled': _ownReminderEnabled,
      },
    );
  }

  DateTime? get _nextPeriod {
    return _nextPeriodFor(_starts);
  }

  DateTime? _nextPeriodFor(List<DateTime> starts) {
    if (starts.isEmpty) return null;
    var next = starts.last.add(const Duration(days: 28));
    while (next.isBefore(_today)) {
      next = next.add(const Duration(days: 28));
    }
    return next;
  }

  int? get _daysUntilNext {
    final next = _nextPeriod;
    return next?.difference(_today).inDays;
  }

  @override
  Widget build(BuildContext context) {
    final next = _nextPeriod;
    final days = _daysUntilNext;
    return Scaffold(
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator(color: violet))
            : CustomScrollView(
                slivers: [
                  SliverAppBar(
                    pinned: true,
                    toolbarHeight: 72,
                    backgroundColor: canvas,
                    surfaceTintColor: Colors.transparent,
                    leadingWidth: 68,
                    leading: Padding(
                      padding: const EdgeInsets.only(left: 18),
                      child: CircleAvatar(
                        backgroundColor: violet,
                        child: const Icon(
                          Icons.auto_awesome_rounded,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    title: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Ella',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                            color: ink,
                          ),
                        ),
                        Text(
                          _dateLabel(_today),
                          style: const TextStyle(
                            fontSize: 13,
                            color: muted,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    actions: [
                      IconButton.filledTonal(
                        tooltip: 'Conta e sincronização',
                        onPressed: _openAccount,
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: violet,
                        ),
                        icon: const Icon(Icons.account_circle_outlined),
                      ),
                      const SizedBox(width: 6),
                      IconButton.filledTonal(
                        tooltip: _sharedMode
                            ? 'Conectar por código'
                            : 'Abrir calendário',
                        onPressed: _sharedMode
                            ? () => _showPairingInfo(createCode: false)
                            : _openCalendar,
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: violet,
                        ),
                        icon: Icon(
                          _sharedMode
                              ? Icons.qr_code_2_rounded
                              : Icons.calendar_month_rounded,
                        ),
                      ),
                      const SizedBox(width: 18),
                    ],
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SegmentedButton<bool>(
                            showSelectedIcon: false,
                            style: ButtonStyle(
                              visualDensity: VisualDensity.compact,
                              backgroundColor: WidgetStateProperty.resolveWith(
                                (states) =>
                                    states.contains(WidgetState.selected)
                                    ? ink
                                    : Colors.white,
                              ),
                              foregroundColor: WidgetStateProperty.resolveWith(
                                (states) =>
                                    states.contains(WidgetState.selected)
                                    ? Colors.white
                                    : muted,
                              ),
                              side: WidgetStateProperty.all(BorderSide.none),
                              shape: WidgetStateProperty.all(
                                RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                            ),
                            segments: const [
                              ButtonSegment(
                                value: false,
                                label: Text('Meu ciclo'),
                                icon: Icon(Icons.person_rounded),
                              ),
                              ButtonSegment(
                                value: true,
                                label: Text('Compartilhado'),
                                icon: Icon(Icons.people_alt_rounded),
                              ),
                            ],
                            selected: {_sharedMode},
                            onSelectionChanged: (values) =>
                                setState(() => _sharedMode = values.first),
                          ),
                          const SizedBox(height: 18),
                          if (_sharedMode) ...[
                            SharedCycleLanding(
                              connection: _pairConnection,
                              latestStart: _sharedStarts.isEmpty
                                  ? null
                                  : _sharedStarts.last,
                              nextPeriod: _nextPeriodFor(_sharedStarts),
                              onOpenCalendar: _openCalendar,
                              onCreateCode: () =>
                                  _showPairingInfo(createCode: true),
                              onEnterCode: () =>
                                  _showPairingInfo(createCode: false),
                              onLeavePair: _leavePair,
                            ),
                            const SizedBox(height: 20),
                            SectionHeading(title: 'Apoiar com cuidado'),
                            const SizedBox(height: 12),
                            const CarePrompt(sharedMode: true),
                            const SizedBox(height: 20),
                            if (_storageError)
                              const InlineNotice(
                                text: 'O armazenamento seguro não respondeu. Confira o aparelho antes de confiar nos registros.',
                              ),
                          ] else ...[
                            CycleHero(
                              sharedMode: false,
                              daysUntil: days,
                              nextDate: next,
                              hasData: _ownStarts.isNotEmpty,
                              onRecord: _openCalendar,
                            ),
                            const SizedBox(height: 18),
                            Row(
                              children: [
                                Expanded(
                                  child: MetricTile(
                                    icon: Icons.water_drop_rounded,
                                    label: 'Último início',
                                    value: _ownStarts.isEmpty
                                        ? 'Sem registro'
                                        : _shortDate(_ownStarts.last),
                                    accent: coral,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                const Expanded(
                                  child: MetricTile(
                                    icon: Icons.loop_rounded,
                                    label: 'Ciclo médio',
                                    value: '28 dias',
                                    accent: aqua,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 28),
                            SectionHeading(
                              title: 'Seu espaço',
                              action: 'Calendário',
                              onTap: _openCalendar,
                            ),
                            const SizedBox(height: 12),
                            CalendarPeek(
                              today: _today,
                              starts: _ownStarts,
                              ends: _ownEnds,
                              onTap: _openCalendar,
                            ),
                            const SizedBox(height: 28),
                            SectionHeading(
                              title: 'Como você está hoje?',
                              action: 'Registrar',
                              onTap: _openDailyLog,
                            ),
                            const SizedBox(height: 12),
                            DailyLogCard(
                              log: _ownLogs[_todayKey],
                              onTap: _openDailyLog,
                            ),
                            const SizedBox(height: 14),
                            ReminderCard(
                              enabled: _ownReminderEnabled,
                              sharedMode: false,
                              onChanged: _toggleReminder,
                            ),
                            const SizedBox(height: 28),
                            SectionHeading(title: 'Pequenos cuidados'),
                            const SizedBox(height: 12),
                            const CarePrompt(sharedMode: false),
                            const SizedBox(height: 20),
                            if (_storageError)
                              const InlineNotice(
                                text: 'O armazenamento seguro não respondeu. Confira o aparelho antes de confiar nos registros.',
                              ),
                            const Text(
                              'As previsões são estimativas e não devem ser usadas como método contraceptivo ou orientação médica. Seus registros ficam protegidos neste aparelho.',
                              style: TextStyle(
                                color: muted,
                                height: 1.45,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class CycleHero extends StatelessWidget {
  const CycleHero({
    super.key,
    required this.sharedMode,
    required this.daysUntil,
    required this.nextDate,
    required this.hasData,
    required this.onRecord,
  });
  final bool sharedMode;
  final int? daysUntil;
  final DateTime? nextDate;
  final bool hasData;
  final VoidCallback onRecord;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    constraints: const BoxConstraints(minHeight: 258),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [violet, Color(0xFF4820C6), Color(0xFF251B65)],
      ),
      borderRadius: BorderRadius.circular(30),
      boxShadow: const [
        BoxShadow(
          color: Color(0x333F20B9),
          blurRadius: 20,
          offset: Offset(0, 10),
        ),
      ],
    ),
    child: Stack(
      children: [
        Positioned(
          right: -30,
          top: -42,
          child: Container(
            width: 190,
            height: 190,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: aqua.withValues(alpha: .16),
            ),
          ),
        ),
        Positioned(
          right: 28,
          top: 34,
          child: Icon(
            sharedMode ? Icons.favorite_rounded : Icons.bubble_chart_rounded,
            color: Colors.white.withValues(alpha: .16),
            size: 92,
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                sharedMode ? 'CICLO COMPARTILHADO' : 'VISÃO DO SEU CICLO',
                style: const TextStyle(
                  color: Color(0xFFDCD1FF),
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                  letterSpacing: 1.1,
                ),
              ),
              const SizedBox(height: 16),
              if (hasData) ...[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${daysUntil ?? 0}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 78,
                        height: .95,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -4,
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.only(left: 10, bottom: 9),
                      child: Text(
                        'dias',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  sharedMode
                      ? 'estimados até a próxima menstruação dela'
                      : 'estimados até a próxima menstruação',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  nextDate == null
                      ? 'Previsão aproximada'
                      : 'Previsão aproximada: ${_shortDate(nextDate!)}',
                  style: const TextStyle(
                    color: Color(0xFFDCD1FF),
                    fontSize: 13,
                  ),
                ),
              ] else ...[
                Text(
                  sharedMode ? 'Conheça o ciclo dela' : 'Comece pelo seu ciclo',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 30,
                    height: 1.08,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -.5,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  sharedMode
                      ? 'Registrem a última data para ver estimativas e acompanhar o calendário.'
                      : 'Registre o início da última menstruação para começar a acompanhar.',
                  style: const TextStyle(
                    color: Color(0xFFE5DEFF),
                    fontSize: 15,
                    height: 1.35,
                  ),
                ),
              ],
              const SizedBox(height: 19),
              FilledButton.icon(
                onPressed: onRecord,
                style: FilledButton.styleFrom(
                  backgroundColor: lemon,
                  foregroundColor: ink,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 13,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                ),
                icon: Icon(
                  hasData ? Icons.edit_calendar_rounded : Icons.add_rounded,
                  size: 20,
                ),
                label: Text(
                  hasData ? 'Abrir calendário' : 'Registrar uma data',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class SharedCycleLanding extends StatelessWidget {
  const SharedCycleLanding({
    super.key,
    required this.connection,
    required this.latestStart,
    required this.nextPeriod,
    required this.onOpenCalendar,
    required this.onCreateCode,
    required this.onEnterCode,
    required this.onLeavePair,
  });

  final PairConnection? connection;
  final DateTime? latestStart;
  final DateTime? nextPeriod;
  final VoidCallback onOpenCalendar;
  final VoidCallback onCreateCode;
  final VoidCallback onEnterCode;
  final VoidCallback onLeavePair;

  @override
  Widget build(BuildContext context) {
    final isConnected = connection?.isActive == true;
    final isPending = connection?.isPending == true && connection!.isOwner;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [violet, Color(0xFF4820C6), Color(0xFF251B65)],
        ),
        borderRadius: BorderRadius.circular(28),
        boxShadow: const [
          BoxShadow(
            color: Color(0x333F20B9),
            blurRadius: 20,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.people_alt_rounded, color: lemon, size: 25),
              const SizedBox(width: 9),
              const Expanded(
                child: Text(
                  'CICLO COMPARTILHADO',
                  style: TextStyle(
                    color: Color(0xFFDCD1FF),
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                    letterSpacing: 1.1,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .15),
                  borderRadius: BorderRadius.circular(30),
                ),
                child: Text(
                  isConnected
                      ? 'CONECTADO'
                      : isPending
                      ? 'AGUARDANDO'
                      : 'PRONTO PARA CONECTAR',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                    letterSpacing: .5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          Text(
            isConnected
                ? 'O ciclo está conectado'
                : isPending
                ? 'Seu convite está pronto'
                : 'Acompanhe alguém de verdade',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 26,
              height: 1.08,
              fontWeight: FontWeight.w900,
              letterSpacing: -.5,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            isConnected
                ? 'As datas e registros do ciclo chegam automaticamente quando a pessoa atualiza o app.'
                : isPending
                ? 'Compartilhe o código com a pessoa que vai acompanhar o seu ciclo.'
                : 'Conecte duas contas para compartilhar um ciclo com atualização automática.',
            style: const TextStyle(
              color: Color(0xFFE5DEFF),
              fontSize: 14,
              height: 1.45,
            ),
          ),
          if (isConnected) ...[
            const SizedBox(height: 18),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: .12),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    latestStart == null
                        ? 'Ainda não há início registrado'
                        : 'Último início: ${_shortDate(latestStart!)}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (nextPeriod != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      'Próxima previsão: ${_shortDate(nextPeriod!)}',
                      style: const TextStyle(color: Color(0xFFE5DEFF)),
                    ),
                  ],
                ],
              ),
            ),
          ],
          if (isPending) ...[
            const SizedBox(height: 16),
            Center(
              child: SelectableText(
                connection!.code,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 3,
                ),
              ),
            ),
          ],
          const SizedBox(height: 22),
          if (isConnected) ...[
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onOpenCalendar,
                style: FilledButton.styleFrom(
                  backgroundColor: lemon,
                  foregroundColor: ink,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                ),
                icon: const Icon(Icons.calendar_month_rounded),
                label: const Text(
                  'Ver calendário compartilhado',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onLeavePair,
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: BorderSide(color: Colors.white.withValues(alpha: .42)),
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                ),
                icon: const Icon(Icons.link_off_rounded),
                label: const Text('Encerrar compartilhamento'),
              ),
            ),
          ] else ...[
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onCreateCode,
                style: FilledButton.styleFrom(
                  backgroundColor: lemon,
                  foregroundColor: ink,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                ),
                icon: Icon(
                  isPending ? Icons.copy_rounded : Icons.qr_code_2_rounded,
                ),
                label: Text(
                  isPending
                      ? 'Copiar código do convite'
                      : 'Criar código de convite',
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
            ),
            if (connection == null) ...[
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: onEnterCode,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: BorderSide(
                      color: Colors.white.withValues(alpha: .42),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15),
                    ),
                  ),
                  icon: const Icon(Icons.key_rounded),
                  label: const Text(
                    'Inserir código recebido',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ),
            ],
            if (isPending) ...[
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: onLeavePair,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: BorderSide(
                      color: Colors.white.withValues(alpha: .42),
                    ),
                  ),
                  icon: const Icon(Icons.close_rounded),
                  label: const Text('Cancelar convite'),
                ),
              ),
            ],
          ],
          const SizedBox(height: 14),
          const Text(
            'A outra pessoa só pode consultar o ciclo compartilhado. Seus registros pessoais ficam privados.',
            style: TextStyle(
              color: Color(0xFFDCD1FF),
              fontSize: 11,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

class MetricTile extends StatelessWidget {
  const MetricTile({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.accent,
  });
  final IconData icon;
  final String label;
  final String value;
  final Color accent;

  @override
  Widget build(BuildContext context) => Container(
    height: 112,
    padding: const EdgeInsets.all(15),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(22),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Icon(icon, color: accent, size: 19),
            const SizedBox(width: 7),
            Text(
              label,
              style: const TextStyle(
                color: muted,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            style: const TextStyle(
              color: ink,
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ],
    ),
  );
}

class SectionHeading extends StatelessWidget {
  const SectionHeading({
    super.key,
    required this.title,
    this.action,
    this.onTap,
  });
  final String title;
  final String? action;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(
          title,
          style: const TextStyle(
            color: ink,
            fontSize: 21,
            fontWeight: FontWeight.w900,
            letterSpacing: -.3,
          ),
        ),
      ),
      if (action != null)
        TextButton(
          onPressed: onTap,
          child: Text(
            action!,
            style: const TextStyle(color: violet, fontWeight: FontWeight.w800),
          ),
        ),
    ],
  );
}

class CalendarPeek extends StatelessWidget {
  const CalendarPeek({
    super.key,
    required this.today,
    required this.starts,
    required this.ends,
    required this.onTap,
  });
  final DateTime today;
  final List<DateTime> starts;
  final Map<DateTime, DateTime> ends;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final monday = today.subtract(Duration(days: (today.weekday + 6) % 7));
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    _monthName(today.month),
                    style: const TextStyle(
                      fontSize: 17,
                      color: ink,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const Spacer(),
                  const Icon(Icons.arrow_forward_rounded, color: violet),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: List.generate(7, (index) {
                  final date = monday.add(Duration(days: index));
                  final stage = _stageFor(date, starts, ends);
                  final isToday = date == today;
                  final isPeriodEnd = ends.values.contains(date);
                  final markColor = stage == CycleStage.period
                      ? coral
                      : stage == CycleStage.fertile
                      ? aqua
                      : violet;
                  return Expanded(
                    child: Column(
                      children: [
                        Text(
                          _weekdayShort(date.weekday),
                          style: const TextStyle(
                            color: muted,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          width: 34,
                          height: 34,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: isToday
                                ? violet
                                : stage == CycleStage.period && !isPeriodEnd
                                ? coral
                                : Colors.transparent,
                            shape: BoxShape.circle,
                            border: isPeriodEnd
                                ? Border.all(color: coral, width: 1.7)
                                : null,
                          ),
                          child: Text(
                            '${date.day}',
                            style: TextStyle(
                              color:
                                  isToday ||
                                      (stage == CycleStage.period &&
                                          !isPeriodEnd)
                                  ? Colors.white
                                  : isPeriodEnd
                                  ? coral
                                  : ink,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        const SizedBox(height: 5),
                        Container(
                          width: 5,
                          height: 5,
                          decoration: BoxDecoration(
                            color: stage == CycleStage.none
                                ? Colors.transparent
                                : markColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class CarePrompt extends StatelessWidget {
  const CarePrompt({super.key, required this.sharedMode});
  final bool sharedMode;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: const Color(0xFFFFD953),
      borderRadius: BorderRadius.circular(24),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.lightbulb_rounded, color: ink, size: 28),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                sharedMode ? 'Pergunte o que ajuda' : 'Uma pausa também conta',
                style: const TextStyle(
                  color: ink,
                  fontWeight: FontWeight.w900,
                  fontSize: 17,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                sharedMode
                    ? 'Cada pessoa vive o ciclo de um jeito. Uma conversa vale mais que uma suposição.'
                    : 'Seu ciclo é só uma parte de você. Cuide do seu bem-estar sem cobrança.',
                style: const TextStyle(color: ink, height: 1.35, fontSize: 13),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class InlineNotice extends StatelessWidget {
  const InlineNotice({super.key, required this.text});
  final String text;
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    margin: const EdgeInsets.only(bottom: 16),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: const Color(0xFFFFE2E6),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Text(
      text,
      style: const TextStyle(color: ink, fontSize: 12, height: 1.4),
    ),
  );
}

class DailyLogCard extends StatelessWidget {
  const DailyLogCard({super.key, required this.log, required this.onTap});
  final DailyLog? log;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final entry = log;
    final summary = entry == null
        ? 'Humor, sintomas e fluxo em um só lugar.'
        : [
            if (entry.mood != null) entry.mood!,
            if (entry.flow != null) 'Fluxo ${entry.flow!.toLowerCase()}',
            if (entry.symptoms.isNotEmpty) entry.symptoms.join(', '),
            if (entry.notes.isNotEmpty) entry.notes,
          ].join(' · ');
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: const Color(0xFFFFE2E6),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(Icons.favorite_rounded, color: coral),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry == null ? 'Registrar meu dia' : 'Registro de hoje',
                      style: const TextStyle(
                        color: ink,
                        fontWeight: FontWeight.w900,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      summary,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: muted,
                        fontSize: 12,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: muted),
            ],
          ),
        ),
      ),
    );
  }
}

class ReminderCard extends StatelessWidget {
  const ReminderCard({
    super.key,
    required this.enabled,
    required this.sharedMode,
    required this.onChanged,
  });
  final bool enabled;
  final bool sharedMode;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(18, 12, 12, 12),
    decoration: BoxDecoration(
      color: const Color(0xFFE1FAF5),
      borderRadius: BorderRadius.circular(22),
    ),
    child: Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: aqua,
            borderRadius: BorderRadius.circular(15),
          ),
          child: const Icon(Icons.notifications_active_rounded, color: ink),
        ),
        const SizedBox(width: 13),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Lembrete do ciclo',
                style: TextStyle(
                  color: ink,
                  fontWeight: FontWeight.w900,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                sharedMode
                    ? 'Aviso local na véspera da previsão dela, às 9h.'
                    : 'Aviso local na véspera da previsão, às 9h.',
                style: const TextStyle(color: muted, fontSize: 11, height: 1.3),
              ),
            ],
          ),
        ),
        Switch(value: enabled, activeTrackColor: violet, onChanged: onChanged),
      ],
    ),
  );
}

class DailyLogSheet extends StatefulWidget {
  const DailyLogSheet({
    super.key,
    required this.date,
    required this.initial,
    required this.sharedMode,
  });
  final DateTime date;
  final DailyLog? initial;
  final bool sharedMode;

  @override
  State<DailyLogSheet> createState() => _DailyLogSheetState();
}

class _DailyLogSheetState extends State<DailyLogSheet> {
  static const _moods = ['Bem', 'Tudo bem', 'Sensível', 'Cansada', 'Ansiosa'];
  static const _symptoms = [
    'Cólicas',
    'Dor de cabeça',
    'Cansaço',
    'Inchaço',
    'Acne',
    'Irritabilidade',
    'Sono ruim',
    'Energia baixa',
  ];
  late String? _mood = widget.initial?.mood;
  late String? _flow = widget.initial?.flow;
  late final Set<String> _selectedSymptoms = {...?widget.initial?.symptoms};
  late final TextEditingController _notes = TextEditingController(
    text: widget.initial?.notes ?? '',
  );

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  void _save() {
    final notes = _notes.text.trim();
    if (_mood == null &&
        _flow == null &&
        _selectedSymptoms.isEmpty &&
        notes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Escolha pelo menos um item para salvar.'),
        ),
      );
      return;
    }
    Navigator.of(context).pop(
      DailyLogEdit(
        DailyLog(
          mood: _mood,
          flow: _flow,
          symptoms: _selectedSymptoms.toList()..sort(),
          notes: notes,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Container(
    constraints: BoxConstraints(
      maxHeight: MediaQuery.sizeOf(context).height * .9,
    ),
    padding: EdgeInsets.fromLTRB(
      22,
      22,
      22,
      18 + MediaQuery.viewInsetsOf(context).bottom,
    ),
    decoration: const BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    child: SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFE7E3EF),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            widget.sharedMode ? 'O dia dela' : 'Seu dia',
            style: const TextStyle(
              color: ink,
              fontSize: 24,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          Text(_dateLabel(widget.date), style: const TextStyle(color: muted)),
          const SizedBox(height: 18),
          const Text(
            'Como está o humor?',
            style: TextStyle(color: ink, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 9),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final mood in _moods)
                ChoiceChip(
                  label: Text(mood),
                  selected: _mood == mood,
                  selectedColor: const Color(0xFFE9DFFF),
                  onSelected: (_) =>
                      setState(() => _mood = _mood == mood ? null : mood),
                ),
            ],
          ),
          const SizedBox(height: 14),
          const Text(
            'Fluxo menstrual',
            style: TextStyle(color: ink, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 9),
          Wrap(
            spacing: 8,
            children: [
              for (final flow in const ['Leve', 'Médio', 'Intenso'])
                ChoiceChip(
                  label: Text(flow),
                  selected: _flow == flow,
                  selectedColor: const Color(0xFFFFE2E6),
                  onSelected: (_) =>
                      setState(() => _flow = _flow == flow ? null : flow),
                ),
            ],
          ),
          const SizedBox(height: 14),
          const Text(
            'Sintomas',
            style: TextStyle(color: ink, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 7,
            runSpacing: 2,
            children: [
              for (final symptom in _symptoms)
                FilterChip(
                  label: Text(symptom),
                  selected: _selectedSymptoms.contains(symptom),
                  selectedColor: const Color(0xFFDDF9F4),
                  onSelected: (selected) => setState(
                    () => selected
                        ? _selectedSymptoms.add(symptom)
                        : _selectedSymptoms.remove(symptom),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _notes,
            maxLines: 2,
            maxLength: 180,
            decoration: InputDecoration(
              labelText: 'Observação (opcional)',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
          const SizedBox(height: 5),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _save,
              style: FilledButton.styleFrom(
                backgroundColor: violet,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: const Text(
                'Salvar registro',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ),
          if (widget.initial != null) ...[
            const SizedBox(height: 6),
            SizedBox(
              width: double.infinity,
              child: TextButton.icon(
                onPressed: () =>
                    Navigator.of(context).pop(const DailyLogEdit(null)),
                icon: const Icon(Icons.delete_outline_rounded),
                label: const Text('Apagar registro'),
              ),
            ),
          ],
        ],
      ),
    ),
  );
}

class CalendarPage extends StatefulWidget {
  const CalendarPage({
    super.key,
    required this.starts,
    required this.ends,
    required this.sharedMode,
    this.readOnly = false,
  });
  final List<DateTime> starts;
  final Map<DateTime, DateTime> ends;
  final bool sharedMode;
  final bool readOnly;

  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage> {
  DateTime _selected = DateUtils.dateOnly(DateTime.now());

  Future<void> _selectDate(DateTime date) async {
    setState(() => _selected = date);
    final isPeriodStart = widget.starts.contains(date);
    final periodStartForEnd = _periodStartForEndDate(
      date,
      widget.starts,
      widget.ends,
    );
    final isPeriodEnd =
        periodStartForEnd != null && widget.ends[periodStartForEnd] == date;
    final result = await showModalBottomSheet<CycleEdit>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => DateActionSheet(
        date: date,
        isPeriodStart: isPeriodStart,
        isPeriodEnd: isPeriodEnd,
        periodStartForEnd: periodStartForEnd,
        sharedMode: widget.sharedMode,
      ),
    );
    if (result != null && mounted) Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    return Scaffold(
      backgroundColor: canvas,
      appBar: AppBar(
        backgroundColor: canvas,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.arrow_back_rounded, color: ink),
        ),
        title: Text(
          widget.sharedMode ? 'Ciclo compartilhado' : 'Meu calendário',
          style: const TextStyle(color: ink, fontWeight: FontWeight.w900),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Row(
              children: [
                const LegendDot(color: coral, label: 'Menstruação'),
                const SizedBox(width: 14),
                const LegendDot(color: aqua, label: 'Janela fértil'),
                const SizedBox(width: 14),
                const LegendDot(color: lemon, label: 'Previsão'),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: WeekdayHeader(),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              itemCount: 9,
              itemBuilder: (context, index) {
                final month = DateTime(now.year, now.month - 2 + index, 1);
                return MonthCard(
                  month: month,
                  starts: widget.starts,
                  ends: widget.ends,
                  selected: _selected,
                  onSelect: widget.readOnly ? null : _selectDate,
                );
              },
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
            color: Colors.white,
            child: const Text(
              'Toque em um dia para marcar o início ou o fim. O contorno coral indica o fim registrado. Estimativas não são método contraceptivo nem orientação médica.',
              style: TextStyle(color: muted, fontSize: 11, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }
}

class WeekdayHeader extends StatelessWidget {
  const WeekdayHeader({super.key});
  @override
  Widget build(BuildContext context) => Row(
    children: [
      for (final day in const ['S', 'T', 'Q', 'Q', 'S', 'S', 'D'])
        Expanded(
          child: Center(
            child: Text(
              day,
              style: const TextStyle(
                color: muted,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
    ],
  );
}

class LegendDot extends StatelessWidget {
  const LegendDot({super.key, required this.color, required this.label});
  final Color color;
  final String label;
  @override
  Widget build(BuildContext context) => Expanded(
    child: Row(
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: muted,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    ),
  );
}

class MonthCard extends StatelessWidget {
  const MonthCard({
    super.key,
    required this.month,
    required this.starts,
    required this.ends,
    required this.selected,
    required this.onSelect,
  });
  final DateTime month;
  final List<DateTime> starts;
  final Map<DateTime, DateTime> ends;
  final DateTime selected;
  final ValueChanged<DateTime>? onSelect;

  @override
  Widget build(BuildContext context) {
    final offset = (month.weekday + 6) % 7;
    final count = DateTime(month.year, month.month + 1, 0).day;
    final cells = ((offset + count + 6) ~/ 7) * 7;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 8, bottom: 10),
            child: Text(
              '${_monthName(month.month)} ${month.year}',
              style: const TextStyle(
                color: ink,
                fontSize: 19,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: cells,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              mainAxisExtent: 50,
            ),
            itemBuilder: (context, index) {
              final day = index - offset + 1;
              if (day < 1 || day > count) return const SizedBox.shrink();
              final date = DateUtils.dateOnly(
                DateTime(month.year, month.month, day),
              );
              final stage = _stageFor(date, starts, ends);
              final isPeriodEnd = ends.values.contains(date);
              final isSelected = date == selected;
              final isToday = date == DateUtils.dateOnly(DateTime.now());
              final background = isSelected
                  ? ink
                  : stage == CycleStage.period && !isPeriodEnd
                  ? coral
                  : stage == CycleStage.fertile
                  ? const Color(0xFFDDF9F4)
                  : stage == CycleStage.predicted
                  ? const Color(0xFFFFF3C4)
                  : Colors.transparent;
              final foreground =
                  isSelected || (stage == CycleStage.period && !isPeriodEnd)
                  ? Colors.white
                  : isPeriodEnd
                  ? coral
                  : ink;
              return Center(
                child: InkWell(
                  onTap: onSelect == null ? null : () => onSelect!(date),
                  customBorder: const CircleBorder(),
                  child: SizedBox(
                    width: 42,
                    height: 42,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: background,
                        shape: BoxShape.circle,
                        border: isPeriodEnd
                            ? Border.all(color: coral, width: 2)
                            : isToday && !isSelected
                            ? Border.all(color: violet, width: 1.5)
                            : null,
                      ),
                      child: Center(
                        child: Text(
                          '$day',
                          style: TextStyle(
                            color: foreground,
                            fontSize: 14,
                            fontWeight: isToday || isSelected
                                ? FontWeight.w900
                                : FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class DateActionSheet extends StatelessWidget {
  const DateActionSheet({
    super.key,
    required this.date,
    required this.isPeriodStart,
    required this.isPeriodEnd,
    required this.periodStartForEnd,
    required this.sharedMode,
  });
  final DateTime date;
  final bool isPeriodStart;
  final bool isPeriodEnd;
  final DateTime? periodStartForEnd;
  final bool sharedMode;

  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.fromLTRB(
      22,
      24,
      22,
      22 + MediaQuery.viewInsetsOf(context).bottom,
    ),
    decoration: const BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(
          child: Container(
            width: 38,
            height: 4,
            decoration: BoxDecoration(
              color: const Color(0xFFE7E3EF),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ),
        const SizedBox(height: 20),
        Text(
          _dateLabel(date),
          style: const TextStyle(
            color: ink,
            fontSize: 24,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          isPeriodStart
              ? 'Início da menstruação registrado.'
              : 'Você pode marcar esta data como início${sharedMode ? ' dela' : ''} da menstruação.',
          style: const TextStyle(color: muted, height: 1.4),
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: () =>
                Navigator.of(context)
                    .pop(CycleEdit.start(date, !isPeriodStart)),
            style: FilledButton.styleFrom(
              backgroundColor: isPeriodStart ? coral : violet,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 15),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            icon: Icon(
              isPeriodStart ? Icons.delete_outline_rounded : Icons.add_rounded,
            ),
            label: Text(
              isPeriodStart ? 'Remover início' : 'Marcar início da menstruação',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          isPeriodEnd
              ? 'Fim registrado para o ciclo iniciado em ${_dateLabel(periodStartForEnd!)}.'
              : periodStartForEnd == null
              ? 'Para marcar o fim, registre primeiro o início desta menstruação.'
              : 'Registre o último dia de fluxo do ciclo iniciado em ${_dateLabel(periodStartForEnd!)}.',
          style: const TextStyle(color: muted, fontSize: 12, height: 1.35),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: periodStartForEnd == null
                ? null
                : () => Navigator.of(
                    context,
                  ).pop(CycleEdit.end(date, periodStartForEnd, !isPeriodEnd)),
            style: OutlinedButton.styleFrom(
              foregroundColor: coral,
              side: BorderSide(color: coral.withValues(alpha: .55)),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            icon: Icon(
              isPeriodEnd
                  ? Icons.remove_circle_outline_rounded
                  : Icons.flag_rounded,
            ),
            label: Text(
              isPeriodEnd ? 'Remover data do fim' : 'Marcar fim da menstruação',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ),
      ],
    ),
  );
}

class DailyLog {
  const DailyLog({
    required this.mood,
    required this.flow,
    required this.symptoms,
    required this.notes,
  });
  final String? mood;
  final String? flow;
  final List<String> symptoms;
  final String notes;

  Map<String, dynamic> toJson() => {
    'mood': mood,
    'flow': flow,
    'symptoms': symptoms,
    'notes': notes,
  };

  factory DailyLog.fromJson(Map<String, dynamic> json) => DailyLog(
    mood: json['mood'] as String?,
    flow: json['flow'] as String?,
    symptoms: (json['symptoms'] as List<dynamic>? ?? [])
        .whereType<String>()
        .toList(),
    notes: json['notes'] as String? ?? '',
  );
}

class DailyLogEdit {
  const DailyLogEdit(this.log);
  final DailyLog? log;
}

Map<String, DailyLog> _parseLogs(dynamic raw) {
  if (raw is! Map) return {};
  final logs = <String, DailyLog>{};
  for (final entry in raw.entries) {
    if (entry.value is Map) {
      logs[entry.key.toString()] = DailyLog.fromJson(
        Map<String, dynamic>.from(entry.value as Map),
      );
    }
  }
  return logs;
}

Map<String, dynamic> _serializeLogs(Map<String, DailyLog> logs) =>
    logs.map((key, value) => MapEntry(key, value.toJson()));

String _dateKey(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

class CycleEdit {
  const CycleEdit.start(this.date, this.add) : startDateForEnd = null;
  const CycleEdit.end(this.date, this.startDateForEnd, this.add);

  final DateTime date;
  final DateTime? startDateForEnd;
  final bool add;
}

DateTime? _periodStartForEndDate(
  DateTime date,
  List<DateTime> starts,
  Map<DateTime, DateTime> ends,
) {
  for (final entry in ends.entries) {
    if (entry.value == date) return entry.key;
  }
  final candidates =
      starts
          .where(
            (start) =>
                !start.isAfter(date) && date.difference(start).inDays <= 14,
          )
          .toList()
        ..sort((a, b) => b.compareTo(a));
  return candidates.isEmpty ? null : candidates.first;
}

Map<String, String> _serializeEndDates(Map<DateTime, DateTime> ends) => {
  for (final entry in ends.entries)
    entry.key.toIso8601String(): entry.value.toIso8601String(),
};

enum CycleStage { none, period, fertile, predicted }

CycleStage _stageFor(
  DateTime date,
  List<DateTime> starts,
  Map<DateTime, DateTime> ends,
) {
  final day = DateUtils.dateOnly(date);
  for (final start in starts) {
    final end = ends[start] ?? start.add(const Duration(days: 4));
    if (!day.isBefore(start) && !day.isAfter(end)) return CycleStage.period;
  }
  if (starts.isEmpty) return CycleStage.none;
  var next = starts.last.add(const Duration(days: 28));
  final today = DateUtils.dateOnly(DateTime.now());
  while (next.isBefore(today)) {
    next = next.add(const Duration(days: 28));
  }
  if (day.isAtSameMomentAs(next) ||
      (day.isAfter(next) && day.difference(next).inDays < 5)) {
    return CycleStage.predicted;
  }
  final ovulation = next.subtract(const Duration(days: 14));
  final fertileStart = ovulation.subtract(const Duration(days: 5));
  final fertileEnd = ovulation.add(const Duration(days: 1));
  if (!day.isBefore(fertileStart) && !day.isAfter(fertileEnd)) {
    return CycleStage.fertile;
  }
  return CycleStage.none;
}

String _monthName(int month) =>
    const {
      1: 'Janeiro',
      2: 'Fevereiro',
      3: 'Março',
      4: 'Abril',
      5: 'Maio',
      6: 'Junho',
      7: 'Julho',
      8: 'Agosto',
      9: 'Setembro',
      10: 'Outubro',
      11: 'Novembro',
      12: 'Dezembro',
    }[month] ??
    '';

String _weekdayShort(int weekday) =>
    const {1: 'S', 2: 'T', 3: 'Q', 4: 'Q', 5: 'S', 6: 'S', 7: 'D'}[weekday] ??
    '';

String _shortDate(DateTime date) =>
    '${date.day.toString().padLeft(2, '0')} ${_monthName(date.month).substring(0, 3).toLowerCase()}';

String _dateLabel(DateTime date) =>
    '${date.day} de ${_monthName(date.month).toLowerCase()}';
