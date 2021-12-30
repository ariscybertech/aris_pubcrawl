import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as path;

import 'package:pub_crawl/src/common.dart';
import 'package:pub_crawl/src/package.dart';

typedef PackageIndexer = void Function(Package p, Cache index);

Directory _cacheDir = Directory('third_party/cache');
File _indexFile = File('third_party/index.json');


// todo (pq): add a cache clean command (to remove old / duplicated libraries)

class Index {
  dynamic _jsonData;

  Index();

  void read() {
    if (_jsonData != null) {
      return;
    }
    if (!_indexFile.existsSync()) {
      print('Cache index does not exist, creating...');
      _indexFile.createSync(recursive: true);
    }
    final contents = _indexFile.readAsStringSync();
    _jsonData = contents.isNotEmpty ? jsonDecode(contents) : {};
  }

  void write() {
    final encoder = JsonEncoder.withIndent('  ');
    _indexFile.writeAsStringSync(encoder.convert(_jsonData));
  }

  Package getPackage(String name) => Package.fromData(name, _jsonData);

  void add(Package package) {
    package.addToJsonData(_jsonData);
  }

  bool containsSourcePath(String path) {
    for (var entry in _jsonData.entries) {
      if (path == entry.value['sourcePath']) {
        return true;
      }
    }
    return false;
  }

}

class Cache {
  final Index index;

  Directory get dir => _cacheDir;

  PackageIndexer onProcess;

  Cache() : index = Index()..read();

  void process(Package package) async {
    if (onProcess != null) {
      await onProcess(package, this);
    }
  }

  bool isCached(Package package) => getSourceDir(package).existsSync();

  Future cache(Package package) async {
    bool cached = await _download(package);
    if (cached) {
      index.add(package);
    }
  }

  bool hasDependenciesInstalled(Package package) {
    final sourceDir = getSourceDir(package);
    return sourceDir.existsSync() &&
        File('${sourceDir.path}/.packages').existsSync();
  }

  Future<ProcessResult> installDependencies(Package package) async {
    final sourceDir = getSourceDir(package);
    final sourcePath = sourceDir.path;
    if (!sourceDir.existsSync()) {
      print(
          'Unable to install dependencies for ${package.name}: $sourcePath does not exist');
      return null;
    }

    if (package.dependencies?.containsKey('flutter') == true) {
      return Process.run('flutter', ['packages', 'get'],
          workingDirectory: sourcePath);
    }

    //TODO: recurse and run pub get in example dirs.
    print('Running "pub get" in ${path.basename(sourcePath)}');
    return Process.run('pub', ['get'], workingDirectory: sourcePath);
  }

  Future<bool> _download(Package package) async {
    final name = package.name;
    final version = package.version;
    final url = package.archiveUrl;
    try {
      // todo (pq): migrate to _downloadDir
      const downloadDir = 'third_party/download';
      if (!Directory(downloadDir).existsSync()) {
        print('Creating: $downloadDir');
        Directory(downloadDir).createSync(recursive: true);
      }

      var response = await getResponse(url);
      var tarFile = '$downloadDir/$name-$version.tar.gz';
      await File(tarFile).writeAsBytes(response.bodyBytes);
      var outputDir = 'third_party/cache/$name-$version';
      await Directory(outputDir).create(recursive: true);
      var result = await Process.run('tar', ['-xf', tarFile, '-C', outputDir]);
      if (result.exitCode != 0) {
        print('Could not extract $tarFile:\n${result.stderr}');
      } else {
        print('Extracted $outputDir');
        await File(tarFile).delete();
      }
    } catch (error) {
      print('Error downloading $url:\n$error');
      return false;
    }

    return true;
  }

  // todo (pq): refactor to share directory info.
  Directory getSourceDir(Package package) =>
      Directory('third_party/cache/${package.name}-${package.version}');

  List<Package> list({List<Criteria> matching}) {
    final packages = <Package>[];
    if (_cacheDir.existsSync()) {
      for (var packageDir in _cacheDir.listSync()) {
        final versionedName = path.basename(packageDir.path);
        final separatorIndex = versionedName.indexOf('-');
        final packageName = versionedName.substring(0, separatorIndex);
        final indexedPackage = index.getPackage(packageName);
        if (indexedPackage != null) {
          for (var criteria in matching ?? <Criteria>[]) {
            if (!criteria.matches(indexedPackage)) {
              break;
            }
          }
          packages.add(indexedPackage);
        }
      }
    }

    return packages;
  }

  int size() => _cacheDir.existsSync() ? _cacheDir.listSync().length : 0;

  Future delete() =>
      _cacheDir.delete(recursive: true).then((_) => _indexFile.delete());
}
