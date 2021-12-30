import 'package:pub_crawl/src/common.dart';

class CleanCommand extends BaseCommand {
  // todo (pq): move to 'delete' cache sub-command

  @override
  String get description => 'delete cached packages.';

  @override
  String get name => 'clean';

  @override
  Future run() async {
    print('Deleting cache...');
    await cache.delete();
  }
}
