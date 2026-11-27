import 'package:flutter/rendering.dart' show BoxFit;

/// 播放页「画面比例」档位，对齐原版 BieCuiLe 的六档。
///
/// 短码存进 [AppSettings]（`aspectFit`），BoxFit 是渲染值，标签与说明是面板
/// 文案。原版六档原文（app.so UTF-16LE）：
///   原始比例 = 保持视频原始比例，完整显示画面
///   拉伸全屏 = 拉伸到屏幕边缘，不保留原始比例
///   拉伸铺满 = 保持原始比例铺满屏幕，边缘可能被裁掉
///   宽度拉伸 = 宽度铺满，高度等比放大，超出部分裁掉
///   高度拉伸 = 高度铺满，宽度等比放大，超出部分裁掉
///   裁剪铺满 = 按短边铺满后居中裁剪
enum AspectMode {
  fit('fit', '自适应', '保持视频原始比例，完整显示画面', BoxFit.contain),
  stretch('stretch', '拉伸全屏', '拉伸到屏幕边缘，不保留原始比例', BoxFit.fill),
  fill('fill', '裁剪铺满', '保持原始比例铺满屏幕，边缘可能被裁掉', BoxFit.cover),
  fitWidth('fitWidth', '宽度拉伸', '宽度铺满，高度等比放大，超出部分裁掉', BoxFit.fitWidth),
  fitHeight('fitHeight', '高度拉伸', '高度铺满，宽度等比放大，超出部分裁掉', BoxFit.fitHeight),
  crop('crop', '居中裁剪', '按短边铺满后居中裁剪', BoxFit.cover);

  const AspectMode(this.slug, this.label, this.description, this.boxFit);

  /// 存进设置的短码。
  final String slug;

  final String label;
  final String description;
  final BoxFit boxFit;

  /// 从短码还原。认不出退回原始比例，写坏一个偏好不该拖垮播放页。
  static AspectMode parse(String? slug) {
    for (final m in AspectMode.values) {
      if (m.slug == slug) return m;
    }
    return AspectMode.fit;
  }
}

/// 播放页「画面调节」的五个量：亮度 / 对比度 / 饱和度 / 色相 / 伽马。
///
/// 值域全部是**百分比**，0 = 原始画面（原版文案「0% 是原始画面；这里的亮度
/// 和屏幕亮度分开」）。每个量对应一个 mpv 属性，播放页用 `set <prop> <value>`
/// 下发。
///
/// mpv 属性原生值域：brightness / contrast / saturation / gamma 都是
/// -100..100（0 为原始），hue 也是 -100..100。所以这里直接存 -100..100 的
/// 整数百分比，不额外换算。
class PictureAdjust {
  const PictureAdjust({
    this.brightness = 0,
    this.contrast = 0,
    this.saturation = 0,
    this.hue = 0,
    this.gamma = 0,
  });

  static const none = PictureAdjust();

  final int brightness;
  final int contrast;
  final int saturation;
  final int hue;
  final int gamma;

  /// 全部回到原始画面。
  bool get isNeutral =>
      brightness == 0 &&
      contrast == 0 &&
      saturation == 0 &&
      hue == 0 &&
      gamma == 0;

  PictureAdjust copyWith({
    int? brightness,
    int? contrast,
    int? saturation,
    int? hue,
    int? gamma,
  }) => PictureAdjust(
    brightness: brightness ?? this.brightness,
    contrast: contrast ?? this.contrast,
    saturation: saturation ?? this.saturation,
    hue: hue ?? this.hue,
    gamma: gamma ?? this.gamma,
  );

  /// 每个滑块要下发的一组 mpv 属性：`(属性名, -100..100 的值)`。
  List<(String, int)> get mpvProperties => [
    ('brightness', brightness),
    ('contrast', contrast),
    ('saturation', saturation),
    ('hue', hue),
    ('gamma', gamma),
  ];

  Map<String, int> toJson() => {
    'brightness': brightness,
    'contrast': contrast,
    'saturation': saturation,
    'hue': hue,
    'gamma': gamma,
  };

  factory PictureAdjust.fromJson(Map<String, dynamic>? json) {
    if (json == null) return PictureAdjust.none;
    int at(String k) {
      final v = json[k];
      if (v is int) return v.clamp(-100, 100);
      if (v is num) return v.toInt().clamp(-100, 100);
      return 0;
    }

    return PictureAdjust(
      brightness: at('brightness'),
      contrast: at('contrast'),
      saturation: at('saturation'),
      hue: at('hue'),
      gamma: at('gamma'),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is PictureAdjust &&
      other.brightness == brightness &&
      other.contrast == contrast &&
      other.saturation == saturation &&
      other.hue == hue &&
      other.gamma == gamma;

  @override
  int get hashCode =>
      Object.hash(brightness, contrast, saturation, hue, gamma);
}
