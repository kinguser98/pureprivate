#!/usr/bin/env python3
"""Fix Penguplay fallback: add else branch to call _resolveStremioAddons with tmdbId when imdbId is unavailable."""

FILE = 'special_search_dialog.dart'

with open(FILE, 'r', encoding='utf-8') as f:
    content = f.read()

# The pattern: the IMDb guard block ends with the Stremio addon call, then closes with }
# We need to add an else branch after that closing }
old_block = """      // Resolve synced custom Stremio addons
      if (_showStremioAddon) {
        tasks.add(_resolveStremioAddons(imdbId, season: season, episode: episode));
      }
    }"""

new_block = """      // Resolve synced custom Stremio addons
      if (_showStremioAddon) {
        tasks.add(_resolveStremioAddons(imdbId, season: season, episode: episode));
      }
    } else {
      // Fallback: try Stremio addons with TMDB ID when IMDB ID is unavailable (regional films)
      if (_showStremioAddon) {
        tasks.add(_resolveStremioAddons(tmdbId, season: season, episode: episode));
      }
    }"""

if old_block in content:
    content = content.replace(old_block, new_block, 1)
    print("Penguplay fallback added: _resolveStremioAddons now called with tmdbId when imdbId is unavailable")
else:
    print("ERROR: Pattern not found")

with open(FILE, 'w', encoding='utf-8') as f:
    f.write(content)
