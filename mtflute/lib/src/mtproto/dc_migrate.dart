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
    if (cachedKey != null) {
      // Try reusing the persisted key.  Telegram may have invalidated it
      // (AUTH_KEY_UNREGISTERED / code 401) if the session was idle or was
      // never fully registered with importAuthorization on a prior run.
      final sub = _makeWorker(targetDcId);
      try {
        sub.seedAuthKey(cachedKey);
        await sub.connect();
        // Probe with a lightweight call that requires an authenticated session.
        await sub.invoke(UpdatesGetStateRequest());
        return sub;
      } on TgError catch (e) {
        try { await sub.close(); } catch (_) {}
        if (e.code == 401 || e.matches('AUTH_KEY_UNREGISTERED')) {
          // Stale key — wipe it and fall through to full export/import below.
          recordDcKey(targetDcId, null);
        } else {
          rethrow;
        }
      } catch (e) {
        try { await sub.close(); } catch (_) {}
        rethrow;
      }
    }

    // Full export/import authorization flow (no cached key, or cached key was stale).
    final sub = _makeWorker(targetDcId);
    try {
      await sub.connect();

      final exported = await invoke(
        AuthExportAuthorizationRequest(dcId: targetDcId),
      );
      final eAuth = exported as AuthExportedAuthorizationObj;

      await sub.invoke(
        AuthImportAuthorizationRequest(id: eAuth.id, bytes: eAuth.bytes),
      );

      recordDcKey(targetDcId, sub.authKeyBytes);
      return sub;
    } catch (e) {
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
