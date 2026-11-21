import 'package:media_kit/media_kit.dart';

import 'track_choice.dart';

/// 一次 `Tracks` 事件的映射结果：面板要显示的选项，加上切换时得交回给播放器
/// 的原始轨道对象。
///
/// 单独抽出来是因为「显示哪几条」和「按 id 切哪一条」必须是同一个判断——否则
/// 面板上写着「粤语」，点下去切换的却是另一条轨。播放页和 `tool/
/// verify_tracks_live.dart` 都用这一份，所以真机验证校验的就是界面的规则。
///
/// mpv 的 `auto` / `no` 在这里被丢掉：它们是控制词，不是轨道。
class MappedTracks {
  MappedTracks(Tracks tracks) {
    for (final t in tracks.video) {
      if (_isVerb(t.id)) continue;
      _videoById[t.id] = t;
      video.add(
        TrackOption(
          id: t.id,
          title: t.title,
          language: t.language,
          codec: t.codec,
          width: t.w,
          height: t.h,
        ),
      );
    }
    for (final t in tracks.audio) {
      if (_isVerb(t.id)) continue;
      _audioById[t.id] = t;
      audio.add(
        TrackOption(
          id: t.id,
          title: t.title,
          language: t.language,
          codec: t.codec,
          channels: t.channelscount ?? t.audiochannels,
        ),
      );
    }
    for (final t in tracks.subtitle) {
      if (_isVerb(t.id)) continue;
      _subById[t.id] = t;
      subtitle.add(
        TrackOption(
          id: t.id,
          title: t.title,
          language: t.language,
          codec: t.codec,
          external: t.uri || t.data,
        ),
      );
    }
  }

  final video = <TrackOption>[];
  final audio = <TrackOption>[];
  final subtitle = <TrackOption>[];

  final _videoById = <String, VideoTrack>{};
  final _audioById = <String, AudioTrack>{};
  final _subById = <String, SubtitleTrack>{};

  bool get isEmpty => video.isEmpty && audio.isEmpty && subtitle.isEmpty;

  VideoTrack? videoTrack(String id) => _videoById[id];
  AudioTrack? audioTrack(String id) => _audioById[id];

  /// `no` 是「关掉字幕」，不需要原始对象。
  SubtitleTrack? subtitleTrack(String id) =>
      id == 'no' ? SubtitleTrack.no() : _subById[id];

  /// 把面板选项和「当前正在用的」合起来，给 [TrackPanel] 用。
  TrackChoices choicesFor(Track current) => TrackChoices(
    video: video,
    audio: audio,
    subtitle: subtitle,
    videoId: current.video.id,
    audioId: current.audio.id,
    subtitleId: current.subtitle.id,
  );

  @override
  String toString() =>
      'MappedTracks(video: ${video.map((t) => t.label).toList()}, '
      'audio: ${audio.map((t) => t.label).toList()}, '
      'subtitle: ${subtitle.map((t) => t.label).toList()})';
}

bool _isVerb(String id) => id == 'auto' || id == 'no';
