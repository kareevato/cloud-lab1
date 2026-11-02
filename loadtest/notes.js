// Профіль «мало записів, багато читань»: 1 запис і 9 читань на ітерацію.
// Фази: 3 хв зростання, 5 хв плато, 2 хв спад. Разом 10 хвилин.
import http from 'k6/http';
import { check, sleep } from 'k6';
import { Counter } from 'k6/metrics';

const cacheHits = new Counter('cache_hits');
const cacheMisses = new Counter('cache_misses');
const vus = Number(__ENV.VUS || 15);

export const options = {
  stages: [
    { duration: '3m', target: vus },
    { duration: '5m', target: vus },
    { duration: '2m', target: 0 },
  ],
  summaryTrendStats: ['avg', 'min', 'med', 'p(50)', 'p(95)', 'p(99)', 'max', 'count'],
};

function cacheHeader(response) {
  return response.headers['X-Cache'] || response.headers['x-cache'] || '';
}

function noteCache(response) {
  const value = cacheHeader(response);
  if (value === 'HIT') cacheHits.add(1);
  if (value === 'MISS') cacheMisses.add(1);
}

export function setup() {
  const base = __ENV.BASE_URL;
  const response = http.post(
    `${base}/auth/login`,
    JSON.stringify({
      username: __ENV.ADMIN_USERNAME || 'admin',
      password: __ENV.ADMIN_PASSWORD,
    }),
    { headers: { 'Content-Type': 'application/json' } },
  );
  if (response.status !== 200) {
    throw new Error(`login failed: ${response.status} ${response.body}`);
  }
  return { token: response.json('access_token') };
}

export default function (data) {
  const base = __ENV.BASE_URL;
  const headers = {
    Authorization: `Bearer ${data.token}`,
    'Content-Type': 'application/json',
  };
  const created = http.post(
    `${base}/notes`,
    JSON.stringify({ text: `load-${__VU}-${__ITER}` }),
    { headers, tags: { op: 'write' } },
  );
  const wrote = check(created, { 'write status 200': (r) => r.status === 200 });
  if (!wrote) {
    sleep(1);
    return;
  }

  const id = created.json('id');
  const author = created.json('author');
  const reads = [
    () => http.get(`${base}/notes`, { tags: { op: 'read' } }),
    () => http.get(`${base}/notes/${id}`, { tags: { op: 'read' } }),
    () => http.get(`${base}/authors/${author}`, { tags: { op: 'read' } }),
    () => http.get(`${base}/notes`, { tags: { op: 'read' } }),
    () => http.get(`${base}/notes/${id}`, { tags: { op: 'read' } }),
    () => http.get(`${base}/notes`, { tags: { op: 'read' } }),
    () => http.get(`${base}/authors/${author}`, { tags: { op: 'read' } }),
    () => http.get(`${base}/notes`, { tags: { op: 'read' } }),
    () => http.get(`${base}/notes/${id}`, { tags: { op: 'read' } }),
  ];
  for (const call of reads) {
    const response = call();
    noteCache(response);
    check(response, { 'read status 200': (r) => r.status === 200 });
  }
  sleep(1);
}
