import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import '../../providers/movie_provider.dart';
import '../../utils/admin_api_client.dart';
import '../../utils/drawer_helper.dart';
import '../../utils/tmdb_service.dart';
import '../../../widgets/image_picker_gallery_dialog.dart';

class AddMovieScreen extends ConsumerStatefulWidget {
  const AddMovieScreen({super.key});
  @override
  ConsumerState<AddMovieScreen> createState() => _AddMovieScreenState();
}

class _AddMovieScreenState extends ConsumerState<AddMovieScreen> {
  final _adminApi = AdminApiClient();
  final _formKey = GlobalKey<FormState>();

  // TMDB
  final _tmdbSearchCtrl = TextEditingController();
  List<TmdbMovie> _tmdbSuggestions = [];
  bool _isSearchingTMDB = false;
  Timer? _debounce;

  // Fields
  final _titleCtrl = TextEditingController();
  final _genreCtrl = TextEditingController();
  final _imdbCtrl = TextEditingController();
  final _tmdbCtrl = TextEditingController();
  final _overviewCtrl = TextEditingController();
  final _castCtrl = TextEditingController();
  final _castPhotosCtrl = TextEditingController();
  final _directorCtrl = TextEditingController();
  final _directorPhotoCtrl = TextEditingController();
  final _releaseCtrl = TextEditingController();
  final _runtimeCtrl = TextEditingController();
  final _trailerCtrl = TextEditingController();
  final _posterCtrl = TextEditingController();
  final _backdropCtrl = TextEditingController();

  int? _languageId;
  int? _ottId;
  String _quality = '1080p';
  DateTime? _ingestionDate;

  // Live preview
  String? _posterPreviewUrl;
  String? _backdropPreviewUrl;

  // Stream sources
  final List<_StreamSource> _streamSources = [];
  int _sourceIdCounter = 0;

  // Dropdown data
  List<Map<String, dynamic>> _languages = [];
  List<Map<String, dynamic>> _ottProviders = [];
  bool _loadingDropdowns = true;
  bool _isSaving = false;

  final List<String> _sourceTypes = ['mp4/mkv', 'Streamtape', 'YouTube', 'VidLink', 'Embed', 'Torrent (Magnet)', 'Stalker VOD'];

  @override
  void initState() {
    super.initState();
    _ingestionDate = DateTime.now();
    _addStreamSource();
    _loadDropdowns();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _tmdbSearchCtrl.dispose();
    _titleCtrl.dispose();
    _genreCtrl.dispose();
    _imdbCtrl.dispose();
    _tmdbCtrl.dispose();
    _overviewCtrl.dispose();
    _castCtrl.dispose();
    _castPhotosCtrl.dispose();
    _directorCtrl.dispose();
    _directorPhotoCtrl.dispose();
    _releaseCtrl.dispose();
    _runtimeCtrl.dispose();
    _trailerCtrl.dispose();
    _posterCtrl.dispose();
    _backdropCtrl.dispose();
    for (final s in _streamSources) { s.nameCtrl.dispose(); s.urlCtrl.dispose(); }
    super.dispose();
  }

  Future<void> _loadDropdowns() async {
    try {
      final langs = await _adminApi.getLanguages();
      final otts = await _adminApi.getOttProviders();
      if (mounted) {
        setState(() {
          _languages = langs;
          _ottProviders = otts;
          _loadingDropdowns = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingDropdowns = false);
    }
  }

  void _onTmdbSearchChanged(String query) {
    _debounce?.cancel();
    if (query.isEmpty) {
      setState(() { _tmdbSuggestions = []; _isSearchingTMDB = false; });
      return;
    }
    if (RegExp(r'^\d+$').hasMatch(query)) return;
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      setState(() => _isSearchingTMDB = true);
      final results = await TmdbService.search(query);
      if (mounted) setState(() { _tmdbSuggestions = results; _isSearchingTMDB = false; });
    });
  }

  Future<void> _selectTmdbMovie(int movieId) async {
    setState(() => _isSearchingTMDB = true);
    final details = await TmdbService.getDetails(movieId);
    if (details != null && mounted) {
      setState(() {
        _tmdbSearchCtrl.text = details.title;
        _tmdbSuggestions = [];
        _isSearchingTMDB = false;
        _titleCtrl.text = details.title;
        _tmdbCtrl.text = details.id.toString();
        _imdbCtrl.text = details.imdbId ?? '';
        _overviewCtrl.text = details.overview;
        _genreCtrl.text = details.genres.join(', ');
        _releaseCtrl.text = details.releaseDate ?? '';
        _runtimeCtrl.text = details.runtime?.toString() ?? '';
        _castCtrl.text = details.cast.map((c) => c.name).join(', ');
        _castPhotosCtrl.text = details.cast.where((c) => c.photoPath != null).map((c) => c.photoPath!).join(', ');
        _directorCtrl.text = details.director ?? '';
        _directorPhotoCtrl.text = details.directorPhoto ?? '';
        _posterCtrl.text = details.posterPath ?? '';
        _backdropCtrl.text = details.backdropPath ?? '';
        _posterPreviewUrl = details.posterPath;
        _backdropPreviewUrl = details.backdropPath;
        if (details.trailerKey != null) _trailerCtrl.text = 'https://www.youtube.com/watch?v=${details.trailerKey}';
      });
    } else if (mounted) {
      setState(() { _isSearchingTMDB = false; _tmdbSuggestions = []; });
    }
  }

  void _addStreamSource({String name = 'mp4/mkv', String url = ''}) {
    setState(() {
      _streamSources.add(_StreamSource(
        id: _sourceIdCounter++,
        nameCtrl: TextEditingController(text: name),
        urlCtrl: TextEditingController(text: url),
      ));
    });
  }

  void _removeStreamSource(int id) {
    setState(() => _streamSources.removeWhere((s) => s.id == id));
  }

  Future<void> _testSourceHealth(int id) async {
    final source = _streamSources.firstWhere((s) => s.id == id);
    setState(() => source.isTesting = true);
    try {
      final url = source.urlCtrl.text.trim();
      if (url.isEmpty) { source.status = 'No URL'; source.isTesting = false; return; }
      // Check YouTube
      if (url.contains('youtube.com') || url.contains('youtu.be')) {
        try {
          final res = await http.head(Uri.parse(url));
          source.status = res.statusCode < 400 ? 'Active' : 'Broken';
        } catch (_) { source.status = 'Broken'; }
      }
      // Check direct URL
      else if (url.startsWith('http')) {
        try {
          final res = await http.head(Uri.parse(url), headers: {'User-Agent': 'Mozilla/5.0'});
          source.status = res.statusCode < 400 || res.statusCode == 403 ? 'Active' : 'Broken';
        } catch (_) {
          // Try GET instead
          try {
            final res = await http.get(Uri.parse(url), headers: {'User-Agent': 'Mozilla/5.0', 'Range': 'bytes=0-0'});
            source.status = res.statusCode == 206 || res.statusCode == 200 ? 'Active' : 'Broken';
          } catch (_) { source.status = 'Broken'; }
        }
      } else if (url.startsWith('magnet:')) {
        source.status = 'Active'; // Magnets are always considered active
      } else if (url.startsWith('stalker://')) {
        source.status = 'Active'; // Stalker VODs are validated at stream time
      } else {
        source.status = 'Unknown';
      }
    } finally {
      if (mounted) setState(() => source.isTesting = false);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);
    try {
      final streamSourcesJson = _streamSources
          .where((s) => s.urlCtrl.text.trim().isNotEmpty)
          .map((s) => '{"name":"${s.nameCtrl.text.trim()}","url":"${s.urlCtrl.text.trim()}"}')
          .join(',');
      final data = <String, dynamic>{
        'title': _titleCtrl.text,
        'description': _overviewCtrl.text,
        'language_id': _languageId?.toString() ?? '',
        'release_date': _releaseCtrl.text,
        'runtime': _runtimeCtrl.text,
        'trailer_url': _trailerCtrl.text,
        'quality_tag': _quality,
        'poster_url': _posterCtrl.text,
        'backdrop_url': _backdropCtrl.text,
        'tmdb_id': _tmdbCtrl.text,
        'imdb_id': _imdbCtrl.text,
        'cast': _castCtrl.text,
        'cast_photos': _castPhotosCtrl.text,
        'director': _directorCtrl.text,
        'director_photo': _directorPhotoCtrl.text,
        'genre': _genreCtrl.text,
        'collection': '',
        'ott_id': _ottId?.toString() ?? '',
        'custom_created_at': _ingestionDate?.toIso8601String().substring(0, 16) ?? '',
        if (streamSourcesJson.isNotEmpty) 'stream_sources_json': '[$streamSourcesJson]',
        'stream_url': _streamSources.where((s) => s.urlCtrl.text.trim().isNotEmpty).firstOrNull?.urlCtrl.text ?? '',
      };
      final result = await _adminApi.addMovie(data);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(result['message'] ?? 'Movie added'),
          backgroundColor: result['success'] == true ? const Color(0xFF10B981) : Colors.red,
        ));
        if (result['success'] == true) {
          ref.read(movieProvider.notifier).fetchMovies(refresh: true);
          context.pop();
        }
      }
    } finally { if (mounted) setState(() => _isSaving = false); }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.menu), onPressed: DrawerProvider.openDrawer),
        title: const Text('Add Movie'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // TMDB Import section
            _sectionHeader('TMDB Import'),
            const SizedBox(height: 8),
            _tmdbSearchBox(),
            if (_tmdbSuggestions.isNotEmpty) _tmdbSuggestionsList(),
            const SizedBox(height: 12),
            // Title & Genre row
            Row(children: [
              Expanded(flex: 3, child: _field('Movie Title', _titleCtrl, Icons.title, required: true)),
              const SizedBox(width: 12),
              Expanded(flex: 2, child: _field('Genre', _genreCtrl, Icons.category)),
            ]),
            const SizedBox(height: 12),
            // IDs row
            Row(children: [
              Expanded(child: _field('TMDB ID', _tmdbCtrl, Icons.tag, inputType: TextInputType.number)),
              const SizedBox(width: 12),
              Expanded(child: _field('IMDb ID', _imdbCtrl, Icons.tag)),
            ]),
            const SizedBox(height: 12),
            // Language & OTT dropdown row
            Row(children: [
              Expanded(child: _dropdown('Language', _languages, _languageId, (v) => setState(() => _languageId = v), required: true)),
              const SizedBox(width: 12),
              Expanded(child: _dropdown('OTT Provider', _ottProviders, _ottId, (v) => setState(() => _ottId = v))),
            ]),
            const SizedBox(height: 12),
            // Overview
            _field('Story / Overview', _overviewCtrl, Icons.description, maxLines: 4),
            const SizedBox(height: 12),
            // Cast
            Row(children: [
              Expanded(child: _field('Cast Names', _castCtrl, Icons.people)),
              const SizedBox(width: 12),
              Expanded(child: _field('Cast Photo URLs', _castPhotosCtrl, Icons.image)),
            ]),
            const SizedBox(height: 12),
            // Director
            Row(children: [
              Expanded(child: _field('Director Name', _directorCtrl, Icons.person)),
              const SizedBox(width: 12),
              Expanded(child: _field('Director Photo URL', _directorPhotoCtrl, Icons.image)),
            ]),
            const SizedBox(height: 12),
            // Release, Runtime, Quality, Trailer row
            Row(children: [
              Expanded(child: _field('Release Date', _releaseCtrl, Icons.calendar_today, hint: 'YYYY-MM-DD')),
              const SizedBox(width: 8),
              Expanded(child: _field('Runtime', _runtimeCtrl, Icons.timer, inputType: TextInputType.number)),
              const SizedBox(width: 8),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A1F2E).withOpacity(0.5),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white.withOpacity(0.08)),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _quality,
                      dropdownColor: const Color(0xFF1A1F2E),
                      isExpanded: true,
                      items: ['4K', '1080p', '720p', 'CAM'].map((q) => DropdownMenuItem(value: q, child: Text(q, style: const TextStyle(color: Colors.white, fontSize: 13)))).toList(),
                      onChanged: (v) { if (v != null) setState(() => _quality = v); },
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                      icon: Icon(Icons.arrow_drop_down, color: Colors.white.withOpacity(0.5)),
                    ),
                  ),
                ),
              ),
            ]),
            const SizedBox(height: 12),
            // Trailer & Ingestion Date
            Row(children: [
              Expanded(flex: 3, child: _field('Trailer URL', _trailerCtrl, Icons.videocam)),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A1F2E).withOpacity(0.5),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white.withOpacity(0.08)),
                  ),
                  child: InkWell(
                    onTap: () async {
                      final date = await showDatePicker(context: context, initialDate: _ingestionDate ?? DateTime.now(), firstDate: DateTime(2000), lastDate: DateTime(2030));
                      if (date != null && mounted) {
                        final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_ingestionDate ?? DateTime.now()));
                        if (time != null) setState(() => _ingestionDate = DateTime(date.year, date.month, date.day, time.hour, time.minute));
                      }
                    },
                    child: InputDecorator(
                      decoration: InputDecoration(
                        labelText: 'Ingestion Date', labelStyle: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 13),
                        prefixIcon: Icon(Icons.calendar_month, size: 18, color: Colors.white.withOpacity(0.4)),
                        border: InputBorder.none, contentPadding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: Text(
                        _ingestionDate != null ? '${_ingestionDate!.year}-${_ingestionDate!.month.toString().padLeft(2, '0')}-${_ingestionDate!.day.toString().padLeft(2, '0')} ${_ingestionDate!.hour.toString().padLeft(2, '0')}:${_ingestionDate!.minute.toString().padLeft(2, '0')}' : 'Select date',
                        style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 13),
                      ),
                    ),
                  ),
                ),
              ),
            ]),
            const SizedBox(height: 16),
            // Poster & Backdrop with live preview
            _sectionHeader('Images'),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: _imageField('Poster URL', _posterCtrl, true)),
              const SizedBox(width: 12),
              Expanded(child: _imageField('Backdrop URL', _backdropCtrl, false)),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: _imagePreview(_posterPreviewUrl, 180, 270)),
              const SizedBox(width: 12),
              Expanded(child: _imagePreview(_backdropPreviewUrl, 180, 101)),
            ]),
            const SizedBox(height: 16),
            // Stream Sources
            _sectionHeader('Video Stream Sources'),
            const SizedBox(height: 8),
            ..._streamSources.asMap().entries.map((entry) {
              final i = entry.key;
              final s = entry.value;
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white.withOpacity(0.08)),
                ),
                child: Column(
                  children: [
                    Row(children: [
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1A1F2E).withOpacity(0.5),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.white.withOpacity(0.08)),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: s.nameCtrl.text.isEmpty ? null : s.nameCtrl.text,
                              hint: Text('Source type', style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 12)),
                              dropdownColor: const Color(0xFF1A1F2E),
                              isExpanded: true,
                              items: _sourceTypes.map((t) => DropdownMenuItem(value: t, child: Text(t, style: const TextStyle(color: Colors.white, fontSize: 12)))).toList(),
                              onChanged: (v) { if (v != null) s.nameCtrl.text = v; setState(() {}); },
                              icon: Icon(Icons.arrow_drop_down, color: Colors.white.withOpacity(0.5), size: 20),
                              style: const TextStyle(color: Colors.white, fontSize: 13),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 2,
                        child: _field('URL', s.urlCtrl, Icons.link, small: true),
                      ),
                    ]),
                    const SizedBox(height: 6),
                    Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                      if (s.status != null)
                        Padding(
                          padding: const EdgeInsets.only(right: 12),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            Container(width: 6, height: 6, decoration: BoxDecoration(
                              color: s.status == 'Active' ? const Color(0xFF10B981) : s.status == 'Broken' ? const Color(0xFFEF4444) : Colors.grey,
                              shape: BoxShape.circle,
                            )),
                            const SizedBox(width: 4),
                            Text(s.status!, style: TextStyle(fontSize: 10, color: s.status == 'Active' ? const Color(0xFF10B981) : s.status == 'Broken' ? const Color(0xFFEF4444) : Colors.grey, fontWeight: FontWeight.bold)),
                          ]),
                        ),
                      SizedBox(
                        height: 28, width: 28,
                        child: IconButton(
                          padding: EdgeInsets.zero, iconSize: 14,
                          icon: s.isTesting
                              ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.favorite_border, color: Colors.white54),
                          onPressed: s.isTesting ? null : () => _testSourceHealth(s.id),
                          style: IconButton.styleFrom(backgroundColor: Colors.white.withOpacity(0.05)),
                        ),
                      ),
                      const SizedBox(width: 4),
                      SizedBox(
                        height: 28, width: 28,
                        child: IconButton(
                          padding: EdgeInsets.zero, iconSize: 14,
                          icon: const Icon(Icons.close, color: Color(0xFFEF4444)),
                          onPressed: () => _removeStreamSource(s.id),
                          style: IconButton.styleFrom(backgroundColor: Colors.red.withOpacity(0.1)),
                        ),
                      ),
                    ]),
                  ],
                ),
              );
            }),
            const SizedBox(height: 4),
            TextButton.icon(
              onPressed: () => _addStreamSource(),
              icon: const Icon(Icons.add, size: 16, color: Color(0xFF3B82F6)),
              label: Text('Add Source', style: TextStyle(color: const Color(0xFF3B82F6).withOpacity(0.8), fontSize: 12, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 24),
            SizedBox(
              height: 52,
              child: ElevatedButton(
                onPressed: _isSaving ? null : _save,
                child: _isSaving
                    ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Save to Library', style: TextStyle(letterSpacing: 1)),
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _sectionHeader(String title) {
    return Text(title, style: TextStyle(color: const Color(0xFF3B82F6), fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1));
  }

  Widget _tmdbSearchBox() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1F2E).withOpacity(0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF3B82F6).withOpacity(0.3)),
      ),
      child: Row(children: [
        Icon(Icons.search, size: 18, color: const Color(0xFF3B82F6)),
        const SizedBox(width: 8),
        Expanded(
          child: TextField(
            controller: _tmdbSearchCtrl,
            onChanged: _onTmdbSearchChanged,
            style: const TextStyle(color: Colors.white, fontSize: 14),
            decoration: InputDecoration(
              hintText: 'Search TMDB or enter ID...',
              hintStyle: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 13),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(vertical: 14),
              suffixIcon: _isSearchingTMDB
                  ? SizedBox(width: 20, height: 20, child: Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator(strokeWidth: 2)))
                  : null,
            ),
          ),
        ),
      ]),
    );
  }

  Widget _tmdbSuggestionsList() {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF0D121E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.15)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.6), blurRadius: 24, spreadRadius: 2)],
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: _tmdbSuggestions.map((m) => InkWell(
        onTap: () {
          setState(() => _tmdbSuggestions = []);
          _selectTmdbMovie(m.id);
        },
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: m.posterPath != null
                  ? Image.network(m.posterPath!, width: 36, height: 54, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(width: 36, height: 54, color: Colors.grey[850]))
                  : Container(width: 36, height: 54, color: Colors.grey[850], child: const Icon(Icons.movie, size: 18, color: Colors.white24)),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(m.title, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis),
              Text('${m.releaseDate?.split('-')[0] ?? "N/A"} - ID: ${m.id}', style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 10)),
            ])),
          ]),
        ),
      )).toList(),
      ),
    );
  }

  Widget _field(String label, TextEditingController ctrl, IconData icon, {int maxLines = 1, bool required = false, TextInputType? inputType, String? hint, bool small = false}) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1A1F2E).withOpacity(0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: TextFormField(
        controller: ctrl, maxLines: maxLines, keyboardType: inputType,
        validator: required ? (v) => (v == null || v.trim().isEmpty) ? 'Required' : null : null,
        style: TextStyle(color: Colors.white, fontSize: small ? 12 : 14),
        decoration: InputDecoration(
          labelText: label, labelStyle: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: small ? 11 : 13),
          hintText: hint, hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
          prefixIcon: Icon(icon, size: small ? 16 : 18, color: Colors.white.withOpacity(0.4)),
          border: InputBorder.none,
          contentPadding: EdgeInsets.symmetric(horizontal: small ? 8 : 12, vertical: maxLines > 1 ? 12 : small ? 10 : 14),
          isDense: small,
        ),
      ),
    );
  }

  Widget _dropdown(String label, List<Map<String, dynamic>> items, int? value, ValueChanged<int?> onChanged, {bool required = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1F2E).withOpacity(0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          value: value,
          isExpanded: true,
          dropdownColor: const Color(0xFF1A1F2E),
          hint: Text('Select $label', style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 13)),
          items: (required
              ? items
              : [<String, dynamic>{'id': 0, 'name': 'None'}, ...items]
          ).map((e) => DropdownMenuItem(
            value: e['id'] is int ? e['id'] as int : int.tryParse(e['id'].toString()) ?? 0,
            child: Text(e['name']?.toString() ?? '', style: const TextStyle(color: Colors.white, fontSize: 13)),
          )).toList(),
          onChanged: onChanged,
          style: const TextStyle(color: Colors.white, fontSize: 14),
          icon: Icon(Icons.arrow_drop_down, color: Colors.white.withOpacity(0.5)),
        ),
      ),
    );
  }

  Widget _imageField(String label, TextEditingController ctrl, bool isPoster) {
    final tmdbId = int.tryParse(_tmdbCtrl.text.trim()) ?? 0;
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1A1F2E).withOpacity(0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: TextField(
        controller: ctrl,
        style: const TextStyle(color: Colors.white, fontSize: 13),
        onChanged: (v) {
          setState(() {
            if (isPoster) _posterPreviewUrl = v.isNotEmpty ? v : null;
            else _backdropPreviewUrl = v.isNotEmpty ? v : null;
          });
        },
        decoration: InputDecoration(
          labelText: label, labelStyle: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12),
          prefixIcon: Icon(Icons.image, size: 16, color: Colors.white.withOpacity(0.4)),
          suffixIcon: IconButton(
            icon: const Icon(Icons.photo_library_rounded, size: 18, color: Color(0xFF8B5CF6)),
            tooltip: 'Pick from Gallery',
            onPressed: () async {
              if (tmdbId <= 0) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Please select or enter a valid TMDB ID first to fetch image variants.')),
                );
                return;
              }
              final selectedUrl = await showDialog<String>(
                context: context,
                builder: (_) => ImagePickerGalleryDialog(
                  tmdbId: tmdbId,
                  imdbId: _imdbCtrl.text.trim(),
                  isPoster: isPoster,
                ),
              );
              if (selectedUrl != null && mounted) {
                ctrl.text = selectedUrl;
                setState(() {
                  if (isPoster) _posterPreviewUrl = selectedUrl;
                  else _backdropPreviewUrl = selectedUrl;
                });
              }
            },
          ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
          isDense: true,
        ),
      ),
    );
  }

  Widget _imagePreview(String? url, double height, double width) {
    if (url == null || url.isEmpty) {
      return Container(
        height: height, width: width,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withOpacity(0.08)),
        ),
        child: Center(child: Icon(Icons.image, color: Colors.white.withOpacity(0.15), size: 32)),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Image.network(url, height: height, width: width, fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Container(
          height: height, width: width,
          decoration: BoxDecoration(color: Colors.red.withOpacity(0.1), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.red.withOpacity(0.2))),
          child: Center(child: Text('Invalid URL', style: TextStyle(color: Colors.red.withOpacity(0.6), fontSize: 10))),
        ),
        loadingBuilder: (_, child, progress) => progress == null ? child : Container(
          height: height, width: width, color: Colors.grey[850],
          child: Center(child: CircularProgressIndicator(strokeWidth: 2, value: progress.expectedTotalBytes != null ? progress.cumulativeBytesLoaded / progress.expectedTotalBytes! : null)),
        ),
      ),
    );
  }
}

class _StreamSource {
  final int id;
  final TextEditingController nameCtrl;
  final TextEditingController urlCtrl;
  bool isTesting = false;
  String? status;
  _StreamSource({required this.id, required this.nameCtrl, required this.urlCtrl});
}
