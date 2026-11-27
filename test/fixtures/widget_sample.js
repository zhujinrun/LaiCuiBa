// A minimal CapyPlayer-compatible widget used by the live runtime test.
var WidgetMetadata = {
  id: 'fixture_widget',
  title: '测试组件',
  description: '本地夹具，不走网络',
  version: '1.0.0',
  icon: 'https://example.com/widget.png',
  modules: [
    {
      id: 'popular',
      title: '热门',
      type: 'media_list',
      functionName: 'getPopular',
      cacheDuration: 3600,
      params: [{ name: 'page', label: '页码', type: 'page' }],
    },
  ],
};

async function getPopular(params) {
  console.log('widget fixture page', params.page);
  return [
    {
      id: 'fixture-1',
      title: '夹具影片一',
      posterUrl: 'https://example.com/1.webp',
      mediaType: 'movie',
      videoUrl: 'https://example.com/1.m3u8',
    },
    {
      id: 'fixture-2',
      title: '夹具影片二',
      name: 'unused',
      media_type: 'tv',
      link: 'https://example.com/detail/2',
    },
  ];
}

async function loadDetail(link) {
  console.log('widget fixture detail', link);
  return {
    title: '夹具详情',
    mediaType: 'tv',
    seasons: [
      {
        seasonNumber: 1,
        episodes: [
          {
            episodeNumber: 1,
            title: '第一集',
            playSources: [
              { title: '线路一', videoUrl: 'https://example.com/s1e1-line1.m3u8' },
              { title: '线路二', videoUrl: 'https://example.com/s1e1-line2.m3u8' },
            ],
          },
        ],
      },
    ],
    tags: ['悬疑', '国产'],
    credits: { cast: [{ name: '演员甲' }] },
  };
}
