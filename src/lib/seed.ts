// Sample community content so the feed is not empty on first launch in on-device mode.
// Every sample account is clearly labelled "Sample" in the UI. Images are generated artwork, not photos of real people.
import type { Post, SocialUser, Comment } from './store';

export function art(title: string, sub: string, a: string, b: string, emoji: string) {
  const svg = `<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 600 600'><defs><linearGradient id='g' x1='0' y1='0' x2='1' y2='1'><stop offset='0' stop-color='${a}'/><stop offset='1' stop-color='${b}'/></linearGradient></defs><rect width='600' height='600' fill='url(#g)'/><circle cx='480' cy='110' r='160' fill='white' opacity='.08'/><circle cx='90' cy='520' r='200' fill='black' opacity='.12'/><text x='50' y='300' font-size='120'>${emoji}</text><text x='50' y='420' font-family='system-ui,Segoe UI,Roboto' font-weight='800' font-size='54' fill='white'>${title}</text><text x='50' y='475' font-family='system-ui,Segoe UI,Roboto' font-size='30' fill='white' opacity='.85'>${sub}</text></svg>`;
  return 'data:image/svg+xml;utf8,' + encodeURIComponent(svg);
}

export function seedSocial(): { users: SocialUser[]; posts: Post[]; comments: Comment[] } {
  const users: SocialUser[] = [
    { id: 's-coach', name: 'FITVERSE Coach Team', username: 'fitverse', bio: 'Official tips, programmes and challenges.', avatarColor: '#C6FF3D', private: false, sample: true, creator: true },
    { id: 's-anu', name: 'Anu (sample)', username: 'anu_lifts', bio: 'Powerlifting · Kochi · deadlift enjoyer', avatarColor: '#FF5A36', private: false, sample: true },
    { id: 's-rahul', name: 'Rahul (sample)', username: 'rahul.runs', bio: 'Half-marathons and home workouts.', avatarColor: '#4FC3F7', private: false, sample: true },
    { id: 's-fathima', name: 'Fathima (sample)', username: 'fathima.fit', bio: 'Recomp journey, 1 year in. Puttu and protein.', avatarColor: '#B388FF', private: true, sample: true },
    { id: 's-arjun', name: 'Arjun (sample)', username: 'arjun_ppl', bio: 'PPL 6x/week. Coach in training.', avatarColor: '#FFB020', private: false, sample: true, creator: true },
  ];
  const h = 3600e3; const now = Date.now();
  const posts: Post[] = [
    { id: 'p1', userId: 's-coach', ts: now - 2 * h, kind: 'tip', text: 'Protein tip 🇮🇳 Kerala breakfast upgrade: puttu + kadala curry + 2 boiled eggs ≈ 30 g protein. Swap half the puttu for extra kadala on fat-loss days.', media: [{ art: art('Breakfast upgrade', 'Puttu · Kadala · Eggs', '#1b5e20', '#C6FF3D', '🍳'), type: 'image' }], likes: 128 },
    { id: 'p2', userId: 's-anu', ts: now - 5 * h, kind: 'workout', text: 'Pull day done. Deadlift felt smooth today — kept the bar close and stayed patient off the floor. #consistency', media: [], workout: { name: 'Pull — Back & Biceps', volume: 8420, minutes: 64, exercises: 6 }, likes: 54 },
    { id: 'p3', userId: 's-rahul', ts: now - 9 * h, kind: 'challenge', text: 'Day 12 of the 30-day push-up challenge. 32 reps today, all with a straight body line. Who else is in?', media: [{ art: art('Day 12 / 30', 'Push-up challenge', '#0d47a1', '#4FC3F7', '💪'), type: 'image' }], likes: 77 },
    { id: 'p4', userId: 's-arjun', ts: now - 26 * h, kind: 'tip', text: 'No leg press at home? Bulgarian split squats with a chair are brutal and brilliant. Open any gym exercise in FITVERSE and tap "Home version".', media: [{ art: art('No machine? No excuse.', 'Leg press → Bulgarian split squat', '#e65100', '#FFB020', '🦵'), type: 'image' }], likes: 211 },
    { id: 'p5', userId: 's-fathima', ts: now - 30 * h, kind: 'transformation', text: '12 months of recomposition. Scale moved only 3 kg but waist is down 9 cm. Measure more than just weight!', media: [{ art: art('Month 0 → 12', 'Waist −9 cm · Weight −3 kg', '#4a148c', '#B388FF', '🔄'), type: 'image' }], likes: 342 },
    { id: 'p6', userId: 's-coach', ts: now - 50 * h, kind: 'tip', text: 'Hydration reminder 💧 In hot, humid weather you may need more than your base target, especially on training days. Pale-yellow urine is a simple practical check.', media: [], likes: 96 },
  ];
  const comments: Comment[] = [
    { id: 'c1', postId: 'p2', userId: 's-arjun', text: 'Clean pull! What did you hit on deadlift?', ts: now - 4 * h },
    { id: 'c2', postId: 'p2', userId: 's-anu', text: '@arjun_ppl 140 × 3, RPE 8 🙌', ts: now - 3.5 * h, parentId: 'c1' },
    { id: 'c3', postId: 'p5', userId: 's-rahul', text: 'This is the motivation I needed.', ts: now - 28 * h },
  ];
  return { users, posts, comments };
}
