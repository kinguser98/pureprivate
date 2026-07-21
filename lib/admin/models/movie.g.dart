part of 'movie.dart';

class MovieAdapter extends TypeAdapter<Movie> {
  @override
  final int typeId = 0;

  @override
  Movie read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return Movie(
      id: fields[0] as int,
      title: fields[1] as String,
      posterUrl: fields[2] as String,
      backdropUrl: fields[3] as String?,
      views: fields[4] as int,
      genre: fields[5] as String,
      releaseDate: fields[6] as String?,
      description: fields[7] as String?,
      streamUrl: fields[8] as String?,
      qualityTag: fields[9] as String?,
      languageId: fields[10] as int,
      cast: fields[11] as String?,
      director: fields[12] as String?,
      trailerUrl: fields[13] as String?,
      collection: fields[14] as String?,
      ottName: fields[15] as String?,
      ottLogo: fields[16] as String?,
      streamSources: fields[17] as String?,
      createdAt: fields[18] as String?,
      streamStatus: fields[19] as String?,
      lastChecked: fields[20] as String?,
      tmdbId: fields[21] as String?,
      imdbId: fields[22] as String?,
      castPhotos: fields[23] as String?,
      directorPhoto: fields[24] as String?,
      runtime: fields[25] as String?,
      ottId: fields[26] as int? ?? 0,
    );
  }

  @override
  void write(BinaryWriter writer, Movie obj) {
    writer.writeByte(27);
    writer.writeByte(0); writer.write(obj.id);
    writer.writeByte(1); writer.write(obj.title);
    writer.writeByte(2); writer.write(obj.posterUrl);
    writer.writeByte(3); writer.write(obj.backdropUrl);
    writer.writeByte(4); writer.write(obj.views);
    writer.writeByte(5); writer.write(obj.genre);
    writer.writeByte(6); writer.write(obj.releaseDate);
    writer.writeByte(7); writer.write(obj.description);
    writer.writeByte(8); writer.write(obj.streamUrl);
    writer.writeByte(9); writer.write(obj.qualityTag);
    writer.writeByte(10); writer.write(obj.languageId);
    writer.writeByte(11); writer.write(obj.cast);
    writer.writeByte(12); writer.write(obj.director);
    writer.writeByte(13); writer.write(obj.trailerUrl);
    writer.writeByte(14); writer.write(obj.collection);
    writer.writeByte(15); writer.write(obj.ottName);
    writer.writeByte(16); writer.write(obj.ottLogo);
    writer.writeByte(17); writer.write(obj.streamSources);
    writer.writeByte(18); writer.write(obj.createdAt);
    writer.writeByte(19); writer.write(obj.streamStatus);
    writer.writeByte(20); writer.write(obj.lastChecked);
    writer.writeByte(21); writer.write(obj.tmdbId);
    writer.writeByte(22); writer.write(obj.imdbId);
    writer.writeByte(23); writer.write(obj.castPhotos);
    writer.writeByte(24); writer.write(obj.directorPhoto);
    writer.writeByte(25); writer.write(obj.runtime);
    writer.writeByte(26); writer.write(obj.ottId);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MovieAdapter && runtimeType == other.runtimeType && typeId == other.typeId;
}
