import 'package:flutter/material.dart';

import '../models/models.dart';

/// Fixture data mirrored from a live BieCuiLe 1.0.6 session so the rebuilt UI can
/// be compared against the original frame by frame. Replaced by the source layer
/// in a later phase.
///
/// Order and copy follow the original home feed at 1920x1040: eight cards per
/// rail, overflowing the 1680 content column so the horizontal scroll shows.
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
    score: 7.9,
    tag: 'TC抢先版',
    year: 2026,
    posterSeed: 1,
    overview: '新的城市，新的身份，旧的选择题又一次摆在他面前。',
  ),
  MediaItem(
    id: 'baxian',
    title: '八仙!',
    tag: '热映',
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
      MediaItem(id: 'm1', title: '欢迎来龙餐馆', posterSeed: 8),
      MediaItem(id: 'm2', title: '蜘蛛侠：崭新之日', tag: 'TC抢先版', score: 7.9, posterSeed: 1),
      MediaItem(id: 'm3', title: '奥德赛', tag: '预告', score: 8.8, posterSeed: 9),
      MediaItem(id: 'm4', title: '八仙!', tag: '枪版', score: 6.9, posterSeed: 2),
      MediaItem(id: 'm5', title: '特立独行', tag: '正片', score: 6.6, posterSeed: 3),
      MediaItem(id: 'm6', title: '给阿嬷的情书', tag: 'TC国语', score: 9.3, posterSeed: 0),
      MediaItem(id: 'm7', title: '功夫女足', tag: 'TC抢先版', score: 8.8, posterSeed: 10),
      MediaItem(id: 'm8', title: '年会不能停!2', posterSeed: 11),
      MediaItem(id: 'm9', title: '捕风追影', tag: 'HD', score: 8.0, posterSeed: 5),
    ],
  ),
  HomeSection(
    title: '电视剧',
    items: [
      MediaItem(id: 't1', title: '谷雨', tag: '第40集', score: 8.1, posterSeed: 12),
      MediaItem(id: 't2', title: '走马上任', tag: '第40集(全)', score: 6.3, posterSeed: 13),
      MediaItem(id: 't3', title: '尚公主', tag: '第40集(全)', score: 8.1, posterSeed: 4),
      MediaItem(id: 't4', title: '小城良方', tag: '第2集(全)', score: 7.0, posterSeed: 14),
      MediaItem(id: 't5', title: '今天是太阳雨', tag: '第24集(全)', score: 8.4, posterSeed: 15),
      MediaItem(id: 't6', title: '焊金钗', tag: '第16集(全)', score: 6.5, posterSeed: 16),
      MediaItem(id: 't7', title: '伟大的长征', tag: '第60集', score: 9.9, posterSeed: 17),
      MediaItem(id: 't8', title: '折月亮', tag: '第20集(全)', score: 8.8, posterSeed: 18),
    ],
  ),
  HomeSection(
    title: '动漫',
    items: [
      MediaItem(id: 'a1', title: '凡人修仙传', tag: '更新至200集', score: 8.5, posterSeed: 19),
      MediaItem(id: 'a2', title: '仙逆 年番', tag: '第167集', score: 8.9, posterSeed: 20),
      MediaItem(id: 'a3', title: '牧神记', tag: '第108集', score: 8.6, posterSeed: 21),
      MediaItem(id: 'a4', title: '斗破苍穹 年番', tag: '第195集', score: 8.8, posterSeed: 22),
      MediaItem(id: 'a5', title: '仙逆', tag: '第167集', score: 8.9, posterSeed: 23),
      MediaItem(id: 'a6', title: '光阴之外', tag: '第48集', score: 7.5, posterSeed: 24),
      MediaItem(id: 'a7', title: '吞噬星空', tag: '更新至250集', score: 8.2, posterSeed: 25),
      MediaItem(id: 'a8', title: '斗罗大陆2：绝世唐门', tag: '第146集', score: 7.8, posterSeed: 26),
    ],
  ),
  HomeSection(
    title: '综艺',
    items: [
      MediaItem(id: 'v1', title: '现在谁出发第四季', tag: '2026-11-15 起每周六', score: 8.4, posterSeed: 27),
      MediaItem(id: 'v2', title: '后会友期', tag: '2026-11-19 下', score: 7.6, posterSeed: 28),
      MediaItem(id: 'v3', title: '现在谁出发 第二季', tag: '2026-11-15 起每周六(6)', score: 8.1, posterSeed: 29),
      MediaItem(id: 'v4', title: '你好星期六', tag: '2026-11-14', score: 7.9, posterSeed: 30),
      MediaItem(id: 'v5', title: '现在谁出发 第三季', tag: '2026-02-19 起每周日', score: 7.4, posterSeed: 31),
      MediaItem(id: 'v6', title: '现在谁出发', tag: '2023-09-10 起每周日', score: 7.8, posterSeed: 32),
      MediaItem(id: 'v7', title: '音乐缘计划3', tag: '2026-11-14 起每周五', score: 8.7, posterSeed: 33),
      MediaItem(id: 'v8', title: '我家那闺女2026', tag: '2026-11-14 起每周六', score: 7.2, posterSeed: 34),
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
