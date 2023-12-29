library wbi;

import 'dart:convert';
import 'package:dartx/dartx.dart';
import 'package:path/path.dart' as path;
import 'package:http/http.dart' as http;
import 'package:uri/uri.dart';

void main(List<String> args) async {
  final uri = await getWbiUri(
      Uri.parse(args.isEmpty ? 'https://bilibili.com' : args[0]));
  print(uri.query);
}

Future<Uri> getWbiUri(Uri originalUri) async {
  // 构造 UriBuilder
  final uri = UriBuilder.fromUri(originalUri);

  // 移除已有的 wRid
  if (uri.queryParameters['w_rid'] != null) uri.queryParameters.remove('w_rid');

  // 获取wts
  String? wts = uri.queryParameters['wts'];
  if (wts != null) {
    uri.queryParameters.remove('wts');
  } else {
    wts = (DateTime.now().millisecondsSinceEpoch / 1000).round().toString();
  }

  // 构造 http 客户端
  final client = http.Client();

  // 得到 imgKey 和 subKey
  final (imgKey, subKey) = (await client
      .get(Uri.parse('https://api.bilibili.com/x/web-interface/nav'))
      .then((value) => jsonDecode(value.body))
      .then((value) {
    try {
      return (
        path.basenameWithoutExtension(value['data']['wbi_img']['img_url']),
        path.basenameWithoutExtension(value['data']['wbi_img']['sub_url'])
      );
    } catch (e) {
      throw value;
    }
  }));
  // print('imgKey: $imgKey');
  // print('subKey: $subKey');

  // 拼接 imgKey 和 subKey
  final rawWbiKey = imgKey + subKey;
  final wbiKey = Sign.mixinKeyEncTab
      .map((e) => rawWbiKey[e])
      .join('')
      // 截取前32位
      .slice(0, 31);
  // print('wbiKey: $wbiKey');

  // 按键名升序排序
  final String query = (uri.queryParameters..addAll({'wts': wts}))
      .toList()
      .sortedWith((a, b) => Comparable.compare(a.first, b.first))
      .map((e) => '${e.first}=${e.second}')
      .join('&');
  // print('query: $query');

  // URL Query 拼接 wbiKey 并计算 MD5，即为wRid
  // print(uri.build().query + wbiKey);
  final wRid = (query + wbiKey).md5;

  // 将 wRid 添加到原 URL Query 中
  uri.queryParameters.addAll({'w_rid': wRid, 'wts': wts});

  // 关闭 http 客户端
  client.close();

  // 返回结果 Uri
  return uri.build();
}

class Sign {
  static const List<int> mixinKeyEncTab = [
    46,
    47,
    18,
    2,
    53,
    8,
    23,
    32,
    15,
    50,
    10,
    31,
    58,
    3,
    45,
    35,
    27,
    43,
    5,
    49,
    33,
    9,
    42,
    19,
    29,
    28,
    14,
    39,
    12,
    38,
    41,
    13,
    37,
    48,
    7,
    16,
    24,
    55,
    40,
    61,
    26,
    17,
    0,
    1,
    60,
    51,
    30,
    4,
    22,
    25,
    54,
    21,
    56,
    59,
    6,
    63,
    57,
    62,
    11,
    36,
    20,
    34,
    44,
    52
  ];
}
