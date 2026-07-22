# Streamtape Working Logic Reference

This file documents the working architecture, connection bypass, and API integration details for **Streamtape** stream playback in Private Cinema.

## 1. Stream Identification
Streamtape links are identified dynamically in the app based on:
1. URL containing `streamtape.com` or `strcloud.club`.
2. Source/Server name containing `streamtape` or `strcloud`.

---

## 2. API Resolution Flow
To play a Streamtape video natively, the app must resolve the embed/page URL to a direct streaming URL using Streamtape's developer API:

1. **Step 1: Download Ticket Request**
   ```
   GET https://[API_DOMAIN]/file/dlticket?file=[FILE_ID]&login=[LOGIN_ID]&key=[API_KEY]
   ```
   * Returns a JSON object containing a `ticket` string and a `wait_time` (usually 5 seconds).

2. **Step 2: Wait Period**
   * The app delays execution by the specified `wait_time` (e.g., 5 seconds).

3. **Step 3: Direct Link Request**
   * The app requests the direct file link using the ticket:
   ```
   GET https://[API_DOMAIN]/file/dl?file=[FILE_ID]&ticket=[TICKET]
   ```
   * Returns a JSON object containing the direct streaming URL (`result.url`).

---

## 3. ISP / Carrier SNI Bypass Implementation
On cellular and broadband networks where the ISP resets secure TLS handshakes (SNI firewalls) for Streamtape API domains, the app uses two critical techniques to ensure 100% success:

### A. Connection Close Enforcement
* The HTTP client explicitly sets the `'Connection': 'close'` header on all API calls. This prevents reuse of TCP sockets where the firewall has injected RST packets.

### B. Fallback Domain Rotation & Retry Engine
* The app attempts resolution across a fallback array of domains:
  1. `api.strcloud.club`
  2. `api.streamtape.com`
  3. `api.streamtape.to`
  4. `api.streamtape.net`
* If a domain fetch fails due to a `SocketException` (connection reset by peer), the app retries up to **3 times** with a **500ms delay** before moving to the next domain.

---

## 4. Direct Playback
* Once resolved, the streaming URL (`*.tapecontent.net`) bypasses the local proxy and plays **directly and natively** inside the player.
