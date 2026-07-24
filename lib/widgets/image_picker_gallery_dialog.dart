import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../admin/utils/tmdb_service.dart';

class ImagePickerGalleryDialog extends StatefulWidget {
  final int tmdbId;
  final String? imdbId;
  final bool isPoster;

  const ImagePickerGalleryDialog({
    super.key,
    required this.tmdbId,
    this.imdbId,
    required this.isPoster,
  });

  @override
  State<ImagePickerGalleryDialog> createState() => _ImagePickerGalleryDialogState();
}

class _ImagePickerGalleryDialogState extends State<ImagePickerGalleryDialog> {
  bool _isLoading = true;
  List<String> _images = [];

  @override
  void initState() {
    super.initState();
    _fetchImages();
  }

  Future<void> _fetchImages() async {
    final result = await TmdbService.getMovieImages(widget.tmdbId, imdbId: widget.imdbId);
    if (mounted) {
      setState(() {
        _images = widget.isPoster ? result.posters : result.backdrops;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF161B22),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        width: 550,
        height: 600,
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  widget.isPoster ? 'Select Poster Image' : 'Select Backdrop Image',
                  style: GoogleFonts.outfit(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white54),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Fetched from TMDB & Fanart.tv APIs. Tap any image to select.',
              style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator(color: Color(0xFFEF4444)))
                  : _images.isEmpty
                      ? const Center(child: Text('No images found for this movie.', style: TextStyle(color: Colors.white38)))
                      : GridView.builder(
                          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: widget.isPoster ? 3 : 2,
                            childAspectRatio: widget.isPoster ? 0.67 : 1.77,
                            crossAxisSpacing: 10,
                            mainAxisSpacing: 10,
                          ),
                          itemCount: _images.length,
                          itemBuilder: (context, index) {
                            final url = _images[index];
                            return InkWell(
                              onTap: () => Navigator.of(context).pop(url),
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: Colors.white.withOpacity(0.1)),
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: Image.network(
                                    url,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => Container(color: Colors.white10),
                                  ),
                                ),
                              ),
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
