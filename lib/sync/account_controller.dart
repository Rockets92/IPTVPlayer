import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/form_factor.dart';
import 'supabase_sync_backend.dart';
import 'sync_engine.dart';

/// A che punto è l'accesso.
enum AccountStage {
  /// Nessun account: l'app funziona come sempre, solo in locale.
  signedOut,

  /// Email inserita, si aspetta il codice di 6 cifre.
  codeSent,

  /// Dentro: promemoria e preferenze seguono l'account.
  signedIn,
}

/// Un dispositivo collegato all'account.
@immutable
class AccountDevice {
  const AccountDevice({
    required this.id,
    required this.name,
    required this.kind,
    required this.lastSeen,
    required this.isThis,
  });

  final String id;
  final String name;
  final String kind;
  final DateTime lastSeen;

  /// È il dispositivo in uso adesso.
  final bool isThis;
}

/// Accesso con email e codice (niente password) e collegamento del
/// dispositivo all'account. A login fatto avvia la sincronizzazione.
class AccountController extends ChangeNotifier {
  AccountController({
    required this.client,
    required this.prefs,
    required this.formFactor,
    required this.engineFor,
  }) {
    final c = client;
    if (c == null) return;
    _authSub = c.auth.onAuthStateChange.listen((s) {
      if (s.event == AuthChangeEvent.signedOut &&
          stage == AccountStage.signedIn) {
        unawaited(_afterSignOut());
      }
    }, onError: (Object _) {});
  }

  /// null se il servizio non è disponibile (es. inizializzazione fallita).
  final SupabaseClient? client;
  final SharedPreferences prefs;
  final FormFactor formFactor;

  /// Costruisce il motore di sincronizzazione per l'account.
  final SyncEngine Function(SupabaseSyncBackend backend) engineFor;

  static const _kDeviceId = 'account.deviceId';

  StreamSubscription<AuthState>? _authSub;
  SyncEngine? engine;

  AccountStage stage = AccountStage.signedOut;
  bool busy = false;
  String? error;

  /// Email in attesa del codice.
  String? pendingEmail;

  bool get available => client != null;
  String? get email => client?.auth.currentUser?.email;
  String? get deviceId => prefs.getString(_kDeviceId);

  /// All'avvio: se c'è una sessione salvata si riparte da lì.
  Future<void> start() async {
    final c = client;
    if (c == null || c.auth.currentSession == null) return;
    stage = AccountStage.signedIn;
    notifyListeners();
    await _onSignedIn(fresh: false);
  }

  /// Manda il codice all'email (l'account nasce al primo accesso).
  Future<bool> sendCode(String email) async {
    final e = email.trim().toLowerCase();
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(e)) {
      error = 'Indirizzo email non valido';
      notifyListeners();
      return false;
    }
    return _run(() async {
      await client!.auth.signInWithOtp(email: e, shouldCreateUser: true);
      pendingEmail = e;
      stage = AccountStage.codeSent;
    });
  }

  /// Verifica il codice ricevuto per email.
  Future<bool> verifyCode(String code) async {
    final e = pendingEmail;
    final t = code.replaceAll(RegExp(r'\s'), '');
    if (e == null) return false;
    if (!RegExp(r'^\d{6,10}$').hasMatch(t)) {
      error = 'Il codice è fatto di sole cifre';
      notifyListeners();
      return false;
    }
    final ok = await _run(() async {
      await client!.auth.verifyOTP(email: e, token: t, type: OtpType.email);
      pendingEmail = null;
      stage = AccountStage.signedIn;
    });
    if (ok) await _onSignedIn(fresh: true);
    return ok;
  }

  /// Annulla l'attesa del codice.
  void cancelCode() {
    pendingEmail = null;
    error = null;
    if (stage == AccountStage.codeSent) stage = AccountStage.signedOut;
    notifyListeners();
  }

  Future<void> signOut() async {
    final c = client;
    if (c == null) return;
    final id = deviceId;
    try {
      if (id != null) await c.from('devices').delete().eq('id', id);
    } catch (_) {}
    try {
      await c.auth.signOut();
    } catch (_) {}
    await _afterSignOut();
  }

  Future<void> _afterSignOut() async {
    await engine?.reset();
    engine?.dispose();
    engine = null;
    await prefs.remove(_kDeviceId);
    stage = AccountStage.signedOut;
    notifyListeners();
  }

  /// Dispositivi collegati, dal più recente.
  Future<List<AccountDevice>> devices() async {
    final c = client;
    if (c == null || stage != AccountStage.signedIn) return const [];
    final rows = await c
        .from('devices')
        .select()
        .order('last_seen', ascending: false);
    final me = deviceId;
    return [
      for (final r in rows)
        AccountDevice(
          id: '${r['id']}',
          name: '${r['name']}',
          kind: '${r['kind']}',
          lastSeen:
              DateTime.tryParse('${r['last_seen']}')?.toLocal() ??
              DateTime.now(),
          isThis: r['id'] == me,
        ),
    ];
  }

  /// Scollega un altro dispositivo: alla prossima apertura esce dall'account.
  Future<void> removeDevice(String id) async {
    if (id == deviceId) return signOut();
    await client?.from('devices').delete().eq('id', id);
  }

  Future<void> syncNow() async => engine?.syncNow();

  Future<void> _onSignedIn({required bool fresh}) async {
    final c = client!;
    try {
      final still = await _registerDevice(c, fresh: fresh);
      if (!still) {
        // Scollegato da un altro dispositivo.
        error = 'Questo dispositivo è stato scollegato dall\'account';
        await signOut();
        return;
      }
    } catch (e) {
      // Senza rete si va avanti: la sincronizzazione riproverà.
      debugPrint('account: $e');
    }
    engine ??= engineFor(SupabaseSyncBackend(c));
    await engine!.start();
    notifyListeners();
  }

  /// Registra (o aggiorna) questo dispositivo. false se era stato tolto
  /// dall'account da un altro dispositivo.
  Future<bool> _registerDevice(SupabaseClient c, {required bool fresh}) async {
    final row = {
      'name': deviceName,
      'kind': formFactor.name,
      'platform': kIsWeb ? 'web' : Platform.operatingSystem,
      'last_seen': DateTime.now().toUtc().toIso8601String(),
    };
    final id = deviceId;
    if (id != null) {
      final updated = await c
          .from('devices')
          .update(row)
          .eq('id', id)
          .select('id');
      if (updated.isNotEmpty) return true;
      if (!fresh) return false;
    }
    final created = await c.from('devices').insert(row).select('id').single();
    await prefs.setString(_kDeviceId, '${created['id']}');
    return true;
  }

  /// Nome leggibile del dispositivo, es. "PC Windows (STUDIO)".
  String get deviceName {
    final kind = switch (formFactor) {
      FormFactor.tv => 'TV',
      FormFactor.phone => 'Telefono',
      FormFactor.tablet => 'Tablet',
      FormFactor.desktop => 'PC',
    };
    if (kIsWeb) return '$kind web';
    final os = switch (Platform.operatingSystem) {
      'windows' => 'Windows',
      'macos' => 'Mac',
      'linux' => 'Linux',
      'android' => 'Android',
      'ios' => 'iOS',
      final o => o,
    };
    var host = '';
    if (formFactor == FormFactor.desktop) {
      try {
        host = Platform.localHostname;
      } catch (_) {}
    }
    return host.isEmpty ? '$kind $os' : '$kind $os ($host)';
  }

  Future<bool> _run(Future<void> Function() f) async {
    if (client == null) {
      error = 'Servizio account non disponibile';
      notifyListeners();
      return false;
    }
    busy = true;
    error = null;
    notifyListeners();
    try {
      await f();
      return true;
    } on AuthException catch (e) {
      error = _authMessage(e);
      return false;
    } catch (_) {
      error = 'Connessione non riuscita: riprova';
      return false;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  static String _authMessage(AuthException e) {
    final m = e.message.toLowerCase();
    if (m.contains('expired') || m.contains('invalid')) {
      return 'Codice sbagliato o scaduto';
    }
    if (m.contains('rate') || e.statusCode == '429') {
      return 'Troppi tentativi: aspetta un minuto e riprova';
    }
    return 'Accesso non riuscito: ${e.message}';
  }

  @override
  void dispose() {
    unawaited(_authSub?.cancel());
    engine?.dispose();
    super.dispose();
  }
}
