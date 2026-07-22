import '../tg/tg.dart';
import 'client.dart';
import 'errors.dart';

extension DcMigration on MtpClient {
  Future<MtpClient> exportToDc(int targetDcId) async {
    if (targetDcId == dcId) {
      final sub = _makeWorker(targetDcId);
      try {
        sub.copyAuthFrom(this);
        await sub.connect();
        return sub;
      } catch (e) {
        try { await sub.close(); } catch (_) {}
        rethrow;
      }
    }

    final cachedKey = persistedKeyFor(targetDcId);
    print('[DC_MIGRATE] exportToDc($targetDcId): cachedKey=${cachedKey != null ? "present(${cachedKey.length}b)" : "null"}');
    if (cachedKey != null) {
      // Try reusing the persisted key.  Telegram may have invalidated it
      // (AUTH_KEY_UNREGISTERED / code 401) if the session was idle or was
      // never fully registered with importAuthorization on a prior run.
      // ANY error during the probe (network, socket, auth) means this cached
      // key is unusable — wipe it and fall through to full export/import.
      final sub = _makeWorker(targetDcId);
      try {
        sub.seedAuthKey(cachedKey);
        print('[DC_MIGRATE] exportToDc($targetDcId): connecting with cached key...');
        await sub.connect();
        print('[DC_MIGRATE] exportToDc($targetDcId): probing cached key with UpdatesGetState...');
        // Probe with a lightweight call that requires an authenticated session.
        await sub.invoke(UpdatesGetStateRequest());
        print('[DC_MIGRATE] exportToDc($targetDcId): cached key OK, returning sub');
        return sub;
      } on TgError catch (e) {
        try { await sub.close(); } catch (_) {}
        print('[DC_MIGRATE] exportToDc($targetDcId): cached key probe TgError: $e — wiping key and falling through');
        // Wipe the bad key regardless of error type, then fall through.
        recordDcKey(targetDcId, null);
        // Only rethrow TgErrors that are clearly not auth-related (e.g. FLOOD_WAIT).
        // AUTH_KEY_UNREGISTERED, 401, etc. should fall through to re-export.
        if (!e.matches('AUTH_KEY_UNREGISTERED') && e.code != 401) {
          rethrow;
        }
      } catch (e) {
        // Network error (SocketException, TimeoutException, StateError, etc.)
        // during connect or probe — wipe the bad key and fall through to full
        // export/import. Do NOT rethrow: the full path may succeed on a fresh connection.
        try { await sub.close(); } catch (_) {}
        print('[DC_MIGRATE] exportToDc($targetDcId): cached key probe error (non-TgError): $e — wiping key and falling through');
        recordDcKey(targetDcId, null);
      }
    }

    // Full export/import authorization flow (no cached key, or cached key was stale).
    print('[DC_MIGRATE] exportToDc($targetDcId): starting full export/import...');
    final sub = _makeWorker(targetDcId);
    try {
      print('[DC_MIGRATE] exportToDc($targetDcId): sub.connect()...');
      await sub.connect();
      print('[DC_MIGRATE] exportToDc($targetDcId): AuthExportAuthorizationRequest...');
      final exported = await invoke(
        AuthExportAuthorizationRequest(dcId: targetDcId),
      );
      print('[DC_MIGRATE] exportToDc($targetDcId): export OK, importing...');
      final eAuth = exported as AuthExportedAuthorizationObj;

      await sub.invoke(
        AuthImportAuthorizationRequest(id: eAuth.id, bytes: eAuth.bytes),
      );

      print('[DC_MIGRATE] exportToDc($targetDcId): import OK, sub ready');
      recordDcKey(targetDcId, sub.authKeyBytes);
      return sub;
    } catch (e) {
      print('[DC_MIGRATE] exportToDc($targetDcId): full export/import FAILED: $e');
      try { await sub.close(); } catch (_) {}
      rethrow;
    }
  }


  MtpClient _makeWorker(int targetDcId) {
    final sub = MtpClient(
      appId: appId,
      appHash: appHash,
      dcId: targetDcId,
      ipv6: ipv6,
      timeout: timeout,
      sessionFile: null,
      proxy: proxy,
    );
    sub.workerMode = true;
    sub.logger.level = logger.level;
    sub.logger.prefix = '${logger.prefix}:sub';
    return sub;
  }
}
