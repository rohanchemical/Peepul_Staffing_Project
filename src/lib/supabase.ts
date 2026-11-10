import { createClient } from '@supabase/supabase-js';

export const supabaseUrl = import.meta.env.VITE_SUPABASE_URL || 'https://yfhdcrhocslhhlmgpexl.supabase.co';
// This is a public client key. All data access is protected with database RLS.
const publishableKey = import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY || 'sb_publishable_Ng69qSVo6-AiB4WRCsXN7Q_LWsMQf9U';
export const supabase = createClient(supabaseUrl, publishableKey, {
  auth: { flowType: 'pkce', persistSession: true, autoRefreshToken: true, detectSessionInUrl: true },
});

export const roles = ['superadmin', 'data_admin', 'leadership', 'programme_manager'] as const;
export type Role = typeof roles[number];
export type Membership = { user_id: string; email: string; display_name: string; role: Role; programme_id: string | null; active: boolean; needs_password_change: boolean; created_at: string; can_view_salary: boolean; can_approve: boolean };
export type Programme = { id: string; name: string; short_name: string; colour: string; donor_posts: number; current_staff: number; above_cap: number; promotions_possible: number; hiring_requested: number; recommended_hires: number; hiring_on_hold: number; funded_open: number; action: string; source_name: string; imported_at: string };
export type Layer = { id: string; programme_id: string; layer: string; donor_posts: number; current_staff: number; allowed_surge: number; above_cap: number; funded_open: number };
export type Budget = { id: string; programme_id: string; month: string; budget: number; actual: number; notes: string };
export type RequestRow = { id: string; programme_id: string; kind: string; role_title: string; positions: number; rationale: string; status: string; review_note: string | null; created_by: string; created_at: string };

export async function accountAction(body: Record<string, unknown>) {
  const { data, error } = await supabase.functions.invoke('people-account', { body });
  if (error) {
    let message = error.message;
    if (error.context instanceof Response) {
      try { message = (await error.context.json()).error || message; } catch { /* retain message */ }
    }
    throw new Error(message);
  }
  if (data?.error) throw new Error(data.error);
  return data;
}
