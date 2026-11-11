import { createClient } from 'npm:@supabase/supabase-js@2.119.0';

const allowedOrigins = new Set([
  'https://peepul-people-planning.rohanchemical.chatgpt.site',
  'https://peepul-people-planning.pages.dev',
  'http://localhost:5173', 'http://127.0.0.1:5173',
  'http://localhost:4173', 'http://127.0.0.1:4173',
]);

Deno.serve(async (req: Request) => {
  const origin = req.headers.get('origin') || '';
  // Non-browser clients still require a valid user access token below.
  const allowed = !origin || allowedOrigins.has(origin) || /^https:\/\/[a-z0-9-]+\.preview\.chatgpt\.site$/.test(origin);
  const cors = { 'Access-Control-Allow-Origin': allowed && origin ? origin : 'https://peepul-people-planning.rohanchemical.chatgpt.site', 'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type', 'Access-Control-Allow-Methods': 'POST, OPTIONS', 'Vary': 'Origin', 'Cache-Control': 'no-store' };
  const reply = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers: { ...cors, 'Content-Type': 'application/json' } });
  if (!allowed) return reply({ error: 'Origin not permitted.' }, 403);
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  if (req.method !== 'POST') return reply({ error: 'Method not allowed.' }, 405);
  const token = req.headers.get('authorization')?.replace(/^Bearer\s+/i, '');
  if (!token) return reply({ error: 'Sign in to continue.' }, 401);
  const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!, { auth: { persistSession: false, autoRefreshToken: false } });
  const { data: { user }, error: authError } = await admin.auth.getUser(token);
  if (authError || !user) return reply({ error: 'Your session has expired. Please sign in again.' }, 401);
  const { data: member, error: memberError } = await admin.from('memberships').select('*').eq('user_id', user.id).single();
  if (memberError || !member?.active) return reply({ error: 'Workspace access has not been approved.' }, 403);
  let body;
  try { body = await req.json(); } catch { return reply({ error: 'Invalid request.' }, 400); }
  try {
    if (body.action === 'change-password') {
      const password = body.password;
      if (typeof password !== 'string' || password.length < 14 || password.length > 128 || !/[A-Z]/.test(password) || !/[a-z]/.test(password) || !/[0-9]/.test(password)) return reply({ error: 'Use 14–128 characters with uppercase and lowercase letters and a number.' }, 400);
      const { error } = await admin.auth.admin.updateUserById(user.id, { password });
      if (error) return reply({ error: error.message }, 400);
      const { error: updateError } = await admin.from('memberships').update({ needs_password_change: false, last_changed_by: user.id }).eq('user_id', user.id);
      if (updateError) return reply({ error: 'Password changed, but workspace activation could not be completed. Retry or contact your administrator.' }, 500);
      return reply({ success: true });
    }
    if (member.needs_password_change) return reply({ error: 'Change your temporary password first.' }, 403);
    const validRoles = ['superadmin','data_admin','leadership','programme_manager'];
    if (body.action === 'create-user') {
      if (member.role !== 'superadmin') return reply({ error: 'Superadmin access required.' }, 403);
      const email = String(body.email || '').trim().toLowerCase();
      const name = String(body.display_name || '').trim();
      if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) || !name || name.length > 120 || !validRoles.includes(body.role)) return reply({ error: 'Provide a valid email, name and role.' }, 400);
      if (body.role === 'programme_manager' && !body.programme_id) return reply({ error: 'Assign a specific programme to this Programme Manager.' }, 400);
      if (body.programme_id) {
        const { data: programme } = await admin.from('programmes').select('id').eq('id', body.programme_id).maybeSingle();
        if (!programme) return reply({ error: 'Programme not found.' }, 400);
      }
      const password = 'Pp!' + Array.from(crypto.getRandomValues(new Uint8Array(15)), b => b.toString(16).padStart(2, '0')).join('') + '7';
      const { data, error } = await admin.auth.admin.createUser({ email, password, email_confirm: true, user_metadata: { full_name: name } });
      if (error || !data.user) return reply({ error: error?.message || 'The account could not be created.' }, 400);
      const { error: accessError } = await admin.from('memberships').update({ last_changed_by: user.id, display_name: name, role: body.role, programme_id: body.role === 'programme_manager' ? body.programme_id : null, active: true, needs_password_change: true, can_view_salary: Boolean(body.can_view_salary), can_approve: body.role === 'leadership' && Boolean(body.can_approve) }).eq('user_id', data.user.id);
      if (accessError) return reply({ error: 'Account created in pending state. Update its access in the user list before use.' }, 500);
      return reply({ success: true, email, temporary_password: password });
    }
    if (body.action === 'reset-user-password') {
      if (member.role !== 'superadmin' || body.user_id === user.id) return reply({ error: 'Use your own Change password action, or select another member.' }, 403);
      const password = 'Pp!' + Array.from(crypto.getRandomValues(new Uint8Array(15)), b => b.toString(16).padStart(2, '0')).join('') + '7';
      const { data: target, error: e } = await admin.from('memberships').update({ needs_password_change: true, last_changed_by: user.id }).eq('user_id', body.user_id).select('user_id').single();
      if (e || !target) return reply({ error: 'Account not found or could not be locked for password reset.' }, 400);
      const { error } = await admin.auth.admin.updateUserById(body.user_id, { password });
      if (error) return reply({ error: 'Could not reset this account. Its mandatory password change remains enabled.' }, 400);
      return reply({ success: true, temporary_password: password });
    }
    if (body.action === 'approve-budget' || body.action === 'set-period-lock') {
      const approver = member.role === 'superadmin' || (member.role === 'leadership' && member.can_approve);
      if (body.action === 'approve-budget') {
        if (!approver) return reply({ error: 'Approval authority required.' }, 403);
        const { data, error } = await admin.from('budget_lines').update({ status: 'approved', approved_by: user.id, approved_at: new Date().toISOString() }).eq('id', body.id).select('id').single();
        if (error || !data) return reply({ error: 'Budget approval could not be saved.' }, 400);
      } else {
        if (!approver && !(member.role === 'data_admin' && body.closed === true)) return reply({ error: 'Reopening a period requires an authorised approver.' }, 403);
        if (typeof body.closed !== 'boolean' || !Number.isInteger(body.fiscal_year) || !Number.isInteger(body.month_index) || body.month_index < 0 || body.month_index > 11 || !String(body.reference || '').trim()) return reply({ error: 'Provide the period, state and reason.' }, 400);
        const { error } = await admin.from('period_locks').upsert({ programme_id: body.programme_id, fiscal_year: body.fiscal_year, month_index: body.month_index, closed: body.closed, reference: body.reference, updated_by: user.id }, { onConflict: 'programme_id,fiscal_year,month_index' });
        if (error) return reply({ error: 'Period could not be updated.' }, 400);
      }
      return reply({ success: true });
    }
    if (body.action === 'update-member') {
      if (member.role !== 'superadmin') return reply({ error: 'Superadmin access required.' }, 403);
      if (body.user_id === user.id) return reply({ error: 'You cannot change your own administrative access.' }, 400);
      if (!validRoles.includes(body.role) || typeof body.active !== 'boolean' || typeof body.user_id !== 'string') return reply({ error: 'Invalid access settings.' }, 400);
      if (body.active && body.role === 'programme_manager' && !body.programme_id) return reply({ error: 'Select a programme for this role.' }, 400);
      const { data, error } = await admin.from('memberships').update({ last_changed_by: user.id, role: body.role, active: body.active, programme_id: body.role === 'programme_manager' ? body.programme_id || null : null, can_view_salary: Boolean(body.can_view_salary), can_approve: body.role === 'leadership' && Boolean(body.can_approve) }).eq('user_id', body.user_id).select('user_id').single();
      if (error || !data) return reply({ error: 'Member not found or settings could not be saved.' }, 400);
      return reply({ success: true });
    }
    if (body.action === 'review-request') {
      if (!(member.role === 'superadmin' || (member.role === 'leadership' && member.can_approve))) return reply({ error: 'Approval authority required.' }, 403);
      if (!['reviewed','on_hold'].includes(body.status) || typeof body.review_note !== 'string' || !body.review_note.trim() || body.review_note.length > 3000) return reply({ error: 'Choose a review status and provide a note of up to 3,000 characters.' }, 400);
      const { data, error } = await admin.from('planning_requests').update({ status: body.status, review_note: body.review_note.trim(), reviewed_by: user.id }).eq('id', body.id).eq('status', 'submitted').select('id').maybeSingle();
      if (error || !data) return reply({ error: 'This request was already reviewed or could not be found. Refresh the queue.' }, 409);
      return reply({ success: true });
    }
    return reply({ error: 'Unknown action.' }, 400);
  } catch { return reply({ error: 'The request could not be completed. Please retry.' }, 500); }
});
