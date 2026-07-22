# VidLink Working Logic Reference

This file documents the working architecture, IP-locking bypass, and API proxy details for **VidLink** stream playback in Private Cinema.

## 1. Stream Identification & Discovery
The mobile app generates a VidLink source if a valid IMDB ID (or TMDB ID) is available for the selected movie:
```
https://[SCRAPER_DOMAIN]/api?id=[ACTIVE_ID]
```
* **Production Domain**: `https://movie-scraper-j6k1jkfy1-kinguser98s-projects.vercel.app`
* **API Route**: `/api?id=[IMDB_ID_OR_TMDB_ID]` (for movie) or `/api?id=[TMDB_ID]&s=[SEASON]&e=[EPISODE]` (for TV series).

---

## 2. API Resolution & The IP-Locking Challenge
1. The app requests the scraper API, which uses WebAssembly-based client decryption (`fu.wasm` / `script.js` / libsodium) to fetch the stream details from `vidlink.pro`.
2. The scraper returns a JSON response containing the raw HLS playlist (`.m3u8`) URL hosted on VidLink's CDN networks (e.g., `hls.shegu.net`, `storm.vodvidl.site`, `vod2.ironwallnet.com`):
   ```json
   {
     "url": "https://hls.shegu.net/38214555.m3u8?sign=CRsne9sXjEuphBDocmDh2A&t=1782669781&KEY7=web_player..."
   }
   ```
3. **The Challenge**: The CDN tokens (`sign`, `auth`) are strictly **IP-locked** to the specific IP address that queried the API (the Vercel deployment IP). If the mobile app or any external media player (like VLC) tries to fetch this URL directly, the CDN will reject the request and return a `403 Forbidden` response.

---

## 3. Server-Side HLS Proxy Routing
To bypass the IP lock, the app routes video playback through the scraper's server-side proxy endpoint rather than playing the raw CDN URL:

```
https://[SCRAPER_DOMAIN]/api?url=[URL_ENCODED_RAW_URL]
```

### How the Proxy Works:
1. **Server-Side Fetch**: The Vercel server fetches the `.m3u8` playlist from the CDN. Since the request comes from the Vercel server's authorized IP address, the CDN returns a `200 OK` with the playlist content.
2. **Referer & Origin Injection**: The server-side proxy always injects:
   * `Referer: https://vidlink.pro/`
   * `Origin: https://vidlink.pro`
   * `User-Agent: Mozilla/5.0 ...`
3. **Playlist Rewriting**: The proxy parses the fetched `.m3u8` playlist and rewrites every internal segment / TS chunk URL (absolute or relative) to point back to the proxy:
   ```
   https://[SCRAPER_DOMAIN]/api?url=[ENCODED_TS_CHUNK_URL]
   ```
4. **Segment Streaming**: When the mobile player requests a segment, the Vercel proxy fetches the segment from the CDN using its authorized IP and streams the bytes back to the mobile player.

---

## 4. Local DNS Proxy Guardrail (dns_proxy.dart)
As an extra layer of defense, the mobile app's local DNS proxy (`dns_proxy.dart`) intercepts any request originating from the player to VidLink CDN hostnames (`vodvidl.site`, `ironwallnet.com`) and dynamically injects the appropriate headers:
* `Referer: https://vidlink.pro/`
* `Origin: https://vidlink.pro`
* Enforces Chrome `User-Agent`.
