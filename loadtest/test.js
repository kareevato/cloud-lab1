import http from 'k6/http';
import { check } from 'k6';
import { Rate } from 'k6/metrics';

const cacheHit = new Rate('cache_hit_ratio');

export const options = {
  stages: [
    { duration: '3m', target: 60 },
    { duration: '5m', target: 60 },
    { duration: '2m', target: 0 },
  ],
  summaryTrendStats: ['avg', 'med', 'p(95)', 'p(99)', 'max'],
};

const readParams = {
  headers: __ENV.NOCACHE ? { 'Cache-Control': 'no-cache' } : {},
  tags: { name: 'GET /notes/:id' },
};

const read = (url) => {
  const res = http.get(url, readParams);
  check(res, { 'read 200': (r) => r.status === 200 });
  if (!__ENV.NOCACHE) {
    cacheHit.add(res.headers['X-Cache'] === 'HIT');
  }
};

export function setup() {
  const login = http.post(`${__ENV.BASE_URL}/auth/login`, JSON.stringify({
    username: __ENV.ADMIN_USERNAME || 'admin',
    password: __ENV.ADMIN_PASSWORD,
  }), { headers: { 'Content-Type': 'application/json' } });
  if (login.status !== 200) throw new Error(login.body);
  return { token: login.json('access_token') };
}

export default function (data) {
  const base = __ENV.BASE_URL;
  const created = http.post(base + '/notes', JSON.stringify({
    text: 'Load test ' + __VU + '-' + __ITER,
  }), {
    headers: {
      'Content-Type': 'application/json',
      Authorization: 'Bearer ' + data.token,
    },
    tags: { name: 'POST /notes' },
  });
  const ok = check(created, { 'created 200': (r) => r.status === 200 });
  if (!ok) {
    return;
  }

  const id = created.json('id');
  read(base + '/notes/' + id);

  for (let i = 1; i <= 8; i++) {
    read(base + '/notes/' + Math.max(1, id - i));
  }
}
