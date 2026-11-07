// Exercise demonstration player: admin-uploaded licensed video first, otherwise the YouTube tutorial.
import React, { useState } from 'react';
import { YT } from '../data/videos';
import { Icon } from '../ui';
import { isNative } from '../lib/extras';
import { update } from '../lib/store';

export function ytUrl(id: string) { return `https://www.youtube.com/watch?v=${id}`; }

export function DemoVideo({ exId, name, custom, compact }: { exId: string; name: string; custom?: string; compact?: boolean }) {
  const [playing, setPlaying] = useState(false);
  const [thumbOk, setThumbOk] = useState(true);
  const yt = YT[exId];
  if (custom) return <video className="demo-video" src={custom} controls playsInline preload="metadata" />;
  if (!yt) return <a className="demo-link" href={`https://www.youtube.com/results?search_query=${encodeURIComponent(name + ' proper form')}`} target="_blank" rel="noreferrer">Search form videos on YouTube ↗</a>;
  // Inline playback inside the Android app (and normal browsers); sandboxed previews fall back to opening YouTube.
  const canEmbed = isNative() || !/claudeusercontent|claude\.ai/.test(location.hostname + document.referrer);
  return (
    <div className={'yt' + (compact ? ' compact' : '')}>
      {playing && canEmbed ? (
        <iframe className="yt-frame" src={`https://www.youtube-nocookie.com/embed/${yt}?autoplay=1&rel=0&modestbranding=1&playsinline=1`}
          title={`${name} demonstration`} allow="autoplay; encrypted-media; picture-in-picture; fullscreen" allowFullScreen referrerPolicy="strict-origin-when-cross-origin" />
      ) : (
        <button className="yt-thumb" onClick={() => { update((d) => { d.settings.watchedDemo = true; }); if (canEmbed) setPlaying(true); else window.open(ytUrl(yt), '_blank'); }} aria-label={`Play ${name} demonstration`}>
          {thumbOk ? <img src={`https://i.ytimg.com/vi/${yt}/hqdefault.jpg`} alt="" onError={() => setThumbOk(false)} /> : <div className="yt-ph"><b>{name}</b><small>Video demonstration</small></div>}
          <span className="yt-play"><Icon n="play" s={26} fill /></span>
          <span className="yt-badge">▶ Watch demo</span>
        </button>
      )}
      <div className="yt-foot"><small>Real-person tutorial on YouTube · needs internet</small><a href={ytUrl(yt)} target="_blank" rel="noreferrer">Open in YouTube ↗</a></div>
    </div>
  );
}
