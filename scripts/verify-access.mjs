// Run with a JSON object on stdin, never passwords in command-line arguments.
// { url, key, email, password, newPassword }
// Changes the account password as part of verifying first-login activation.
let rawInput = '';
for await (const chunk of process.stdin) rawInput += chunk.toString();
const input = JSON.parse(rawInput);
const { url, key, email, password, newPassword } = input;
let token;
async function request(path, { method = 'GET', body, authenticated = false } = {}) {
  const r = await fetch(url + path, {
    method,
    headers: { apikey: key, 'Content-Type': 'application/json', ...(authenticated ? { Authorization: `Bearer ${token}` } : {}) },
    ...(body ? { body: JSON.stringify(body) } : {}),
  });
  const text = await r.text();
  return { status: r.status, data: text ? JSON.parse(text) : null };
}
function assert(ok, message) { if (!ok) throw new Error(message); }
const checks = [];
const signedOut = await request('/rest/v1/programmes?select=id');
assert([401,403].includes(signedOut.status), 'Signed-out users could access programme data'); checks.push('Anonymous data access denied');
const noAuthFunction = await request('/functions/v1/people-account', { method: 'POST', body: { action: 'update-member' } });
assert(noAuthFunction.status === 401, 'Account endpoint accepted a request without authentication'); checks.push('Account endpoint requires verified authentication');
const login = await request('/auth/v1/token?grant_type=password', { method: 'POST', body: { email, password } });
assert(login.status === 200 && login.data.access_token, 'Password authentication failed'); token = login.data.access_token; checks.push('Superadmin password login verified');
const own = await request(`/rest/v1/memberships?select=*&user_id=eq.${login.data.user.id}`, { authenticated: true });
assert(own.status === 200 && own.data.length === 1 && own.data[0].needs_password_change, 'First-login password requirement missing');
const before = await request('/rest/v1/programmes?select=id', { authenticated: true });
assert(before.status === 200 && before.data.length === 0, 'Temporary-password user can read staffing data'); checks.push('Data blocked until temporary password is changed');
const escalation = await request(`/rest/v1/memberships?user_id=eq.${login.data.user.id}`, { method: 'PATCH', authenticated: true, body: { needs_password_change: false } });
assert([401,403].includes(escalation.status), 'Browser client could alter privileged membership fields'); checks.push('Client cannot bypass membership/password restrictions');
const change = await request('/functions/v1/people-account', { method: 'POST', authenticated: true, body: { action: 'change-password', password: newPassword } });
assert(change.status === 200 && change.data.success, `Password change failed: ${JSON.stringify(change.data)}`); checks.push('First-login password change endpoint verified');
const signedInAgain = await request('/auth/v1/token?grant_type=password', { method: 'POST', body: { email, password: newPassword } });
assert(signedInAgain.status === 200 && signedInAgain.data.access_token, 'Could not establish a fresh session after password change');
token = signedInAgain.data.access_token; checks.push('Fresh session established after password change');
const programmes = await request('/rest/v1/programmes?select=*', { authenticated: true });
assert(programmes.status === 200 && programmes.data.length === 5, 'Activated admin cannot read programme data');
assert(programmes.data.reduce((s,p)=>s+p.donor_posts,0) === 132 && programmes.data.reduce((s,p)=>s+p.current_staff,0) === 154, 'Staffing baseline failed reconciliation'); checks.push('Five programmes reconcile to 132 funded posts and 154 staff');
const budgets = await request('/rest/v1/monthly_budgets?select=id', { authenticated: true });
assert(budgets.status === 200 && budgets.data.length === 0, 'Unexpected budget data'); checks.push('Budget starts empty; no invented monetary figures');
const selfChange = await request('/functions/v1/people-account', { method: 'POST', authenticated: true, body: { action: 'update-member', user_id: login.data.user.id, role: 'viewer', active: false } });
assert(selfChange.status === 400, `Self-demotion protection returned an unexpected response: ${selfChange.status} ${JSON.stringify(selfChange.data)}`); checks.push('Administrator self-demotion protection verified');
const logout = await request('/auth/v1/logout?scope=global', { method: 'POST', authenticated: true });
assert(logout.status === 204, 'Test session sign-out failed'); checks.push('Test refresh session revoked');
console.log(JSON.stringify({ passed: checks.length, checks }));
