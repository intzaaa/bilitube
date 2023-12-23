import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

Future<String> encWbi(
    Map<String, dynamic> params, String imgKey, String subKey) async {
  final mixinKeyEncTab = [
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

  String getMixinKey(String orig) {
    return mixinKeyEncTab.map((n) => orig[n]).join('').substring(0, 32);
  }

  final mixinKey = getMixinKey(imgKey + subKey);
  final currTime = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  final chrFilter = RegExp(r"[!'()*]");

  params['wts'] = currTime; // Add wts field

  final query = (params.keys.toList()..sort()) // Sort keys
      .map((key) {
    final value = params[key].toString().replaceAll(chrFilter, '');
    return '${Uri.encodeComponent(key)}=${Uri.encodeComponent(value)}';
  }).join('&');

  final wbiSign =
      md5.convert(utf8.encode(query + mixinKey)).toString(); // Calculate w_rid

  return '$query&w_rid=$wbiSign';
}

Future<({String imgKey, String subKey})> getWbiKeys(String cookie) async {
  final response = await http
      .get(Uri.parse('https://api.bilibili.com/x/web-interface/nav'), headers: {
    'Cookie': cookie,
  });
  final data = jsonDecode(response.body)['data'];
  final imgUrl = data['wbi_img']['img_url'];
  final subUrl = data['wbi_img']['sub_url'];

  final String imgKey =
      imgUrl.substring(imgUrl.lastIndexOf('/') + 1, imgUrl.lastIndexOf('.'));
  final String subKey =
      subUrl.substring(subUrl.lastIndexOf('/') + 1, subUrl.lastIndexOf('.'));

  return (
    imgKey: imgKey,
    subKey: subKey,
  );
}

Future<Uri> getWbiUri(final String cookie, Uri uri) async {
  final webKeys = await getWbiKeys(cookie);
  return Uri.parse(
      '${uri.toString()}&img_key=${webKeys.imgKey}sub_key=&${webKeys.subKey}');
}
