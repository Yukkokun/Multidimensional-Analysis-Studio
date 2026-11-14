'use strict';

/* MA Studio — site script.
 *  · 首屏与功能区的界面演示：读 demo.json（tools/site-data.py 用 mat-cli 导出的真实结果），
 *    在浏览器里按数值现场画 SVG。
 *  · 下载区：读 GitHub Releases，按系统 + 版本 + 芯片拼出直链。
 */

const REPO = 'Yukkokun/Multidimensional-Analysis-Studio';
const GH = `https://github.com/${REPO}`;

const DIMS = [
  { code: 'D1', en: 'Involved vs Informational', zh: '互动 vs 信息' },
  { code: 'D2', en: 'Narrative vs Non-narrative', zh: '叙事 vs 非叙事' },
  { code: 'D3', en: 'Explicit vs Situation-Dependent', zh: '明示 vs 情境依赖' },
  { code: 'D4', en: 'Overt Persuasion', zh: '显性劝说' },
  { code: 'D5', en: 'Abstract vs Non-abstract', zh: '抽象 vs 非抽象' },
  { code: 'D6', en: 'On-line Elaboration', zh: '即时详述' },
];
const GENRE_ZH = {
  Conversations: '对话', Broadcasts: '广播', 'Prepared speeches': '演讲稿', 'Personal letters': '私人书信',
  'General fiction': '小说', 'Press reportage': '新闻', 'Academic prose': '学术', 'Official documents': '公文',
};
const GENRE_SHORT = {
  en: { Conversations: 'Conversat.', Broadcasts: 'Broadcast', 'Prepared speeches': 'Speeches',
        'Personal letters': 'Letters', 'General fiction': 'Fiction', 'Press reportage': 'Press',
        'Academic prose': 'Academic', 'Official documents': 'Official' },
  zh: { Conversations: '对话', Broadcasts: '广播', 'Prepared speeches': '演讲', 'Personal letters': '书信',
        'General fiction': '小说', 'Press reportage': '新闻', 'Academic prose': '学术', 'Official documents': '公文' },
};
const TYPE_ZH = {
  'Intimate interpersonal interaction': '亲密人际互动', 'Informational interaction': '信息性互动',
  'Scientific exposition': '科学说明', 'Learned exposition': '学术说明', 'Imaginative narrative': '想象性叙事',
  'General narrative exposition': '一般叙事说明', 'Situated reportage': '现场报道', 'Involved persuasion': '感染性劝说',
};
const ICON = {
  overview: '<rect x="2" y="2" width="4" height="4" rx="1"/><rect x="8" y="2" width="4" height="4" rx="1"/><rect x="2" y="8" width="4" height="4" rx="1"/><rect x="8" y="8" width="4" height="4" rx="1"/>',
  dimension: '<path d="M3 12V6M7.5 12V3M12 12V8"/>',
  sixdim: '<path d="M2 4h9M2 8h6M2 12h11"/>',
  texttype: '<path d="M2 9l3-4 3 3 4-6"/>',
  feature: '<path d="M2 3h12M2 7h8M2 11h11"/>',
  distribution: '<path d="M2 12c3 0 3-7 6-7s3 7 6 7"/>',
  compare: '<path d="M3 5h10M10 2l3 3-3 3M13 11H3M6 8l-3 3 3 3"/>',
  zcompare: '<rect x="2" y="3" width="12" height="10" rx="1.5"/><path d="M2 7h12M7 3v10"/>',
};
const TAB_ICON = { overview: 'overview', dimension: 'dimension', sixdim: 'sixdim', texttype: 'texttype',
  feature: 'feature', distribution: 'distribution', compare: 'compare', zcompare: 'zcompare' };

const TABS = [
  ['overview', 'Overview', '概览'], ['dimension', 'Dimension', '维度'], ['sixdim', 'Six dims', '六维'],
  ['texttype', 'Text type', '文本类型'], ['feature', 'Feature', '特征'], ['distribution', 'Distribution', '分布'],
  ['compare', 'Compare', '对比'], ['zcompare', 'Z-compare', 'Z 对比'],
];

const UI = {
  en: {
    words: 'words', docs: 'docs', awl: 'avg word length', types: 'types',
    closest: 'Closest text types', feature: 'Feature', meaning: 'Meaning', freq: 'Freq /100w', z: 'z',
    genre: 'Genre', range: 'Range', mean: 'Mean', compare: 'Compare', on: 'on', off: 'off',
    all: 'All', onlyZ: '|z| > 2 only', correction: 'Correction', none: 'None',
    corr: { bh: 'BH-FDR', holm: 'Holm', none: 'None' },
    hist: 'Per-document values', normal: 'Normal curve', descriptive: 'Descriptive',
    sd: 'sd', skew: 'skew', n: 'n', diff: 'Δ', t: 'Welch t', p: 'p', q: 'q',
    zA: 'z', zB: 'z', six: 'Six dimensions', refdata: 'Reference data', ref: 'reference',
    docsLegend: 'documents', perDoc: 'per-document', refTypes: 'reference types', mn: 'mean',
  },
  zh: {
    words: '词', docs: '篇', awl: '平均词长', types: '类符',
    closest: '最接近的文本类型', feature: '特征', meaning: '含义', freq: '每百词', z: 'z 值',
    genre: '体裁', range: '区间', mean: '均值', compare: '对比', on: '开', off: '关',
    all: '全部', onlyZ: '只看 |z| > 2', correction: '校正', none: '不校正',
    corr: { bh: 'BH-FDR', holm: 'Holm', none: '不校正' },
    hist: '逐篇取值', normal: '正态曲线', descriptive: '描述统计',
    sd: '标准差', skew: '偏度', n: '篇数', diff: 'Δ', t: 'Welch t', p: 'p', q: 'q',
    zA: 'z', zB: 'z', six: '六个维度', refdata: '参考数据', ref: '参考体裁',
    docsLegend: '逐篇', perDoc: '逐篇曲线', refTypes: '参考类型', mn: '均值',
  },
};

let LANG = 'en';
let DATA = null;
let MADE = 0;          // 已挂载实例计数，用于生成唯一 id

const t = (k) => (LANG === 'en' ? UI.en[k] : UI.zh[k]);
const esc = (s) => String(s).replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
const fx = (v, d = 2) => (v == null || Number.isNaN(v) ? '—' : (Math.abs(v) < 1e-9 ? 0 : v).toFixed(d));
const f0 = (v) => Math.round(v).toLocaleString('en-US');
const fz = (v) => (Math.abs(v) > 100 ? '⚠' : fx(v, 2));
/** 折线 → 平滑曲线。mac 的文本类型轮廓用 Swift Charts 的 catmullRom，
 *  直着连会显得很硬，这里用同样的 Catmull-Rom 转三次贝塞尔。 */
function smooth(pts) {
  if (pts.length < 2) return '';
  let d = `M${pts[0][0].toFixed(1)},${pts[0][1].toFixed(1)}`;
  for (let i = 0; i < pts.length - 1; i++) {
    const p0 = pts[i - 1] || pts[i];
    const p1 = pts[i];
    const p2 = pts[i + 1];
    const p3 = pts[i + 2] || p2;
    const c1 = [p1[0] + (p2[0] - p0[0]) / 6, p1[1] + (p2[1] - p0[1]) / 6];
    const c2 = [p2[0] - (p3[0] - p1[0]) / 6, p2[1] - (p3[1] - p1[1]) / 6];
    d += `C${c1[0].toFixed(1)},${c1[1].toFixed(1)} ${c2[0].toFixed(1)},${c2[1].toFixed(1)} ${p2[0].toFixed(1)},${p2[1].toFixed(1)}`;
  }
  return d;
}

const mean = (a) => (a.length ? a.reduce((x, y) => x + y, 0) / a.length : 0);
const sd = (a) => {
  if (a.length < 2) return 0;
  const m = mean(a);
  return Math.sqrt(a.reduce((s, v) => s + (v - m) ** 2, 0) / (a.length - 1));
};
const dimName = (i) => (LANG === 'en' ? DIMS[i].en : DIMS[i].zh);
const typeName = (id) => (LANG === 'en' ? id : (TYPE_ZH[id] || id));
const genreName = (id) => (LANG === 'en' ? id : (GENRE_ZH[id] || id));
const genreShort = (id) => GENRE_SHORT[LANG][id] || (LANG === 'en' ? id.slice(0, 9) : genreName(id));

/* ── 语料聚合 ── */
function agg(corpus) {
  const docs = corpus.docs;
  return {
    name: corpus.name,
    docs,
    tokens: docs.reduce((s, d) => s + d.tokens, 0),
    awl: mean(docs.map((d) => d.awl)),
    types: mean(docs.map((d) => d.ttr)),
    dims: [0, 1, 2, 3, 4, 5].map((i) => mean(docs.map((d) => d.dims[i]))),
    lo: [0, 1, 2, 3, 4, 5].map((i) => Math.min(...docs.map((d) => d.dims[i]))),
    hi: [0, 1, 2, 3, 4, 5].map((i) => Math.max(...docs.map((d) => d.dims[i]))),
  };
}
const ranking = (A) => DATA.textTypes
  .map((tt) => ({ id: tt.id, d: Math.sqrt(tt.dimension.reduce((s, v, i) => s + (v - A.dims[i]) ** 2, 0)) }))
  .sort((a, b) => a.d - b.d);
const nearestGenre = (v, dim) => DATA.genres
  .map((g) => ({ id: g.id, d: Math.abs(g.dimension[dim] - v) }))
  .sort((a, b) => a.d - b.d)[0];

function niceTicks(lo, hi, count = 4) {
  const span = hi - lo || 1;
  const raw = span / count;
  const mag = 10 ** Math.floor(Math.log10(raw));
  const step = [1, 2, 2.5, 5, 10].map((m) => m * mag).find((s) => s >= raw) || mag * 10;
  const out = [];
  for (let v = Math.ceil(lo / step) * step; v <= hi + 1e-9; v += step) out.push(Math.round(v * 1e6) / 1e6);
  return out;
}

/* ── 各页 ── */

function pOverview(st) {
  const A = agg(DATA.corpora[0]);
  const rank = ranking(A);
  const maxD = Math.max(...rank.map((r) => r.d));

  const tiles = [
    [t('words'), f0(A.tokens), `${A.docs.length} ${t('docs')}`],
    [t('docs'), A.docs.length, ''],
    [t('awl'), fx(A.awl, 2), ''],
    [t('types'), f0(A.types), ''],
  ].map(([k, v, s]) => `<div class="tile"><div class="k">${k}</div><div class="v">${v}</div><div class="s">${s}</div></div>`).join('');

  const cards = DIMS.map((d, i) => {
    const v = A.dims[i];
    const g = nearestGenre(v, i);
    return `<div class="dimcard" data-goto="${i}" title="${esc(d.en)} → ${esc(genreName(g.id))}">
      <div class="top"><span class="code">${d.code}</span><span class="val">${fx(v, 2)}</span></div>
      <div class="lab">${esc(dimName(i))}</div>
      <div class="lab" style="color:#9A9AA4">≈ ${esc(genreName(g.id))}</div>
    </div>`;
  }).join('');

  const rows = rank.map((r, i) => {
    const w = 100 - (r.d / (maxD || 1)) * 100;
    return `<div style="display:flex;align-items:center;gap:8px;padding:4px 0;border-bottom:1px solid rgba(11,11,15,.04)">
      <span style="width:10px;color:#9A9AA4;font-size:9.5px">${i + 1}</span>
      <span style="flex:1;font-size:11.5px;${i === 0 ? 'font-weight:600' : ''};overflow:hidden;text-overflow:ellipsis;white-space:nowrap">${esc(typeName(r.id))}</span>
      <span style="width:52px;height:4px;background:#EFF0F4;border-radius:2px;overflow:hidden"><span style="display:block;height:100%;width:${w}%;background:${i === 0 ? '#4B57E0' : '#C9CCD8'}"></span></span>
      <span style="width:28px;text-align:right;font-size:9.5px;color:#9A9AA4">${fx(r.d, 1)}</span>
    </div>`;
  }).join('');

  return `<div class="grid4" style="margin-bottom:10px">${tiles}</div>
    <div class="grid2">
      <div class="card"><h3 class="h">${t('six')}</h3><div class="grid3">${cards}</div></div>
      <div class="card"><h3 class="h">${t('closest')}</h3>${rows}</div>
    </div>`;
}

function pDimension(st) {
  const A = agg(DATA.corpora[0]);
  const B = st.compare ? agg(DATA.corpora[1]) : null;
  const series = DATA.genres.map((g) => ({
    key: g.id, label: genreName(g.id), short: genreShort(g.id),
    lo: g.rangeLow[st.dim], hi: g.rangeHigh[st.dim],
    mean: g.dimension[st.dim], kind: 'ref',
  }));
  series.push({ key: 'A', label: A.name, short: A.name.slice(0, 9), lo: A.lo[st.dim], hi: A.hi[st.dim], mean: A.dims[st.dim], kind: 'a' });
  if (B) series.push({ key: 'B', label: B.name, short: B.name.slice(0, 9), lo: B.lo[st.dim], hi: B.hi[st.dim], mean: B.dims[st.dim], kind: 'b' });

  const lo = Math.min(...series.map((s) => s.lo));
  const hi = Math.max(...series.map((s) => s.hi));
  const W = 520, H = 286, PL = 30, PB = 34, PT = 8;
  const y = (v) => PT + ((hi - v) / (hi - lo)) * (H - PT - PB);
  const ticks = niceTicks(lo, hi, 4);

  const grid = ticks.map((v) => {
    const zero = Math.abs(v) < 1e-9;
    return `<line x1="${PL}" x2="${W - 6}" y1="${y(v)}" y2="${y(v)}" stroke="${zero ? '#D6D9E3' : '#F0F1F5'}"/>
      <text x="${PL - 6}" y="${y(v) + 3}" text-anchor="end" font-size="9" fill="#9A9AA4">${v}</text>`;
  }).join('');

  const slot = (W - PL - 8) / series.length;
  const bars = series.map((s, i) => {
    const cx = PL + slot * i + slot / 2;
    const w = s.kind === 'ref' ? 7 : 12;
    const top = y(Math.max(s.lo, s.hi)), bot = y(Math.min(s.lo, s.hi));
    const color = s.kind === 'ref' ? '#BFC4D2' : s.kind === 'a' ? '#4B57E0' : '#B5654A';
    return `<g><title>${esc(s.label)} · ${fx(s.mean, 2)} (${fx(s.lo, 1)} ~ ${fx(s.hi, 1)})</title>
      <rect x="${cx - w / 2}" y="${top}" width="${w}" height="${Math.max(1, bot - top)}" rx="3" fill="${color}" opacity="${s.kind === 'ref' ? .6 : 1}"/>
      <circle cx="${cx}" cy="${y(s.mean)}" r="${s.kind === 'ref' ? 2 : 3}" fill="${s.kind === 'ref' ? '#6B7280' : color}"/>
      <text x="${cx}" y="${H - 32}" text-anchor="middle" font-size="9" fill="#9A9AA4">${esc(s.short || s.label.slice(0, 9))}</text></g>`;
  }).join('');

  const rows = DATA.genres.map((g) => ({
    id: g.id, lo: g.rangeLow[st.dim], hi: g.rangeHigh[st.dim], mean: g.dimension[st.dim],
    distA: Math.abs(g.dimension[st.dim] - A.dims[st.dim]),
    distB: B ? Math.abs(g.dimension[st.dim] - B.dims[st.dim]) : null,
  }));
  const key = st.sort.dim.key, dir = st.sort.dim.dir;
  rows.sort((a, b) => ((a[key] ?? 0) - (b[key] ?? 0)) * dir);

  const head = `<th class="l">${t('genre')}</th><th data-sort="range">${t('range')}</th>
    <th data-sort="mean">${t('mean')}</th><th data-sort="distA">→ ${esc(A.name)}</th>
    ${B ? `<th data-sort="distB">→ ${esc(B.name)}</th>` : ''}`;
  const body = rows.map((r) => `<tr><td>${esc(genreName(r.id))}</td><td>${fx(r.lo, 1)} ~ ${fx(r.hi, 1)}</td>
    <td>${fx(r.mean, 2)}</td><td class="pos">${fx(r.distA, 2)}</td>${B ? `<td class="neg">${fx(r.distB, 2)}</td>` : ''}</tr>`).join('');

  return `<div class="chips">
      ${DIMS.map((d, i) => `<button class="chip" data-dim="${i}" aria-pressed="${i === st.dim}">${d.code}</button>`).join('')}
      <span style="flex:1"></span>
      <button class="chip" data-compare aria-pressed="${!!st.compare}">${t('compare')}: ${st.compare ? t('on') : t('off')}</button>
    </div>
    <div class="card" style="margin-bottom:10px">
      <h3 class="h">${DIMS[st.dim].code} · ${esc(dimName(st.dim))}</h3>
      <svg viewBox="0 0 ${W} ${H}" width="100%" height="${H}">${grid}${bars}</svg>
      <div class="legend"><span><i style="background:#BFC4D2"></i>${t('ref')}</span><span><i style="background:#4B57E0"></i>${esc(A.name)}</span>${B ? `<span><i style="background:#B5654A"></i>${esc(B.name)}</span>` : ''}</div>
    </div>
    <div class="card"><h3 class="h">${t('refdata')}</h3>
      <table class="tbl"><thead><tr>${head}</tr></thead><tbody>${body}</tbody></table></div>`;
}

function pSixdim(st) {
  const A = agg(DATA.corpora[0]);
  const B = st.compare ? agg(DATA.corpora[1]) : null;
  const all = [...DATA.genres.flatMap((g) => [...g.rangeLow, ...g.rangeHigh]), ...A.dims, ...(B ? B.dims : [])];
  const lo = Math.min(...all), hi = Math.max(...all);
  const W = 520, PL = 72, rowH = 34, H = rowH * 6 + 20;
  const x = (v) => PL + ((v - lo) / (hi - lo)) * (W - PL - 14);
  const ticks = niceTicks(lo, hi, 4);
  const grid = ticks.map((v) => `<line x1="${x(v)}" x2="${x(v)}" y1="4" y2="${H - 16}" stroke="${Math.abs(v) < 1e-9 ? '#D6D9E3' : '#F0F1F5'}"/>
    <text x="${x(v)}" y="${H - 4}" text-anchor="middle" font-size="9" fill="#9A9AA4">${v}</text>`).join('');
  const rows = DIMS.map((d, i) => {
    const y0 = 8 + i * rowH;
    const bar = (v, color, off) => `<rect x="${Math.min(x(0), x(v))}" y="${y0 + off}" width="${Math.max(1, Math.abs(x(v) - x(0)))}" height="8" rx="3" fill="${color}"><title>${fx(v, 2)}</title></rect>`;
    return `<text x="${PL - 10}" y="${y0 + 14}" text-anchor="end" font-size="9.5" fill="#6B6B76">${d.code}</text>
      ${bar(A.dims[i], '#4B57E0', 0)}${B ? bar(B.dims[i], '#B5654A', 11) : ''}`;
  }).join('');
  return `<div class="chips"><span style="flex:1"></span>
      <button class="chip" data-compare aria-pressed="${!!st.compare}">${t('compare')}: ${st.compare ? t('on') : t('off')}</button></div>
    <div class="card"><svg viewBox="0 0 ${W} ${H}" width="100%" height="${H}">${grid}${rows}</svg>
      <div class="legend"><span><i style="background:#4B57E0"></i>${esc(A.name)}</span>${B ? `<span><i style="background:#B5654A"></i>${esc(B.name)}</span>` : ''}</div></div>`;
}

function pTexttype(st) {
  const A = agg(DATA.corpora[0]);
  const m = 5;
  const all = [...DATA.textTypes.flatMap((r) => r.dimension.slice(0, m)), ...A.dims.slice(0, m)];
  const lo = Math.min(...all) - 4, hi = Math.max(...all) + 4;
  const W = 520, H = 280, PL = 30, PB = 28, PT = 10;
  const x = (i) => PL + (i / (m - 1)) * (W - PL - 26);
  const y = (v) => PT + ((hi - v) / (hi - lo)) * (H - PT - PB);
  const grid = niceTicks(lo, hi, 4).map((v) => `<line x1="${PL}" x2="${W - 10}" y1="${y(v)}" y2="${y(v)}" stroke="${Math.abs(v) < 1e-9 ? '#D6D9E3' : '#F0F1F5'}"/>
    <text x="${PL - 6}" y="${y(v) + 3}" text-anchor="end" font-size="9" fill="#9A9AA4">${v}</text>`).join('');
  const axis = DIMS.slice(0, m).map((d, i) => `<text x="${x(i)}" y="${H - 7}" text-anchor="middle" font-size="9" fill="#9A9AA4">${d.code}</text>`).join('');
  const pts = (vals) => vals.slice(0, m).map((v, i) => [x(i), y(v)]);
  const refs = DATA.textTypes.map((r) => `<path d="${smooth(pts(r.dimension))}" fill="none" stroke="#C9CCD8" stroke-width="1.2"><title>${esc(typeName(r.id))}</title></path>`).join('');
  const docs = st.docs ? A.docs.map((d) => `<path d="${smooth(pts(d.dims))}" fill="none" stroke="#4B57E0" stroke-width="1" opacity=".14"/>`).join('') : '';
  const line = `<path d="${smooth(pts(A.dims))}" fill="none" stroke="#4B57E0" stroke-width="2.4" stroke-linecap="round"/>
    ${A.dims.slice(0, m).map((v, i) => `<circle cx="${x(i)}" cy="${y(v)}" r="3" fill="#fff" stroke="#4B57E0" stroke-width="2"/>`).join('')}`;
  return `<div class="chips"><button class="chip" data-docs aria-pressed="${!!st.docs}">${t('perDoc')}: ${st.docs ? t('on') : t('off')}</button>
      <span style="flex:1"></span><span style="font-size:10.5px;color:#9A9AA4">${esc(typeName(ranking(A)[0].id))}</span></div>
    <div class="card"><svg viewBox="0 0 ${W} ${H}" width="100%" height="${H}">${grid}${refs}${docs}${line}${axis}</svg>
      <div class="legend"><span><i style="background:#4B57E0"></i>${esc(A.name)} mean</span><span><i style="background:#C9CCD8"></i>${t('refTypes')}</span></div></div>`;
}

function pFeature(st) {
  const A = DATA.corpora[0].docs;
  const rows = DATA.features
    .map((f) => ({ f, freq: mean(A.map((d) => d.freq[f.id] || 0)), z: mean(A.map((d) => d.z[f.id] || 0)) }))
    .filter((r) => st.filter === 'all' || st.filter === 'z2' || r.f.dims.includes(Number(st.filter)))
    .filter((r) => st.filter !== 'z2' || Math.abs(r.z) > 2);
  const key = st.sort.feat.key, dir = st.sort.feat.dir;
  rows.sort((a, b) => ((a[key] ?? 0) - (b[key] ?? 0)) * dir);
  const maxZ = Math.max(2, ...rows.map((r) => Math.min(10, Math.abs(r.z))));
  const body = rows.map((r) => {
    const w = (Math.min(10, Math.abs(r.z)) / maxZ) * 46;
    return `<tr title="z = ${fx(r.z, 2)}"><td><span class="code">${esc(r.f.id)}</span></td>
      <td style="text-align:left">${esc(LANG === 'en' ? r.f.en : r.f.zh)}</td>
      <td>${fx(r.freq, 2)}</td><td class="${r.z >= 0 ? 'pos' : 'neg'}">${fz(r.z)}</td>
      <td style="text-align:left"><span style="display:flex;justify-content:${r.z >= 0 ? 'flex-start' : 'flex-end'}">
        <span style="height:4px;border-radius:2px;width:${w}%;background:${r.z >= 0 ? '#4B57E0' : '#B5654A'};opacity:.7"></span></span></td></tr>`;
  }).join('');
  return `<div class="chips">
      <button class="chip" data-filter="all" aria-pressed="${st.filter === 'all'}">${t('all')}</button>
      ${DIMS.map((d, i) => `<button class="chip" data-filter="${i + 1}" aria-pressed="${st.filter === String(i + 1)}">${d.code}</button>`).join('')}
      <button class="chip" data-filter="z2" aria-pressed="${st.filter === 'z2'}">${t('onlyZ')}</button>
    </div>
    <div class="card table-wrap"><table class="tbl"><thead><tr>
      <th class="l">${t('feature')}</th><th class="l">${t('meaning')}</th>
      <th data-sortf="freq">${t('freq')}</th><th data-sortf="z">${t('z')}</th><th class="l"></th>
    </tr></thead><tbody>${body}</tbody></table></div>`;
}

function pDistribution(st) {
  const vals = DATA.corpora[0].docs.map((d) => d.dims[st.dim]);
  const m = mean(vals), s = sd(vals);
  const lo = Math.min(...vals), hi = Math.max(...vals);
  const pad = Math.max(1, (hi - lo) * 0.15);
  const x0 = lo - pad, x1 = hi + pad, bins = 7, bw = (x1 - x0) / bins;
  const counts = new Array(bins).fill(0);
  vals.forEach((v) => { counts[Math.min(bins - 1, Math.max(0, Math.floor((v - x0) / bw)))]++; });
  const peak = s > 0 ? (1 / (s * Math.sqrt(2 * Math.PI))) * bw * vals.length : 0;
  const yMax = Math.max(...counts, peak, 1);
  const W = 520, H = 250, PL = 30, PB = 24, PT = 12;
  const x = (v) => PL + ((v - x0) / (x1 - x0)) * (W - PL - 12);
  const y = (c) => PT + (1 - c / yMax) * (H - PT - PB);
  const bars = counts.map((c, i) => {
    const l = x(x0 + i * bw), r = x(x0 + (i + 1) * bw);
    return `<rect x="${l + 1}" y="${y(c)}" width="${Math.max(1, r - l - 2)}" height="${H - PB - y(c)}" rx="3" fill="#DCE0F8"><title>${c}</title></rect>`;
  }).join('');
  let pts = [];
  for (let i = 0; i <= 60; i++) {
    const v = x0 + ((x1 - x0) * i) / 60;
    const d = s > 0 ? Math.exp(-((v - m) ** 2) / (2 * s * s)) / (s * Math.sqrt(2 * Math.PI)) : 0;
    pts.push(`${x(v)},${y(d * bw * vals.length)}`);
  }
  const axis = niceTicks(x0, x1, 4).map((v) => `<text x="${x(v)}" y="${H - 5}" text-anchor="middle" font-size="9" fill="#9A9AA4">${v}</text>`).join('');
  const skew = vals.length > 2 && s > 0
    ? (vals.reduce((a, v) => a + ((v - m) / s) ** 3, 0) * vals.length) / ((vals.length - 1) * (vals.length - 2))
    : 0;
  return `<div class="chips">${DIMS.map((d, i) => `<button class="chip" data-dim="${i}" aria-pressed="${i === st.dim}">${d.code}</button>`).join('')}</div>
    <div class="grid2">
      <div class="card"><h3 class="h">${DIMS[st.dim].code} · ${t('hist')}</h3>
        <svg viewBox="0 0 ${W} ${H}" width="100%" height="${H}">${bars}<polyline points="${pts.join(' ')}" fill="none" stroke="#4B57E0" stroke-width="1.8"/>${axis}</svg>
        <div class="legend"><span><i style="background:#DCE0F8"></i>${t('docsLegend')}</span><span><i style="background:#4B57E0"></i>${t('normal')}</span></div></div>
      <div class="card"><h3 class="h">${t('descriptive')}</h3>
        <div class="tile" style="border:0;padding:3px 0"><div class="k">${t('n')}</div><div class="v">${vals.length}</div></div>
        <div class="tile" style="border:0;padding:3px 0"><div class="k">${t('mn')}</div><div class="v">${fx(m, 2)}</div></div>
        <div class="tile" style="border:0;padding:3px 0"><div class="k">${t('sd')}</div><div class="v">${fx(s, 2)}</div></div>
        <div class="tile" style="border:0;padding:3px 0"><div class="k">${t('skew')}</div><div class="v">${fx(skew, 2)}</div></div></div>
    </div>`;
}

/* 多重比较校正，和内核 stats.rs 的 bh() / holm() 同一套算法。
 *   BH  ：从最大的 p 往前累积取最小
 *   Holm：从小到大，q = p × (n − rank + 1)，再累积取最大（单调）
 */
function qvalues(ps, method) {
  const n = ps.length;
  if (method === 'none' || !n) return ps.slice();
  const order = ps.map((_, i) => i).sort((a, b) => ps[a] - ps[b] || a - b);
  const q = new Array(n).fill(1);

  if (method === 'holm') {
    let run = 0;
    for (let rank = 1; rank <= n; rank++) {
      const i = order[rank - 1];
      run = Math.max(run, Math.min(1, ps[i] * (n - rank + 1)));
      q[i] = run;
    }
    return q;
  }

  let run = 1;
  for (let rank = n; rank >= 1; rank--) {
    const i = order[rank - 1];
    run = Math.min(run, Math.min(1, (ps[i] * n) / rank));
    q[i] = run;
  }
  return q;
}

function pCompare(st, mode) {
  const rows = DATA.compare.map((c) => {
    const f = DATA.features.find((x) => x.id === c.id);
    return mode === 'z'
      ? { id: c.id, name: LANG === 'en' ? f.en : f.zh, za: c.za, zb: c.zb, diff: c.za - c.zb, t: c.t, p: c.p }
      : { id: c.id, name: LANG === 'en' ? f.en : f.zh, a: c.a, b: c.b, diff: c.a - c.b, t: c.t, p: c.p };
  });
  const qs = qvalues(rows.map((r) => r.p), st.corr);
  rows.forEach((r, i) => { r.q = qs[i]; });
  const key = st.sort.cmp.key, dir = st.sort.cmp.dir;
  rows.sort((a, b) => ((a[key] ?? 0) - (b[key] ?? 0)) * dir);
  const body = rows.map((r) => `<tr title="t=${fx(r.t, 2)} p=${r.p.toFixed(4)}">
      <td><span class="code">${esc(r.id)}</span></td><td style="text-align:left">${esc(r.name)}</td>
      ${mode === 'z'
        ? `<td class="${r.za >= 0 ? 'pos' : 'neg'}">${fz(r.za)}</td><td class="${r.zb >= 0 ? 'pos' : 'neg'}">${fz(r.zb)}</td>`
        : `<td>${fx(r.a, 2)}</td><td>${fx(r.b, 2)}</td>`}
      <td class="${r.diff >= 0 ? 'pos' : 'neg'}">${fx(r.diff, 2)}</td>
      <td>${fx(r.t, 2)}</td>
      <td style="opacity:${r.q < 0.05 ? 1 : .42}">${r.q < 0.001 ? '<0.001' : r.q.toFixed(3)}</td></tr>`).join('');
  return `<div class="chips">
      <span style="font-size:10px;color:#9A9AA4">${t('correction')}</span>
      ${['bh', 'holm', 'none'].map((k) => `<button class="chip" data-corr="${k}" aria-pressed="${st.corr === k}">${T2(k)}</button>`).join('')}
    </div>
    <div class="card table-wrap"><table class="tbl"><thead><tr>
      <th class="l">${t('feature')}</th><th class="l">${t('meaning')}</th>
      ${mode === 'z' ? `<th>z ${esc(DATA.corpora[0].name)}</th><th>z ${esc(DATA.corpora[1].name)}</th>`
                     : `<th>${esc(DATA.corpora[0].name)}</th><th>${esc(DATA.corpora[1].name)}</th>`}
      <th>${t('diff')}</th><th>${t('t')}</th><th>${t('q')}</th>
    </tr></thead><tbody>${body}</tbody></table></div>`;
}
const T2 = (k) => (LANG === 'en' ? UI.en.corr[k] : UI.zh.corr[k]);

const PAGES = {
  overview: pOverview, dimension: pDimension, sixdim: pSixdim, texttype: pTexttype,
  feature: pFeature, distribution: pDistribution,
  compare: (st) => pCompare(st, 'freq'), zcompare: (st) => pCompare(st, 'z'),
};

/* ── 挂载一个演示实例 ── */
function mount(el, over) {
  const st = Object.assign({
    tab: 'overview', dim: 0, compare: true, corr: 'bh', filter: 'all', docs: true,
    sort: { dim: { key: 'distA', dir: 1 }, feat: { key: 'z', dir: -1 }, cmp: { key: 't', dir: -1 } },
  }, over);

  el.classList.add('pane', 'inst-' + (++MADE));
  const draw = () => { el.innerHTML = PAGES[st.tab](st); };

  el.addEventListener('click', (e) => {
    const n = e.target.closest('[data-dim],[data-compare],[data-docs],[data-filter],[data-corr],[data-goto],[data-sort],[data-sortf]');
    if (!n) return;
    if (n.hasAttribute('data-goto')) { st.dim = Number(n.dataset.goto); st.tab = 'dimension'; draw(); return; }
    if (n.dataset.dim != null) st.dim = Number(n.dataset.dim);
    if (n.hasAttribute('data-compare')) st.compare = !st.compare;
    if (n.hasAttribute('data-docs')) st.docs = !st.docs;
    if (n.dataset.filter) st.filter = n.dataset.filter;
    if (n.dataset.corr) st.corr = n.dataset.corr;
    if (n.dataset.sort) {
      const k = n.dataset.sort;
      st.sort.dim = { key: k, dir: st.sort.dim.key === k ? -st.sort.dim.dir : (k === 'range' ? 1 : 1) };
    }
    if (n.dataset.sortf) {
      const k = n.dataset.sortf;
      st.sort.feat = { key: k, dir: st.sort.feat.key === k ? -st.sort.feat.dir : -1 };
    }
    draw();
  });

  draw();
  return { redraw: draw, state: st };
}

/* ── 首屏：完整窗口 + 页签 ── */
let heroInstance = null;
function mountHero() {
  const tabsEl = document.getElementById('hero-tabs');
  const paneEl = document.getElementById('hero-pane');
  if (!tabsEl || !paneEl) return;

  tabsEl.innerHTML = TABS.map(([id, en, zh]) => {
    const p = ICON[TAB_ICON[id]] || '';
    return `<button class="tab" data-tab="${id}"><svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.4" stroke-linecap="round" stroke-linejoin="round">${p}</svg>${LANG === 'en' ? en : zh}</button>`;
  }).join('');
  tabsEl.querySelectorAll('.tab').forEach((b) => {
    b.setAttribute('aria-selected', 'false');
    b.addEventListener('click', () => {
      heroInstance.state.tab = b.dataset.tab;
      tabsEl.querySelectorAll('.tab').forEach((x) => x.setAttribute('aria-selected', String(x === b)));
      heroInstance.redraw();
      const A = agg(DATA.corpora[0]);
      document.getElementById('hero-name').textContent = A.name;
      document.getElementById('hero-meta').textContent = meta(A);
    });
  });
  tabsEl.querySelector('.tab').setAttribute('aria-selected', 'true');

  paneEl.innerHTML = '';
  heroInstance = mount(paneEl, { tab: 'overview' });

  const A = agg(DATA.corpora[0]);
  document.getElementById('hero-name').textContent = A.name;
  document.getElementById('hero-meta').textContent = meta(A);
}
const meta = (A) => LANG === 'en'
  ? `${A.docs.length} docs · ${f0(A.tokens)} words · TTR 400 · z clamp off · Biber features`
  : `${A.docs.length} 篇 · ${f0(A.tokens)} 词 · TTR 400 · z 不截断 · Biber 特征`;

/* ── 下载区 ── */
const FALLBACK = [{
  tag: 'version-1.3.2', version: '1.3.2', date: '2026-11-13',
  assets: [
    { name: 'MAStudio-1.3.2-win-x64.zip', size: 4178355 },
    { name: 'MA-Studio-1.3.2-macOS12-universal.dmg', size: 8188968 },
    { name: 'MA-Studio-1.3.2.dmg', size: 6737674 },
    { name: 'MA-Studio-Windows-source.zip', size: 538000 },
    { name: 'MA-Studio-1.3.2-source.zip', size: 1846099 },
  ],
}];

const DLO = { os: 'windows', chip: 'universal', releases: [], pick: 0 };

function classify(assets) {
  const find = (re) => assets.find((a) => re.test(a.name));
  return {
    windows: find(/win-x64\.zip$/i),
    macUni: find(/macOS12-universal\.dmg$/i),
    macArm: find(/^MA-Studio-[\d.]+\.dmg$/i),
    srcWin: find(/Windows-source\.zip$/i),
    srcMac: find(/^MA-Studio-[\d.]+-source\.zip$/i),
    srcMacUni: find(/macOS12-universal-source\.zip$/i),
  };
}

function guessOS() {
  const ua = navigator.userAgent || '';
  if (/Windows/i.test(ua)) return 'windows';
  return 'mac';
}

async function loadReleases() {
  try {
    const r = await fetch(`https://api.github.com/repos/${REPO}/releases?per_page=8`, { headers: { Accept: 'application/vnd.github+json' } });
    if (!r.ok) throw new Error(r.status);
    const list = await r.json();
    const out = list
      .filter((x) => !x.draft && x.assets && x.assets.length)
      .map((x) => ({
        tag: x.tag_name,
        version: String(x.tag_name).replace(/^version-?|^v/, ''),
        date: (x.published_at || '').slice(0, 10),
        assets: x.assets.map((a) => ({ name: a.name, size: a.size })),
      }));
    if (out.length) return out;
  } catch (e) { /* 离线或限流：用内置清单 */ }
  return FALLBACK;
}

function bytes(n) {
  if (!n) return '';
  return n > 1e6 ? (n / 1048576).toFixed(1) + ' MB' : Math.round(n / 1024) + ' KB';
}

function pickAsset(rel) {
  const c = classify(rel.assets);
  if (DLO.os === 'windows') return c.windows;
  return DLO.chip === 'arm' ? c.macArm : c.macUni;
}

function paintDownload() {
  const rel = DLO.releases[DLO.pick];
  if (!rel) return;
  const sel = document.getElementById('dl-version');
  if (sel && !sel.options.length) {
    sel.innerHTML = DLO.releases.map((r, i) => `<option value="${i}">${r.version}${i === 0 ? ' · latest' : ''}</option>`).join('');
    sel.value = '0';
  }

  document.querySelectorAll('#dl-os button').forEach((b) => b.setAttribute('aria-pressed', String(b.dataset.os === DLO.os)));
  document.querySelectorAll('#dl-chip button').forEach((b) => b.setAttribute('aria-pressed', String(b.dataset.chip === DLO.chip)));
  document.getElementById('dl-chip-field').style.display = DLO.os === 'mac' ? '' : 'none';

  const asset = pickAsset(rel);
  const base = `${GH}/releases/download/${rel.tag}/${asset ? asset.name : ''}`;
  const label = document.getElementById('dl-primary-label');
  const file = document.getElementById('dl-primary-file');
  const main = document.getElementById('dl-primary');
  const hint = document.getElementById('dl-hint');

  if (!asset) {
    main.href = `${GH}/releases/tag/${rel.tag}`;
    label.textContent = LANG === 'en' ? 'See this release' : '查看这个版本';
    file.textContent = '';
    hint.textContent = LANG === 'en' ? 'No build for this platform in this version.' : '这个版本没有对应平台的构建。';
  } else {
    main.href = base;
    label.textContent = (LANG === 'en' ? 'Download for ' : '下载：') +
      (DLO.os === 'windows' ? 'Windows' : DLO.chip === 'arm' ? 'macOS · Apple silicon' : 'macOS · Universal');
    file.textContent = `${asset.name} · ${bytes(asset.size)}`;
    hint.textContent = DLO.os === 'windows'
      ? (LANG === 'en' ? 'Windows 10 / 11, 64-bit · portable zip, no installer, no Java required.' : 'Windows 10 / 11 64 位 · 免安装 zip，不需要 Java。')
      : (LANG === 'en' ? 'macOS 12 or later · universal runs on Intel and Apple silicon.' : 'macOS 12 及以上 · 通用版同时支持 Intel 与 Apple 芯片。');
  }

  const c = classify(rel.assets);
  const src = DLO.os === 'windows' ? c.srcWin : (DLO.chip === 'arm' ? c.srcMac : c.srcMacUni);
  const srcEl = document.getElementById('dl-source');
  srcEl.href = src ? `${GH}/releases/download/${rel.tag}/${src.name}` : `${GH}/releases`;
  document.getElementById('dl-source-size').textContent = src ? bytes(src.size) : '';
  document.getElementById('dl-notes').href = `${GH}/releases/tag/${rel.tag}`;

  const lead = document.getElementById('dl-lead');
  if (lead) {
    lead.textContent = LANG === 'en'
      ? 'We picked the build for your system. Every version stays on GitHub, and source ships with each one (GPLv3 §6).'
      : '已经按你的系统选好了。所有版本都留在 GitHub，每个版本都附带源码（GPLv3 第 6 条）。';
  }
}

function bindDownload() {
  document.querySelectorAll('#dl-os button').forEach((b) => b.addEventListener('click', () => {
    DLO.os = b.dataset.os;
    paintDownload();
  }));
  document.querySelectorAll('#dl-chip button').forEach((b) => b.addEventListener('click', () => {
    DLO.chip = b.dataset.chip;
    paintDownload();
  }));
  const sel = document.getElementById('dl-version');
  if (sel) sel.addEventListener('change', () => { DLO.pick = Number(sel.value) || 0; paintDownload(); });
}

/* ── 语言 ── */
function applyLang(lang) {
  LANG = lang === 'zh' ? 'zh' : 'en';
  document.documentElement.lang = LANG === 'en' ? 'en' : 'zh-CN';
  document.title = LANG === 'en'
    ? 'MA Studio — Multidimensional Analysis, done right'
    : 'MA Studio — 多维分析，做得像样';
  document.querySelectorAll('[data-zh]').forEach((el) => {
    const v = el.getAttribute('data-' + LANG);
    if (v != null) el.innerHTML = v;
  });
  document.querySelectorAll('.lang button').forEach((b) => b.setAttribute('aria-pressed', String(b.dataset.lang === LANG)));

  if (DATA) {
    // 允许 URL 预置状态，方便分享某一张图 / 自己核对算法
    const qp = new URLSearchParams(location.search);
    const corr = qp.get('corr') || 'bh';
    mountHero();
    ['overview', 'dimension', 'texttype', 'feature', 'zcompare'].forEach((k) => {
      const el = document.getElementById('app-' + k);
      if (el) mount(el, { tab: k, compare: true, corr });
    });
    paintDownload();
  }
}

/* ── 启动 ── */
async function boot() {
  document.querySelectorAll('.lang button').forEach((b) =>
    b.addEventListener('click', () => applyLang(b.dataset.lang)));

  const copy = document.getElementById('copy');
  if (copy) copy.addEventListener('click', async () => {
    try {
      await navigator.clipboard.writeText(document.getElementById('bib').textContent);
      const old = copy.textContent;
      copy.textContent = '✓';
      setTimeout(() => { copy.textContent = old; }, 1200);
    } catch (e) { /* 剪贴板不可用就算了 */ }
  });

  DLO.os = guessOS();
  DLO.releases = await loadReleases();
  bindDownload();

  try {
    DATA = await (await fetch('demo.json')).json();
  } catch (e) {
    console.error('demo data failed to load', e);
  }

  const q = new URLSearchParams(location.search).get('lang');
  const stored = (() => { try { return localStorage.getItem('ma-lang'); } catch (e) { return null; } })();
  applyLang(q || stored || 'en');
}
document.addEventListener('DOMContentLoaded', boot);
