import 'dart:io';
import 'dart:convert';
import 'package:args/args.dart';
import 'package:dartx/dartx.dart';
import 'package:logging/logging.dart';
import 'package:http/http.dart' as http;
import 'package:googleapis_auth/auth_io.dart';
import 'package:googleapis/youtube/v3.dart' as yt;

import 'package:bilitube/wbi.dart';

// const String version = '0.0.1';

Config parse(List<String> a) {
  final parser = ArgParser()
    ..addOption('bc', abbr: 'e', help: '哔哩哔哩用户Cookie，用于风控校验')
    ..addOption('bm', abbr: 'm', help: '哔哩哔哩用户MemberID，用于获取用户空间信息')
    ..addOption('yi', abbr: 'i', help: 'YouTubeApiOAuth验证方式的ClientID')
    ..addOption('ys', abbr: 's', help: 'YouTubeApiOAuth验证方式的ClientSecret')
    ..addOption('ya', abbr: 'a', help: 'YouTubeApiOAuth验证方式的AccessToken（可选）')
    ..addOption('yr',
        abbr: 'r', help: 'YouTubeApiOAuth验证方式的RefreshToken，用于获取AccessToken')
    ..addOption('yc', abbr: 'c', help: 'YouTube的ChannelID')
    ..addOption('yd', abbr: 'd', help: 'YouTube的回退CategoryId，默认27')
    ..addFlag('log', abbr: 'l', help: '开启日志', defaultsTo: false);
  parser.addFlag(
    'help',
    abbr: 'h',
    callback: (b) {
      if (b) {
        print('欢迎使用BiliTube！以下是帮助文档：\n');
        print(parser.usage);
        exit(0);
      }
    },
  );
  return Config(parser.parse(a));
}

class Config {
  Config(ArgResults args)
      : bilibiliCookie = args['bc']!,
        bilibiliMemberId = args['bm']!,
        youtubeOAuthClientId = args['yi']!,
        youtubeOAuthClientSecret = args['ys']!,
        youtubeOAuthAccessToken = args['ya'] ?? '',
        youtubeOAuthRefreshToken = args['yr']!,
        youtubeChannelId = args['yc']!,
        youtubeDefaultCategoryId = args['yd'] ?? 27,
        log = (args['log'] as bool) ? Level.ALL : Level.WARNING,
        rawArgResult = args;
  String bilibiliCookie;
  String bilibiliMemberId;
  String youtubeOAuthClientId;
  String youtubeOAuthClientSecret;
  String youtubeOAuthAccessToken;
  String youtubeOAuthRefreshToken;
  String youtubeChannelId;
  String youtubeDefaultCategoryId;
  Level log;
  ArgResults rawArgResult;
}

void main(List<String> input) async {
  final config = parse(input.isEmpty ? (List.from(input)..add('-h')) : input);
  Logger.root.level = config.log;
  final log = Logger('main');
  log.onRecord.listen((event) {
    print(
        '[${event.time.toUtc().toIso8601String()}] ${event.level.name}: ${event.message}');
  });
  log.info('BiliTube已启动');

  final bilibili = Bilibili(config);
  final bilibiliList = await bilibili.list;
  final youtube = Youtube(config);
  final youtubeList = await youtube.list;
}

String jsonEncodeWithIndent(Object json) {
  const JsonEncoder encoder = JsonEncoder.withIndent(' ');
  return encoder.convert(json);
}

class BBdown {
  BBdown(this.address);
  String address;
  Future<ProcessResult> download() async {
    return await Process.run(
        'bbdown',
        [
          '$address --encoding-priority "av1,hevc,avc" -F bbdown-<bvid> -M bbdown-<bvid>-<cid>'
        ],
        runInShell: true);
  }
}

class Video {
  Video(this.id, this.title, this.description,
      {this.categoryId, this.date, this.parts = const <VideoPart>[]});
  String id;
  String title;
  DateTime? date;
  String description;
  int? categoryId;
  List<VideoPart> parts;
}

class VideoPart {
  VideoPart(this.cid, this.title, {this.playUrl});
  String cid;
  String title;
  String? playUrl;
}

class Bilibili {
  Bilibili(this._config);
  final Config _config;
  static const String endpoint = 'https://api.bilibili.com';
  Map<String, String> get _headers => {
        'user-agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/115.0.0.0 Safari/537.36 Edg/115.0.1901.183',
        'accept':
            'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.7',
        'accept-language': 'zh',
        'cache-control': 'no-cache',
        'pragma': 'no-cache',
        'sec-ch-ua':
            '"Not/A)Brand";v="99", "Microsoft Edge";v="115", "Chromium";v="115"',
        'sec-ch-ua-mobile': '?0',
        'sec-ch-ua-platform': '"Windows"',
        'sec-fetch-dest': 'document',
        'sec-fetch-mode': 'navigate',
        'sec-fetch-site': 'none',
        'sec-fetch-user': '?1',
        'upgrade-insecure-requests': '1',
        'cookie': _config.bilibiliCookie,
        'referer': 'https://www.bilibili.com/'
      };
  Future<List<Video>> get list async {
    final log = Logger('BilibiliList');
    Future<List<Map>> getVlist() async {
      Future<Map> getSearchResults(int pn) async => await http
              .get(
                  await Uri.parse(
                          '$endpoint/x/space/wbi/arc/search?mid=${_config.bilibiliMemberId}&pn=$pn')
                      .toWbiUri(),
                  headers: _headers)
              .catchError((err) => throw err)
              .then((value) => jsonDecode(value.body))
              .then((body) {
            if (body['code'] == 0) {
              return body;
            } else {
              throw body;
            }
          });
      List<Map> vlist = [];
      int pn = 1;
      final firstPage = await getSearchResults(pn);
      final int pageCount = firstPage['data']['page']['count'];
      logPage(int pn, int pageCount) =>
          log.info('正在获取哔哩哔哩用户视频，已获取 $pn 页，共 $pageCount 页');
      logPage(pn, pageCount);
      vlist.addAll(
          (firstPage['data']['list']['vlist'] as List).whereType<Map>());
      for (pn + 1; pn <= pageCount; pn = pn + 1) {
        vlist.addAll(
            ((await getSearchResults(pn))['data']['list']['vlist'] as List)
                .whereType<Map>());
        logPage(pn, pageCount);
      }
      return vlist;
    }

    final vlist = await getVlist();

    List<Video> videoList = [];
    for (var item in vlist) {
      videoList.add(Video(item['bvid'], item['title'], item['description'],
          categoryId: item['typeid']));
    }

    Future<List<Map>> getParts(String bvid) async => await http
            .get(
                Uri.parse(
                    'https://api.bilibili.com/x/player/pagelist?bvid=$bvid'),
                headers: _headers)
            .catchError((err) => throw err)
            .then((value) => jsonDecode(value.body))
            .then((body) {
          if (body['code'] == 0) {
            return (body['data'] as List).whereType<Map>().toList();
          } else {
            throw body;
          }
        });
    logVideo(String title, int partCount) =>
        log.info('已获取 $title 的各个P的信息，共 $partCount 个P');
    for (final item in videoList) {
      final parts = await getParts(item.id);
      List<VideoPart> list = [];
      logVideo(item.title, parts.length);
      for (final part in parts) {
        list.add(VideoPart(part['cid'].toString(), part['part']));
      }
      item.parts = list;
    }
    log.info('已获取到哔哩哔哩用户视频的全部信息如下\n${jsonEncodeWithIndent(videoList.map((e) => [
          '${e.id}-${e.title}',
          e.parts.map((e) => '${e.cid}-${e.title}').toList()
        ]).toList())}');
    return videoList;
  }
}

class Youtube {
  Youtube(this._config);
  final Config _config;
  Future<AutoRefreshingAuthClient> _client() async {
    var client = http.Client();
    var id = ClientId(
        _config.youtubeOAuthClientId, _config.youtubeOAuthClientSecret);
    var credentials = AccessCredentials(
        AccessToken('Bearer', _config.youtubeOAuthAccessToken, DateTime.now()),
        _config.youtubeOAuthRefreshToken, [
      'https://www.googleapis.com/auth/youtube',
      'https://www.googleapis.com/auth/youtube.force-ssl',
      'https://www.googleapis.com/auth/youtube.channel-memberships.creator',
      'https://www.googleapis.com/auth/youtubepartner',
      'https://www.googleapis.com/auth/youtube.readonly',
      'https://www.googleapis.com/auth/youtube.upload',
    ]);
    return autoRefreshingClient(id, credentials, client);
  }

  Future<List<Video>> get list async {
    final client = await _client();
    final youtube = yt.YouTubeApi(client);
    // https://developers.google.com/youtube/v3/docs/search/list#parameters
    final res = await youtube.search
        .list(['snippet'], channelId: _config.youtubeChannelId);
    var items = res.items!.where((element) => element.id!.videoId != null);
    List<Video> list = [];
    for (final item in items) {
      list.add(Video(
          item.id!.videoId!, item.snippet!.title!, item.snippet!.description!));
    }
    client.close();
    return list;
  }

  /// https://developers.google.com/youtube/v3/docs/videos/insert
  void upload(Video item, Stream<List<int>> stream, int streamLength) async {
    final client = await _client();
    final youtube = yt.YouTubeApi(client);
    final video = yt.Video(
        snippet: yt.VideoSnippet()
          ..title = item.title
          ..channelId = _config.youtubeChannelId
          ..description = '${item.description}\n(${item.id.hashCode})'
          ..categoryId = item.categoryId.toString());
    final media = yt.Media(stream, streamLength);
    await youtube.videos.insert(video, ['snippet'], uploadMedia: media);
    client.close();
  }
}

class RemoteFile {
  RemoteFile(this.uri);
  Uri uri;

  Future<http.StreamedResponse> get res async {
    final client = http.Client();
    final res = await client.send(http.Request('GET', uri));
    client.close();
    return res;
  }

  get stream async => (await res).stream;
  get length async => (await res).contentLength;

  Future<File> download() async {
    final file = File(uri.path.split('/').last);
    await file.openWrite().addStream(await stream);
    return file;
  }
}
