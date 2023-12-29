import 'dart:io';
import 'dart:convert';
import 'package:dartx/dartx.dart';
import 'package:http/http.dart' as http;
import 'package:googleapis_auth/auth_io.dart';
import 'package:googleapis/youtube/v3.dart' as yt;
import 'package:args/args.dart';

import 'package:bilitube/wbi.dart' show getWbiUri;

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
    ..addOption('yd', abbr: 'd', help: 'YouTube的回退CategoryId，默认27');
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
        rawArgResult = args;
  String bilibiliCookie;
  String bilibiliMemberId;
  String youtubeOAuthClientId;
  String youtubeOAuthClientSecret;
  String youtubeOAuthAccessToken;
  String youtubeOAuthRefreshToken;
  String youtubeChannelId;
  String youtubeDefaultCategoryId;
  ArgResults rawArgResult;
}

void main(List<String> input) async {
  final info = parse(input.isEmpty ? (List.from(input)..add('-h')) : input);
  final bilibili = Bilibili(info);
  final youtube = Youtube(info);
  print(bilibili.list);
}

ProcessResult bbdown(String address) {
  return Process.runSync(
      'bbdown',
      [
        '$address --encoding-priority "av1,hevc,avc" -F bbdown-<bvid> -M bbdown-<bvid>-<cid>'
      ],
      runInShell: true);
}

class Video {
  Video(this.id, this.title, this.description, {this.categoryId, this.parts});
  String id;
  String title;
  String description;
  String? categoryId;
  List<VideoPart>? parts;
}

class VideoPart {
  VideoPart(this.cid, this.title, {this.playUrl});
  String cid;
  String title;
  String? playUrl;
}

class Bilibili {
  Bilibili(this._info);
  final Config _info;
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
        'cookie': _info.bilibiliCookie,
        'referer': 'https://www.bilibili.com/'
      };
  Future<List<Video>> get list async {
    final client = http.Client();
    Future<List<Map>> getFullVList() async {
      Future<Map> getSearchResults(int pn) async => await client
              .get(
                  await getWbiUri(
                      _info.bilibiliCookie,
                      Uri.parse(
                          '$endpoint/x/space/wbi/arc/search?mid=${_info.bilibiliMemberId}&pn=$pn')),
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
      final initRes = await getSearchResults(1);
      vlist.add(initRes['data']['list']['vlist']);
      for (var pn = 2;
          pn <= int.parse(initRes['data']['page']['count']);
          pn = pn + 1) {
        vlist.add((await getSearchResults(pn))['data']['list']['vlist']);
      }
      return vlist;
    }

    var vlist = await getFullVList();

    List<Video> videoList = [];
    vlist.forEachIndexed((item, index) {
      videoList.add(Video(item['bvid'], item['title'], item['description'],
          categoryId: item['typeid']));
    });

    Future<List<Map>> getParts(String bvid) async => await client
            .get(
                Uri.parse(
                    'https://api.bilibili.com/x/player/pagelist?bvid=$bvid'),
                headers: _headers)
            .catchError((err) => throw err)
            .then((value) => jsonDecode(value.body))
            .then((body) {
          if (body['code'] == 0) {
            return body['data'];
          } else {
            throw json;
          }
        });
    videoList.forEachIndexed((item, index) async {
      final parts = await getParts(item.id);
      List<VideoPart> list = [];
      parts.forEachIndexed((part, index) {
        list.add(VideoPart(part['cid'], part['part']));
      });
      item.parts = list;
    });
    return videoList;
  }
}

class Youtube {
  Youtube(this._info);
  final Config _info;
  Future<AutoRefreshingAuthClient> _client() async {
    var client = http.Client();
    var id =
        ClientId(_info.youtubeOAuthClientId, _info.youtubeOAuthClientSecret);
    var credentials = AccessCredentials(
        AccessToken('Bearer', _info.youtubeOAuthAccessToken, DateTime.now()),
        _info.youtubeOAuthRefreshToken, [
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
        .list(['snippet'], channelId: _info.youtubeChannelId);
    var items = res.items!.where((element) => element.id!.videoId != null);
    List<Video> list = [];
    for (var item in items) {
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
          ..channelId = _info.youtubeChannelId
          ..description = '${item.description}\n(${item.id.hashCode})'
          ..categoryId = item.categoryId);
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
