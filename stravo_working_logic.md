# Stravo Working Logic Reference

This file documents the working architecture and integration details for **Stravo** stream playback in Private Cinema.

## 1. Stream Discovery (Scraper / Addon integration)
Stravo streams are retrieved from a Stremio-compatible addon server (configured in user preferences, defaults to `https://stravo-clfk.onrender.com/default`).

The app builds a request URL using the movie's IMDB ID:
```
[ADDON_BASE_URL]/stream/movie/[IMDB_ID].json
```
For example:
`https://stravo-clfk.onrender.com/default/stream/movie/tt1234567.json`

### Payload Structure
The addon returns a JSON list of streams:
```json
{
  "streams": [
    {
      "name": "Stravo [1080p]",
      "title": "Movie Name\n1080p | High Speed",
      "url": "https://stravo.fayallc.workers.dev/proxy/stream?access=..."
    }
  ]
}
```

---

## 2. Stream Resolution & Direct Native Playback
In modern builds, Stravo streams play **directly and natively** inside the `media_kit` (libmpv) player without routing through the local DNS proxy.

### Player Configuration
To bypass ISP limitations and certificate expiration blocks on older devices:
1. **Disable SSL Verification**: Set native player property `tls-verify` to `'no'`.
2. **Force IPv4**: Set native player property `dns-lookup-family` to `'ipv4'`.
3. **Pass Custom Headers**: Set `http-header-fields` on the native player with any required headers.

### Exemption from Local DNS Proxy
Stravo domains (`fayallc`, `workers.dev`) bypass the global proxy settings (`HttpOverrides`) and connect natively (`DIRECT`), which avoids connection resets.
