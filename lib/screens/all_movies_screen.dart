import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:private_cinema_ios/models/movie.dart';
import 'package:private_cinema_ios/data/mock_catalog.dart';
import 'package:private_cinema_ios/theme/app_colors.dart';
import 'package:private_cinema_ios/widgets/movie_card.dart';
import 'package:private_cinema_ios/screens/movie_detail_screen.dart';

Widget getOttLogo(String name, {String? logoUrl, double size = 38}) {
  final lower = name.toLowerCase();

  String? primaryUrl = logoUrl;
  Color bg;
  Color accentColor;
  String text;
  IconData? icon;

  if (lower.contains('netflix') || lower.contains('(nf)')) {
    primaryUrl ??= 'https://assets.nflxext.com/us/ffe/siteui/common/icons/nficon2016.png';
    bg = const Color(0xFF000000);
    accentColor = const Color(0xFFE50914);
    text = 'N';
  } else if (lower.contains('prime') || lower.contains('amazon') || lower.contains('(pv)')) {
    primaryUrl ??= 'https://upload.wikimedia.org/wikipedia/commons/thumb/1/11/Amazon_Prime_Video_logo.svg/185px-Amazon_Prime_Video_logo.svg.png';
    bg = const Color(0xFF00A8E1);
    accentColor = Colors.white;
    text = 'PRIME';
  } else if (lower.contains('hotstar') || lower.contains('disney') || lower.contains('jiohotstar') || lower.contains('(hs)')) {
    primaryUrl ??= 'https://upload.wikimedia.org/wikipedia/commons/thumb/1/1e/Disney%2B_Hotstar_logo.svg/185px-Disney%2B_Hotstar_logo.svg.png';
    bg = const Color(0xFF0F1016);
    accentColor = const Color(0xFF00E5FF);
    text = 'HOTSTAR';
    icon = Icons.star_rounded;
  } else if (lower.contains('sony') || lower.contains('liv')) {
    primaryUrl ??= 'https://upload.wikimedia.org/wikipedia/commons/thumb/5/58/SonyLIV_logo.svg/185px-SonyLIV_logo.svg.png';
    bg = const Color(0xFF16151A);
    accentColor = const Color(0xFFFF5500);
    text = 'LIV';
  } else if (lower.contains('zee')) {
    primaryUrl ??= 'https://upload.wikimedia.org/wikipedia/commons/thumb/5/5a/ZEE5_logo.svg/185px-ZEE5_logo.svg.png';
    bg = const Color(0xFF8230C6);
    accentColor = const Color(0xFFFFC107);
    text = 'ZEE5';
  } else if (lower.contains('jio')) {
    primaryUrl ??= 'https://upload.wikimedia.org/wikipedia/commons/thumb/e/e4/JioCinema_logo.svg/185px-JioCinema_logo.svg.png';
    bg = const Color(0xFFE20074);
    accentColor = Colors.white;
    text = 'Jio';
  } else if (lower.contains('sun')) {
    primaryUrl ??= 'https://upload.wikimedia.org/wikipedia/commons/thumb/a/a2/Sun_NXT_logo.png/185px-Sun_NXT_logo.png';
    bg = const Color(0xFFFF5500);
    accentColor = Colors.yellow;
    text = 'SUN';
  } else if (lower.contains('aha')) {
    primaryUrl ??= 'https://upload.wikimedia.org/wikipedia/commons/thumb/8/87/Aha_OTT_logo.png/185px-Aha_OTT_logo.png';
    bg = const Color(0xFFFF5100);
    accentColor = Colors.white;
    text = 'aha';
  } else if (lower.contains('apple')) {
    primaryUrl ??= 'https://upload.wikimedia.org/wikipedia/commons/thumb/2/28/Apple_TV_Plus_Logo.svg/185px-Apple_TV_Plus_Logo.svg.png';
    bg = const Color(0xFF1C1C1E);
    accentColor = Colors.white;
    text = 'tv+';
    icon = Icons.apple;
  } else {
    bg = const Color(0xFF25293A);
    accentColor = Colors.white70;
    text = name.isNotEmpty ? name[0].toUpperCase() : 'O';
  }

  final fallbackWidget = Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(size * 0.28),
      border: Border.all(color: accentColor.withOpacity(0.5), width: 1.2),
      boxShadow: [
        BoxShadow(
          color: bg.withOpacity(0.4),
          blurRadius: 4,
        ),
      ],
    ),
    child: Center(
      child: icon != null
          ? Icon(icon, color: accentColor, size: size * 0.55)
          : Text(
              text,
              style: TextStyle(
                color: accentColor,
                fontWeight: FontWeight.bold,
                fontSize: size * 0.36,
                letterSpacing: -0.5,
              ),
            ),
    ),
  );

  if (primaryUrl != null && primaryUrl.isNotEmpty) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.28),
      child: Image.network(
        primaryUrl,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => fallbackWidget,
      ),
    );
  }

  return fallbackWidget;
}

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

  @override
  void initState() {
    super.initState();
    if (widget.initialOttProvider != null && widget.initialOttProvider!.trim().isNotEmpty) {
      _selectedOtts.add(widget.initialOttProvider!.trim());
    }
    _loadFilters();
    _applyFilters();
    _searchController.addListener(_applyFilters);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _loadFilters() {
    final all = MockCatalog.allMovies;
    
    // Extract unique non-empty values dynamically from catalog & database
    final genres = all.map((m) => m.genre).where((g) => g.trim().isNotEmpty).toSet().toList()..sort();
    final languages = all.map((m) => m.language).whereType<String>().where((l) => l.trim().isNotEmpty).toSet().toList()..sort();
    
    // STRICT: Extract ONLY actual OTT providers and actual OTT logos present in database/catalog movies
    final ottMap = <String, String?>{};
    for (final m in all) {
      if (m.ottName != null && m.ottName!.trim().isNotEmpty) {
        final name = m.ottName!.trim();
        ottMap[name] = (m.ottLogo != null && m.ottLogo!.isNotEmpty) ? m.ottLogo : ottMap[name];
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
    var list = List<Movie>.from(MockCatalog.allMovies);

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
      list = list.where((m) => _selectedGenres.contains(m.genre)).toList();
    }

    if (_selectedLanguages.isNotEmpty) {
      list = list.where((m) => m.language != null && _selectedLanguages.contains(m.language!)).toList();
    }

    if (_selectedOtts.isNotEmpty) {
      list = list.where((m) {
        if (m.ottName == null) return false;
        return _selectedOtts.any((s) => s.toLowerCase() == m.ottName!.toLowerCase() || m.ottName!.toLowerCase().contains(s.toLowerCase()));
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
                  border: Border.all(color: Colors.white.withOpacity(0.15)),
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

            const SizedBox(height: 8),

            // Movie Grid
            Expanded(
              child: _filteredMovies.isEmpty
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
