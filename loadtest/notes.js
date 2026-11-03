import http from 'k6/http';
import { check, sleep } from 'k6';

const vus = Number(__ENV.VUS || 15);
export const options = {
  stages: [
    { duration: '3m', target: vus }, { duration: '5m', target: vus }, { duration: '2m', target: 0 },
  ],
  summaryTrendStats: ['med', 'p(95)', 'p(99)'],
};

export function setup() {
  const login = http.post(`${__ENV.BASE_URL}/auth/login`, JSON.stringify({
    username: __ENV.ADMIN_USERNAME || 'admin', password: __ENV.ADMIN_PASSWORD,
  }), { headers: { 'Content-Type': 'application/json' } });
  if (login.status !== 200) throw new Error(login.body);
  return { token: login.json('access_token') };
}

export default function (data) {
  const base = __ENV.BASE_URL;
  const headers = { Authorization: `Bearer ${data.token}`, 'Content-Type': 'application/json' };
  const created = http.post(`${base}/notes`, JSON.stringify({ text: `load-${__VU}-${__ITER}` }), { headers });
  check(created, { 'write 200': (r) => r.status === 200 });
  const id = created.json('id'), author = created.json('author');
  for (let i = 0; i < 9; i++) {
    const path = ['/notes', `/notes/${id}`, `/authors/${author}`][i % 3];
    check(http.get(base + path), { 'read 200': (r) => r.status === 200 });
  }
  sleep(1);
}
