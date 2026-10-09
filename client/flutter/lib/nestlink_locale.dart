import 'dart:io';
import 'package:flutter/foundation.dart';
import 'models/platform_model.dart';

final nestlinkLanguage = ValueNotifier<String>('zh-cn');
bool get nestlinkEnglish => nestlinkLanguage.value == 'en';
String nl(String chinese, String english) =>
    nestlinkEnglish ? english : chinese;

void loadNestLinkLanguage() {
  final saved = bind.mainGetLocalOption(key: 'lang');
  nestlinkLanguage.value = saved == 'en' ||
          (saved.isEmpty && !Platform.localeName.toLowerCase().startsWith('zh'))
      ? 'en'
      : 'zh-cn';
}

Future<void> setNestLinkLanguage(String language) async {
  if (!['zh-cn', 'en'].contains(language)) return;
  await bind.mainSetLocalOption(key: 'lang', value: language);
  await bind.mainChangeLanguage(lang: language);
  nestlinkLanguage.value = language;
}
