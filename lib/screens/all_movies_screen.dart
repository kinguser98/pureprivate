import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:private_cinema_mobile/models/movie.dart';
import 'package:private_cinema_mobile/data/mock_catalog.dart';
import 'package:private_cinema_mobile/data/api_service.dart';
import 'package:private_cinema_mobile/theme/app_colors.dart';
import 'package:private_cinema_mobile/widgets/movie_card.dart';
import 'package:private_cinema_mobile/widgets/ott_badge.dart';
import 'package:private_cinema_mobile/screens/movie_detail_screen.dart';

class AllMoviesScreen extends StatefulWidget {
  const AllMoviesScreen({super.key, this.initialOttProvider});

  final String? initialOttProvider;

  @override
  State<AllMoviesScreen> createState() => _AllMoviesScreenState();
}

class _AllMoviesScreenState extends State<AllMoviesScreen> {
  final TextEditingController _searchController = TextEditingController();
  
  final Set<String> _selectedGenres = {};
  final Set<String> _selectedLanguages = {};
  final Set<String> _selectedOtts = {};
  
  List<Movie> _filteredMovies = [];
  List<String> _genres = [];
  List<String> _languages = [];
  List<String> _ottProviders = [];
  final Map<String, String?> _ottLogoMap = {};
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialOttProvider != null && widget.initialOttProvider!.trim().isNotEmpty) {
      _selectedOtts.add(widget.initialOttProvider!.trim());
    }
    _loadFilters();
    _applyFilters();
    _searchController.addListener(_applyFilters);
    _loadMoviesFromApi();
  }

  List<Movie> get _masterCatalog {
    if (ApiService.cachedMovies.isNotEmpty) return ApiService.cachedMovies;
    if (MockCatalog.allMovies.isNotEmpty) return MockCatalog.allMovies;
    return [];
  }

  static bool matchesOttProvider(String movieOtt, String targetOtt) {
    final m = movieOtt.toLowerCase().trim();
    final t = targetOtt.toLowerCase().trim();
    if (m == t || m.contains(t) || t.contains(m)) return true;

    final mClean = m.replaceAll(RegExp(r'[^a-z0-9]'), '');
    final tClean = t.replaceAll(RegExp(r'[^a-z0-9]'), '');
    if (mClean.isNotEmpty && tClean.isNotEmpty) {
      if (mClean == tClean || mClean.contains(tClean) || tClean.contains(mClean)) return true;
    }

    bool isNetflix(String s) => s.contains('netflix') || s.contains('(nf)');
    bool isPrime(String s) => s.contains('prime') || s.contains('amazon') || s.contains('(pv)');
    bool isHotstar(String s) => s.contains('hotstar') || s.contains('disney') || s.contains('jiohotstar') || s.contains('(hs)');
    bool isSony(String s) => s.contains('sony') || s.contains('liv');
    bool isZee(String s) => s.contains('zee');
    bool isJio(String s) => s.contains('jio');
    bool isSun(String s) => s.contains('sun');
    bool isAha(String s) => s.contains('aha');
    bool isApple(String s) => s.contains('apple');
    bool isManorama(String s) => s.contains('manorama') || s.contains('max');
    bool isSaina(String s) => s.contains('saina');

    if (isNetflix(m) && isNetflix(t)) return true;
    if (isPrime(m) && isPrime(t)) return true;
    if (isHotstar(m) && isHotstar(t)) return true;
    if (isSony(m) && isSony(t)) return true;
    if (isZee(m) && isZee(t)) return true;
    if (isJio(m) && isJio(t)) return true;
    if (isSun(m) && isSun(t)) return true;
    if (isAha(m) && isAha(t)) return true;
    if (isApple(m) && isApple(t)) return true;
    if (isManorama(m) && isManorama(t)) return true;
    if (isSaina(m) && isSaina(t)) return true;

    return false;
  }

  Future<void> _loadMoviesFromApi() async {
    if (_masterCatalog.isEmpty) {
      setState(() => _isLoading = true);
    }
    try {
      final rawData = await ApiService.fetchRawData();
      final rawMovies = rawData['movies'] as List<dynamic>? ?? [];
      final rawLanguages = rawData['languages'] as List<dynamic>? ?? [];
      final parsed = ApiService.parseMovies(rawMovies, rawLanguages, true);
      if (parsed.isNotEmpty) {
        ApiService.cachedMovies = parsed;
        MockCatalog.allMovies = parsed;
      }
    } catch (e) {
      debugPrint('AllMoviesScreen _loadMoviesFromApi error: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        _loadFilters();
        _applyFilters();
      }
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _loadFilters() {
    final all = _masterCatalog;
    
    // Extract unique non-empty genres dynamically (splitting comma-separated genres)
    final Set<String> genreSet = {};
    for (final m in all) {
      final parts = m.genre.split(',').map((g) => g.trim()).where((g) => g.isNotEmpty);
      genreSet.addAll(parts);
    }
    final genres = genreSet.toList()..sort();
    final languages = all.map((m) => m.language).whereType<String>().where((l) => l.trim().isNotEmpty).toSet().toList()..sort();
    
    // STRICT: Extract ONLY actual OTT providers and actual OTT logos present in database/catalog movies
    final ottMap = <String, String?>{};
    for (final m in all) {
      if (m.ottName != null && m.ottName!.trim().isNotEmpty) {
        final name = m.ottName!.trim();
        if (m.ottLogo != null && m.ottLogo!.isNotEmpty) {
          ottMap[name] = m.ottLogo;
        } else {
          ottMap.putIfAbsent(name, () => null);
        }
      }
    }

    final otts = ottMap.keys.toList()..sort();

    setState(() {
      _genres = genres;
      _languages = languages;
      _ottProviders = otts;
      _ottLogoMap.clear();
      _ottLogoMap.addAll(ottMap);
    });
  }

  void _applyFilters() {
    final query = _searchController.text.toLowerCase().trim();
    final catalog = _masterCatalog;
    var list = List<Movie>.from(catalog);

    if (query.isNotEmpty) {
      list = list.where((m) {
        final matchesTitle = m.title.toLowerCase().contains(query);
        final matchesDesc = m.description?.toLowerCase().contains(query) ?? false;
        final matchesDirector = m.director?.toLowerCase().contains(query) ?? false;
        final matchesCast = m.cast.any((c) => c.toLowerCase().contains(query));
        return matchesTitle || matchesDesc || matchesDirector || matchesCast;
      }).toList();
    }

    if (_selectedGenres.isNotEmpty) {
      list = list.where((m) {
        final movieGenres = m.genre.split(',').map((g) => g.trim()).toList();
        return movieGenres.any((g) => _selectedGenres.contains(g)) || _selectedGenres.contains(m.genre);
      }).toList();
    }

    if (_selectedLanguages.isNotEmpty) {
      list = list.where((m) => m.language != null && _selectedLanguages.contains(m.language!)).toList();
    }

    if (_selectedOtts.isNotEmpty) {
      list = list.where((m) {
        if (m.ottName == null || m.ottName!.trim().isEmpty) return false;
        final movieOtt = m.ottName!.trim();
        return _selectedOtts.any((s) => matchesOttProvider(movieOtt, s));
      }).toList();
    }

    setState(() {
      _filteredMovies = list;
    });
  }

  void _openCompactMultiSelectDialog({
    required String title,
    required List<String> options,
    required Set<String> currentSelected,
    required ValueChanged<Set<String>> onApply,
    bool isOtt = false,
  }) {
    final tempSelected = Set<String>.from(currentSelected);

    showDialog<void>(
      context: context,
      builder: (dialogCtx) {
        return Dialog(
          backgroundColor: Colors.transparent,
          elevation: 0,
          insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(28),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
              child: Container(
                constraints: BoxConstraints(maxHeight: isOtt ? 480 : 420),
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: const Color(0xDB1D172E), // Translucent deep purple liquid glass
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(
                    color: Colors.white.withOpacity(0.22),
                    width: 1.2,
                  ),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x667E22CE), // Ambient purple glow
                      blurRadius: 32,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: StatefulBuilder(
                  builder: (modalCtx, setModalState) {
                    final bool allSelected = tempSelected.length == options.length;
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Header title + Select All Action matching exact screenshot design
                        Row(
                          children: [
                            Text(
                              title,
                              style: GoogleFonts.outfit(
                                color: Colors.white,
                                fontSize: 16.5,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const Spacer(),
                            InkWell(
                              onTap: () {
                                setModalState(() {
                                  if (allSelected) {
                                    tempSelected.clear();
                                  } else {
                                    tempSelected.addAll(options);
                                  }
                                });
                              },
                              borderRadius: BorderRadius.circular(8),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.check_box_outlined,
                                      color: Color(0xFFC084FC),
                                      size: 15,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      allSelected ? 'Deselect All' : 'Select All',
                                      style: const TextStyle(
                                        color: Color(0xFFC084FC),
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                        
                        const SizedBox(height: 14),

                        // Options Grid/List matching exact screenshot
                        Expanded(
                          child: options.isEmpty
                              ? const Center(
                                  child: Text(
                                    'No options available',
                                    style: TextStyle(color: Colors.white38, fontSize: 12),
                                  ),
                                )
                              : isOtt
                                  ? GridView.builder(
                                      shrinkWrap: true,
                                      itemCount: options.length,
                                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                        crossAxisCount: 3, // 3 OTT logos per row
                                        crossAxisSpacing: 10,
                                        mainAxisSpacing: 10,
                                        childAspectRatio: 0.92,
                                      ),
                                      itemBuilder: (context, idx) {
                                        final opt = options[idx];
                                        final isChecked = tempSelected.contains(opt);
                                        final logoUrl = _ottLogoMap[opt];
                                        return InkWell(
                                          onTap: () {
                                            setModalState(() {
                                              if (isChecked) {
                                                tempSelected.remove(opt);
                                              } else {
                                                tempSelected.add(opt);
                                              }
                                            });
                                          },
                                          borderRadius: BorderRadius.circular(20),
                                          child: AnimatedContainer(
                                            duration: const Duration(milliseconds: 120),
                                            decoration: BoxDecoration(
                                              color: isChecked
                                                  ? const Color(0x359333EA)
                                                  : Colors.white.withOpacity(0.08),
                                              borderRadius: BorderRadius.circular(20),
                                              border: Border.all(
                                                color: isChecked
                                                    ? const Color(0xFFC084FC)
                                                    : Colors.white.withOpacity(0.12),
                                                width: isChecked ? 1.8 : 1.0,
                                              ),
                                              boxShadow: isChecked
                                                  ? const [
                                                      BoxShadow(
                                                        color: Color(0x559333EA),
                                                        blurRadius: 10,
                                                      ),
                                                    ]
                                                  : null,
                                            ),
                                            child: Stack(
                                              children: [
                                                Center(
                                                  child: Padding(
                                                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                                                    child: Column(
                                                      mainAxisAlignment: MainAxisAlignment.center,
                                                      children: [
                                                        getOttLogo(opt, logoUrl: logoUrl, size: 38),
                                                        const SizedBox(height: 7),
                                                        Text(
                                                          opt,
                                                          textAlign: TextAlign.center,
                                                          maxLines: 1,
                                                          overflow: TextOverflow.ellipsis,
                                                          style: TextStyle(
                                                            color: isChecked ? Colors.white : Colors.white70,
                                                            fontSize: 11,
                                                            fontWeight: isChecked ? FontWeight.bold : FontWeight.w500,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ),
                                                // Purple tick badge matching screenshot
                                                if (isChecked)
                                                  Positioned(
                                                    top: 6,
                                                    right: 6,
                                                    child: Container(
                                                      padding: const EdgeInsets.all(2),
                                                      decoration: const BoxDecoration(
                                                        color: Color(0xFFC084FC),
                                                        shape: BoxShape.circle,
                                                      ),
                                                      child: const Icon(
                                                        Icons.check_rounded,
                                                        color: Colors.black,
                                                        size: 10,
                                                      ),
                                                    ),
                                                  ),
                                              ],
                                            ),
                                          ),
                                        );
                                      },
                                    )
                                  : ListView.separated(
                                      shrinkWrap: true,
                                      itemCount: options.length,
                                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                                      itemBuilder: (context, idx) {
                                        final opt = options[idx];
                                        final isChecked = tempSelected.contains(opt);
                                        return InkWell(
                                          borderRadius: BorderRadius.circular(16),
                                          onTap: () {
                                            setModalState(() {
                                              if (isChecked) {
                                                tempSelected.remove(opt);
                                              } else {
                                                tempSelected.add(opt);
                                              }
                                            });
                                          },
                                          child: AnimatedContainer(
                                            duration: const Duration(milliseconds: 120),
                                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                            decoration: BoxDecoration(
                                              color: isChecked
                                                  ? const Color(0x359333EA)
                                                  : Colors.white.withOpacity(0.08),
                                              borderRadius: BorderRadius.circular(16),
                                              border: Border.all(
                                                color: isChecked
                                                    ? const Color(0xFFC084FC)
                                                    : Colors.white.withOpacity(0.12),
                                                width: isChecked ? 1.6 : 1.0,
                                              ),
                                            ),
                                            child: Row(
                                              children: [
                                                Expanded(
                                                  child: Text(
                                                    opt,
                                                    style: TextStyle(
                                                      color: isChecked ? Colors.white : Colors.white70,
                                                      fontSize: 13,
                                                      fontWeight: isChecked ? FontWeight.bold : FontWeight.w500,
                                                    ),
                                                  ),
                                                ),
                                                if (isChecked)
                                                  Container(
                                                    padding: const EdgeInsets.all(3),
                                                    decoration: const BoxDecoration(
                                                      color: Color(0xFFC084FC),
                                                      shape: BoxShape.circle,
                                                    ),
                                                    child: const Icon(
                                                      Icons.check_rounded,
                                                      color: Colors.black,
                                                      size: 12,
                                                    ),
                                                  )
                                                else
                                                  Icon(
                                                    Icons.circle_outlined,
                                                    color: Colors.white.withOpacity(0.2),
                                                    size: 18,
                                                  ),
                                              ],
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                        ),

                        const SizedBox(height: 16),

                        // Purple Gradient Apply / Show All Pill Button matching exact screenshot
                        Container(
                          width: double.infinity,
                          height: 44,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(18),
                            gradient: const LinearGradient(
                              colors: [
                                Color(0xFF5B21B6),
                                Color(0xFF9333EA),
                              ],
                            ),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x559333EA),
                                blurRadius: 12,
                                offset: Offset(0, 4),
                              ),
                            ],
                          ),
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.transparent,
                              shadowColor: Colors.transparent,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                            ),
                            onPressed: () {
                              Navigator.of(dialogCtx).pop();
                              onApply(tempSelected);
                            },
                            child: Text(
                              tempSelected.isEmpty ? 'Show All' : 'Apply (${tempSelected.length})',
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.2,
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildDropdownButton({
    required String label,
    required Set<String> selectedSet,
    required VoidCallback onTap,
    bool isOtt = false,
  }) {
    final bool hasSelection = selectedSet.isNotEmpty;
    String displayText = '$label: All';
    if (selectedSet.length == 1) {
      displayText = '$label: ${selectedSet.first}';
    } else if (selectedSet.length > 1) {
      displayText = '$label (${selectedSet.length})';
    }

    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7.5),
            decoration: BoxDecoration(
              color: hasSelection 
                  ? const Color(0x409333EA) 
                  : AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: hasSelection ? const Color(0xFFC084FC) : Colors.white.withOpacity(0.15),
                width: hasSelection ? 1.4 : 0.8,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (isOtt && selectedSet.length == 1) ...[
                  getOttLogo(selectedSet.first, logoUrl: _ottLogoMap[selectedSet.first], size: 16),
                  const SizedBox(width: 4),
                ],
                Flexible(
                  child: Text(
                    displayText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: hasSelection ? Colors.white : Colors.white70,
                      fontSize: 11.5,
                      fontWeight: hasSelection ? FontWeight.bold : FontWeight.w500,
                    ),
                  ),
                ),
                const SizedBox(width: 2),
                Icon(
                  Icons.arrow_drop_down_rounded,
                  color: hasSelection ? const Color(0xFFC084FC) : Colors.white38,
                  size: 18,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildOttLogoCube(String name) {
    final isSelected = _selectedOtts.contains(name);
    final logoUrl = _ottLogoMap[name];

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () {
        setState(() {
          if (isSelected) {
            _selectedOtts.remove(name);
          } else {
            _selectedOtts.clear();
            _selectedOtts.add(name);
            if (_searchController.text.isNotEmpty) {
              _searchController.clear();
            }
          }
          _applyFilters();
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected 
              ? const Color(0x409333EA) 
              : AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? const Color(0xFFC084FC) : Colors.white.withValues(alpha: 0.14),
            width: isSelected ? 1.5 : 0.8,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: const Color(0xFF9333EA).withValues(alpha: 0.35),
                    blurRadius: 8,
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            getOttLogo(name, logoUrl: logoUrl, size: 20),
            const SizedBox(width: 6),
            Text(
              name,
              style: TextStyle(
                color: isSelected ? Colors.white : Colors.white70,
                fontSize: 11.5,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final isLandscape = mediaQuery.orientation == Orientation.landscape;
    final int crossAxisCount = isLandscape ? 5 : 3;
    final double spacing = 12.0;

    final double cardWidth = 115.0;
    final double cardHeight = 172.5;
    final double childAspectRatio = cardWidth / cardHeight;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Search Header
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text(
                'Explore Catalog',
                style: GoogleFonts.outfit(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),

            // Compact Search Field
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              child: Container(
                height: 38,
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
                ),
                child: TextField(
                  controller: _searchController,
                  style: const TextStyle(color: Colors.white, fontSize: 12.5),
                  cursorColor: const Color(0xFFC084FC),
                  decoration: InputDecoration(
                    isDense: true,
                    prefixIcon: const Icon(Icons.search_rounded, color: Colors.white60, size: 18),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            icon: const Icon(Icons.close_rounded, color: Colors.white60, size: 16),
                            onPressed: () {
                              _searchController.clear();
                              FocusScope.of(context).unfocus();
                            },
                          )
                        : null,
                    hintText: 'Search title, cast, genre or director...',
                    hintStyle: const TextStyle(color: Colors.white38, fontSize: 11.5),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 6),

            // 3 Multi-Select Dropdown Buttons Row
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                children: [
                  _buildDropdownButton(
                    label: 'Genre',
                    selectedSet: _selectedGenres,
                    onTap: () {
                      _openCompactMultiSelectDialog(
                        title: 'Filter Genre',
                        options: _genres,
                        currentSelected: _selectedGenres,
                        onApply: (newSet) {
                          setState(() {
                            _selectedGenres.clear();
                            _selectedGenres.addAll(newSet);
                            _applyFilters();
                          });
                        },
                      );
                    },
                  ),
                  const SizedBox(width: 6),
                  _buildDropdownButton(
                    label: 'Lang',
                    selectedSet: _selectedLanguages,
                    onTap: () {
                      _openCompactMultiSelectDialog(
                        title: 'Filter Language',
                        options: _languages,
                        currentSelected: _selectedLanguages,
                        onApply: (newSet) {
                          setState(() {
                            _selectedLanguages.clear();
                            _selectedLanguages.addAll(newSet);
                            _applyFilters();
                          });
                        },
                      );
                    },
                  ),
                  const SizedBox(width: 6),
                  _buildDropdownButton(
                    label: 'OTT',
                    selectedSet: _selectedOtts,
                    isOtt: true,
                    onTap: () {
                      _openCompactMultiSelectDialog(
                        title: 'Filter OTT Provider',
                        options: _ottProviders,
                        currentSelected: _selectedOtts,
                        isOtt: true,
                        onApply: (newSet) {
                          setState(() {
                            _selectedOtts.clear();
                            _selectedOtts.addAll(newSet);
                            _applyFilters();
                          });
                        },
                      );
                    },
                  ),
                ],
              ),
            ),

            // Quick 1-tap OTT Provider Row
            if (_ottProviders.isNotEmpty) ...[
              const SizedBox(height: 8),
              SizedBox(
                height: 34,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  itemCount: _ottProviders.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, idx) => _buildOttLogoCube(_ottProviders[idx]),
                ),
              ),
            ],

            const SizedBox(height: 8),

            // Movie Grid
            Expanded(
              child: _isLoading && _filteredMovies.isEmpty
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: Color(0xFFC084FC),
                      ),
                    )
                  : _filteredMovies.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.movie_filter_outlined, color: Colors.white24, size: 48),
                              const SizedBox(height: 12),
                              Text(
                                'No movies match your filters',
                                style: GoogleFonts.outfit(color: Colors.white60, fontSize: 14),
                              ),
                              const SizedBox(height: 14),
                              TextButton.icon(
                                onPressed: () {
                                  setState(() {
                                    _searchController.clear();
                                    _selectedGenres.clear();
                                    _selectedLanguages.clear();
                                    _selectedOtts.clear();
                                    _applyFilters();
                                  });
                                },
                                icon: const Icon(Icons.clear_all_rounded, color: Color(0xFFC084FC), size: 18),
                                label: const Text(
                                  'Clear All Filters',
                                  style: TextStyle(color: Color(0xFFC084FC), fontWeight: FontWeight.bold),
                                ),
                              ),
                            ],
                          ),
                        )
                      : GridView.builder(
                          padding: const EdgeInsets.all(14),
                          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: crossAxisCount,
                            childAspectRatio: childAspectRatio,
                            crossAxisSpacing: spacing,
                            mainAxisSpacing: spacing,
                          ),
                          itemCount: _filteredMovies.length,
                          itemBuilder: (context, index) {
                            final movie = _filteredMovies[index];
                            return MovieCard(
                              movie: movie,
                              onTap: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                    builder: (_) => MovieDetailScreen(movie: movie),
                                  ),
                                );
                              },
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
