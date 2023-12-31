library wbi;

import 'dart:convert';
import 'package:dartx/dartx.dart';
import 'package:path/path.dart' as path;
import 'package:http/http.dart' as http;
import 'package:uri/uri.dart';

void main(List<String> args) async {
  final originalUri =
      Uri.parse(args.isEmpty ? 'https://bilibili.com' : args[0]);
  final uri = await originalUri.toWbiUri();
  print(uri.query);
  if ((args.isNotEmpty) &&
      (originalUri.queryParameters['w_rid'] == uri.queryParameters['w_rid'])) {
    print('test passed.');
  }
}

extension WbiUri on Uri {
  Future<Uri> toWbiUri() async {
    // 构造 UriBuilder
    final uri = UriBuilder.fromUri(this);

    // 移除已有的 wRid
    /// 代码 if (uri.queryParameters['w_rid'] != null) uri.queryParameters.remove('w_rid');` 正在检查 URI
    /// 的查询参数中是否存在查询参数 'w_rid'。如果存在，则会从 URI 中删除“w_rid”查询参数。
    if (uri.queryParameters['w_rid'] != null) {
      uri.queryParameters.remove('w_rid');
    }

    // 获取wts
    /// 该代码片段检查“uri.queryParameters”映射中是否存在“wts”查询参数。
    String? wts = uri.queryParameters['wts'];
    if (wts != null) {
      uri.queryParameters.remove('wts');
    } else {
      wts = (DateTime.now().millisecondsSinceEpoch / 1000).round().toString();
    }

    // 得到 imgKey 和 subKey
    /// 该代码向 URL“https://api.bilibili.com/x/web-interface/nav”发出 HTTP GET
    /// 请求并检索响应正文。然后使用“jsonDecode”函数将响应正文解析为 JSON。然后，代码从 JSON
    /// 响应中提取“img_url”和“sub_url”的值，并使用“path.basenameWithoutExtension”函数删除文件扩展名。最后，将“imgKey”和“subKey”的值分配给提取的值。
    final (imgKey, subKey) = (await http
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

    // 拼接 imgKey 和 subKey
    /// 该代码片段连接“imgKey”和“subKey”变量的值以形成“rawWbiKey”字符串。然后，它使用“Sign.mixinKeyEncTab”列表作为查找表，将“rawWbiKey”中的每个字符映射到新字符。然后将映射的字符连接在一起形成新的字符串“wbiKey”。最后，代码使用“slice”方法对“wbiKey”的前
    /// 32 个字符进行切片。
    final rawWbiKey = imgKey + subKey;
    final wbiKey = Sign.mixinKeyEncTab
        .map((e) => rawWbiKey[e])
        .join('')
        // 截取前32位
        .slice(0, 31);

    // 按键名升序排序
    final String query = (uri.queryParameters..addAll({'wts': wts}))
        .toList()
        // 实施 Uri Encode
        .map((e) =>
            Pair(Uri.encodeComponent(e.first), Uri.encodeComponent(e.second)))
        .sortedWith((a, b) => Comparable.compare(a.first, b.first))
        .map((e) => '${e.first}=${e.second}')
        .join('&');

    // URL Query 拼接 wbiKey 并计算 MD5，即为wRid
    final wRid = (query + wbiKey).md5;

    // 将 wRid 添加到原 URL Query 中
    uri.queryParameters.addAll({'w_rid': wRid, 'wts': wts});

    // 返回结果 Uri
    return uri.build();
  }
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
