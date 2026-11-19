import 'package:flutter/cupertino.dart';

import '../models/models.dart';

/// Fixture data lifted from a live BieCuiLe 1.0.6 session: the same source, the
/// same titles and the same cached artwork, so the rebuilt home feed can be
/// compared with the original frame by frame. Replaced by the real source layer
/// in a later phase.

/// Douban scores the original shows beside each banner, read off the running
/// app (八仙！ has no entry in the cache, so it carries no badge there either).
const List<MediaItem> heroItems = [
  MediaItem(
      id: 'b0', title: '欢迎来龙餐馆', tag: '枪版', score: 8.7,
      image: 'assets/demo/b0.jpg'),
  MediaItem(
      id: 'b1', title: '蜘蛛侠：崭新之日', tag: 'TC中字', score: 7.7,
      image: 'assets/demo/b1.jpg'),
  MediaItem(
      id: 'b2', title: '奥德赛', tag: '枪版', score: 6.1,
      image: 'assets/demo/b2.jpg'),
  MediaItem(id: 'b3', title: '八仙！', tag: '枪版', image: 'assets/demo/b3.jpg'),
  MediaItem(
      id: 'b4', title: '特立独行', tag: '正片', score: 6.6,
      image: 'assets/demo/b4.jpg'),
  MediaItem(
      id: 'b5', title: '给阿嬷的情书', tag: 'TC国语', score: 9.3,
      image: 'assets/demo/b5.jpg'),
];

const List<ContinueWatching> continueWatching = [
  ContinueWatching(
    media: MediaItem(id: 'cont0', title: '尚公主', image: 'assets/demo/cont0.webp'),
    episodeLabel: '第39集',
    positionMs: 31840,
    durationMs: 2905400,
  ),
];

const List<HomeSection> homeSections = [
  HomeSection(
    title: '电影',
    items: [
    MediaItem(id: 'movie0', title: '欢迎来龙餐馆', tag: '枪版', image: 'assets/demo/movie0.jpg'),
    MediaItem(id: 'movie1', title: '蜘蛛侠：崭新之日', tag: 'TC中字', image: 'assets/demo/movie1.jpg'),
    MediaItem(id: 'movie2', title: '奥德赛', tag: '枪版', image: 'assets/demo/movie2.jpg'),
    MediaItem(id: 'movie3', title: '八仙！', tag: '枪版', image: 'assets/demo/movie3.jpg'),
    MediaItem(id: 'movie4', title: '特立独行', tag: '正片', image: 'assets/demo/movie4.jpg'),
    MediaItem(id: 'movie5', title: '给阿嬷的情书', tag: 'TC国语', image: 'assets/demo/movie5.jpg'),
    MediaItem(id: 'movie6', title: '功夫女足', tag: 'TC国语v2', image: 'assets/demo/movie6.jpg'),
    MediaItem(id: 'movie7', title: '年会不能停！2', tag: '正片', image: 'assets/demo/movie7.jpg'),
    MediaItem(id: 'movie8', title: '一个部门的诞生', tag: '粤语版', image: 'assets/demo/movie8.webp'),
    MediaItem(id: 'movie10', title: '毒战行动', tag: '正片', image: 'assets/demo/movie10.webp'),
    MediaItem(id: 'movie11', title: '新生化危机', tag: 'HD中英双字', image: 'assets/demo/movie11.jpg'),
    MediaItem(id: 'movie14', title: '后室', tag: '正片', image: 'assets/demo/movie14.jpg'),
    ],
  ),
  HomeSection(
    title: '电视剧',
    items: [
    MediaItem(id: 'tv0', title: '谷雨', tag: '第30集', image: 'assets/demo/tv0.webp'),
    MediaItem(id: 'tv1', title: '走马上任', tag: '第40集(全)', image: 'assets/demo/tv1.webp'),
    MediaItem(id: 'tv2', title: '尚公主', tag: '第40集(全)', image: 'assets/demo/tv2.webp'),
    MediaItem(id: 'tv3', title: '小城良方', tag: '第29集(全)', image: 'assets/demo/tv3.webp'),
    MediaItem(id: 'tv4', title: '今天是太阳雨', tag: '第24集(全)', image: 'assets/demo/tv4.webp'),
    MediaItem(id: 'tv5', title: '嫁金钗', tag: '第30集(全)', image: 'assets/demo/tv5.webp'),
    MediaItem(id: 'tv6', title: '伟大的长征', tag: '第60集', image: 'assets/demo/tv6.webp'),
    MediaItem(id: 'tv7', title: '折月亮', tag: '第27集(全)', image: 'assets/demo/tv7.webp'),
    MediaItem(id: 'tv8', title: '玉簟秋', tag: '第40集(全)', image: 'assets/demo/tv8.webp'),
    MediaItem(id: 'tv9', title: '兰香如故', tag: '第47集(全)', image: 'assets/demo/tv9.webp'),
    MediaItem(id: 'tv12', title: '鉴定', tag: '第48集', image: 'assets/demo/tv12.webp'),
    MediaItem(id: 'tv13', title: '蒸蒸日上', tag: '第22集(全)', image: 'assets/demo/tv13.webp'),
    MediaItem(id: 'tv14', title: '美人余', tag: '第28集(全)', image: 'assets/demo/tv14.webp'),
    ],
  ),
  HomeSection(
    title: '动漫',
    items: [
    MediaItem(id: 'anime0', title: '凡人修仙传', tag: '第200集', image: 'assets/demo/anime0.jpg'),
    MediaItem(id: 'anime1', title: '仙逆 年番', tag: '第167集', image: 'assets/demo/anime1.jpg'),
    MediaItem(id: 'anime2', title: '牧神记', tag: '第109集', image: 'assets/demo/anime2.jpg'),
    MediaItem(id: 'anime3', title: '斗破苍穹 年番', tag: '第219集', image: 'assets/demo/anime3.jpg'),
    MediaItem(id: 'anime4', title: '仙逆', tag: '第167集', image: 'assets/demo/anime4.jpg'),
    MediaItem(id: 'anime5', title: '光阴之外', tag: '第48集', image: 'assets/demo/anime5.jpg'),
    MediaItem(id: 'anime6', title: '吞噬星空', tag: '第250集', image: 'assets/demo/anime6.jpg'),
    MediaItem(id: 'anime7', title: '斗罗大陆2：绝世唐门', tag: '第179集', image: 'assets/demo/anime7.jpg'),
    MediaItem(id: 'anime8', title: '遮天', tag: '第190集', image: 'assets/demo/anime8.jpg'),
    MediaItem(id: 'anime9', title: '沧元图3', tag: '第36集', image: 'assets/demo/anime9.png'),
    MediaItem(id: 'anime10', title: '诛仙第四季', tag: '第15集', image: 'assets/demo/anime10.webp'),
    ],
  ),
  HomeSection(
    title: '综艺',
    items: [
    MediaItem(id: 'show0', title: '现在就出发第四季', tag: '第20261119期花絮特辑', image: 'assets/demo/show0.webp'),
    MediaItem(id: 'show1', title: '后会友期', tag: '20261119下', image: 'assets/demo/show1.webp'),
    MediaItem(id: 'show2', title: '现在就出发 第二季', tag: '20250119游戏特辑(全)', image: 'assets/demo/show2.jpg'),
    MediaItem(id: 'show3', title: '你好星期六', tag: '20261114', image: 'assets/demo/show3.jpg'),
    MediaItem(id: 'show4', title: '现在就出发 第三季', tag: '20260201特辑', image: 'assets/demo/show4.jpg'),
    MediaItem(id: 'show5', title: '现在就出发', tag: '20239010(全)', image: 'assets/demo/show5.jpg'),
    MediaItem(id: 'show6', title: '音乐缘计划3', tag: '20261119第3期抢鲜', image: 'assets/demo/show6.webp'),
    MediaItem(id: 'show7', title: '我家那闺女2026', tag: '第20261116期 加更版', image: 'assets/demo/show7.webp'),
    MediaItem(id: 'show8', title: '哈哈哈哈哈第六季', tag: '20260706精编回顾', image: 'assets/demo/show8.webp'),
    MediaItem(id: 'show9', title: '花儿与少年第八季', tag: '第20261115期 加更', image: 'assets/demo/show9.webp'),
    MediaItem(id: 'show11', title: '喜剧之王单口季第三季', tag: '第20260907期第10期衍生', image: 'assets/demo/show11.webp'),
    ],
  ),
];

/// Sidebar model: four groups with a label each, matching the original. The
/// original draws its navigation glyphs from CupertinoIcons, not Material Icons,
/// so the shapes are kept here rather than swapped for near equivalents.
const List<(String, List<(IconData, String, LcbPage)>)> navGroups = [
  ('媒体库', [(CupertinoIcons.home, '首页', LcbPage.home)]),
  ('来源', [(CupertinoIcons.tray_2, '资源', LcbPage.resources)]),
  (
    '列表',
    [
      (CupertinoIcons.heart, '收藏', LcbPage.favorites),
      (CupertinoIcons.clock, '历史', LcbPage.history),
    ]
  ),
  ('其他', [(CupertinoIcons.gear, '设置', LcbPage.settings)]),
];
