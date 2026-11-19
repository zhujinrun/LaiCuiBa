import 'package:flutter/material.dart';

import '../models/models.dart';

/// Fixture data mirrored from a live BieCuiLe 1.0.6 session so the rebuilt UI can
/// be compared against the original frame by frame. Replaced by the source layer
/// in a later phase.
const List<MediaItem> heroItems = [
  MediaItem(
    id: 'ama',
    title: '给阿嬷的情书',
    score: 9.3,
    tag: 'TC国语',
    year: 2025,
    posterSeed: 0,
    overview: '一封迟到四十年的信，把三代人的秘密重新摊开在潮汕的老宅里。',
  ),
  MediaItem(
    id: 'spiderman',
    title: '蜘蛛侠：崭新之日',
    score: 7.7,
    tag: 'TC中字',
    year: 2026,
    posterSeed: 1,
    overview: '新的城市，新的身份，旧的选择题又一次摆在他面前。',
  ),
  MediaItem(
    id: 'baxian',
    title: '八仙!',
    tag: '枪版',
    year: 2026,
    posterSeed: 2,
    overview: '八个人，八种执念，一条渡不过去的河。',
  ),
  MediaItem(
    id: 'teliduxing',
    title: '特立独行',
    score: 6.6,
    tag: '正片',
    year: 2025,
    posterSeed: 3,
    overview: '',
  ),
  MediaItem(
    id: 'shanggongzhu',
    title: '尚公主',
    score: 8.1,
    tag: '全40集',
    year: 2026,
    posterSeed: 4,
  ),
];

const List<ContinueWatching> continueWatching = [
  ContinueWatching(
    media: MediaItem(
      id: 'shanggongzhu',
      title: '尚公主',
      score: 8.1,
      posterSeed: 4,
    ),
    episodeLabel: '第39集',
    positionMs: 31000,
    durationMs: 2880000,
  ),
];

const List<HomeSection> homeSections = [
  HomeSection(
    title: '电影',
    items: [
      MediaItem(id: 'm1', title: '八仙!', tag: '枪版', score: 6.9, posterSeed: 2),
      MediaItem(id: 'm2', title: '特立独行', tag: '正片', score: 6.6, posterSeed: 3),
      MediaItem(id: 'm3', title: '捕风追影', tag: 'HD', score: 8.0, posterSeed: 5),
      MediaItem(id: 'm4', title: '长安的荔枝', tag: 'HD', score: 8.4, posterSeed: 6),
      MediaItem(id: 'm5', title: '浪浪山小妖怪', tag: 'TC', score: 8.8, posterSeed: 7),
      MediaItem(id: 'm6', title: '南京照相馆', tag: 'HD', score: 9.1, posterSeed: 1),
    ],
  ),
  HomeSection(
    title: '电视剧',
    items: [
      MediaItem(id: 't1', title: '尚公主', tag: '全40集', score: 8.1, posterSeed: 4),
      MediaItem(id: 't2', title: '给阿嬷的情书', tag: 'TC国语', score: 9.3, posterSeed: 0),
      MediaItem(id: 't3', title: '许我耀眼', tag: '全32集', score: 7.8, posterSeed: 5),
      MediaItem(id: 't4', title: '国色芳华', tag: '全40集', score: 8.3, posterSeed: 2),
      MediaItem(id: 't5', title: '藏海传', tag: '全40集', score: 8.6, posterSeed: 6),
    ],
  ),
  HomeSection(
    title: '动漫',
    items: [
      MediaItem(id: 'a1', title: '诡秘之主', tag: '更新至12集', score: 8.9, posterSeed: 7),
      MediaItem(id: 'a2', title: '牧神记', tag: '更新至86集', score: 8.7, posterSeed: 0),
      MediaItem(id: 'a3', title: '仙逆', tag: '更新至102集', score: 8.5, posterSeed: 3),
      MediaItem(id: 'a4', title: '吞噬星空', tag: '更新至180集', score: 8.2, posterSeed: 1),
    ],
  ),
];

/// Sidebar model: four groups with a label each, matching the original.
const List<(String, List<(IconData, String, LcbPage)>)> navGroups = [
  ('媒体库', [(Icons.home_outlined, '首页', LcbPage.home)]),
  ('来源', [(Icons.video_library_outlined, '资源', LcbPage.resources)]),
  (
    '列表',
    [
      (Icons.favorite_border, '收藏', LcbPage.favorites),
      (Icons.history, '历史', LcbPage.history),
    ]
  ),
  ('其他', [(Icons.settings_outlined, '设置', LcbPage.settings)]),
];
