import { useEffect, useState, useCallback } from 'react';
import {
  View, Text, TouchableOpacity, StyleSheet,
  ActivityIndicator, ScrollView,
} from 'react-native';
import { router, Redirect } from 'expo-router';
import type { Session } from '@supabase/supabase-js';
import { supabase } from '../lib/supabase';
import { useAppMode, type AppMode } from '../lib/appMode'; // Using our new Zustand store
import type { Profile, Delivery } from '../lib/supabase';

const STATUS_LABEL: Record<string, string> = {
  pending:     '⏳ Waiting for a driver...',
  claimed:     '🚗 Driver is on the way',
  in_progress: '📦 Delivery in progress',
  completed:   '✅ Delivered',
  cancelled:   '❌ Cancelled',
};

const STATUS_COLOR: Record<string, string> = {
  pending:     '#7a9e9e',
  claimed:     '#f5a623',
  in_progress: '#f5a623',
  completed:   '#1a6b6b',
  cancelled:   '#7a4a4a',
};

export default function HomeScreen() {
  const { currentMode, availableModes, setMode } = useAppMode(); // Bound to our global state
  const [session,         setSession]         = useState<Session | null | undefined>(undefined);
  const [profile,         setProfile]         = useState<Profile | null>(null);
  const [activeOrder,     setActiveOrder]     = useState<Delivery | null>(null);
  const [recentCompleted, setRecentCompleted] = useState<Delivery | null>(null);
  const [todayEarnings,   setTodayEarnings]   = useState(0);
  const [weekEarnings,    setWeekEarnings]    = useState(0);

  const isAdmin = profile?.is_admin === true;

  useEffect(() => {
    supabase.auth.getSession().then(({ data: { session } }) => setSession(session ?? null));
    const { data: { subscription } } = supabase.auth.onAuthStateChange((_e, s) => setSession(s ?? null));
    return () => subscription.unsubscribe();
  }, []);

  const fetchCustomerData = useCallback(async (uid: string) => {
    const { data: active } = await supabase
      .from('deliveries')
      .select('*')
      .eq('customer_id', uid)
      .in('status', ['pending', 'claimed', 'in_progress'])
      .order('requested_at', { ascending: false })
      .limit(1)
      .maybeSingle();

    setActiveOrder(active ?? null);

    const { data: recent } = await supabase
      .from('deliveries')
      .select('*')
      .eq('customer_id', uid)
      .in('status', ['completed', 'cancelled'])
      .order('requested_at', { ascending: false })
      .limit(1)
      .maybeSingle();

    setRecentCompleted(recent ?? null);
  }, []);

  const fetchDriverData = useCallback(async (uid: string) => {
    const now = new Date();
    const startOfToday = new Date(now.getFullYear(), now.getMonth(), now.getDate()).toISOString();
    const startOfWeek  = new Date(now.getFullYear(), now.getMonth(), now.getDate() - now.getDay()).toISOString();

    const { data: todayRows } = await supabase
      .from('deliveries')
      .select('driver_payout')
      .eq('driver_id', uid)
      .eq('status', 'completed')
      .gte('requested_at', startOfToday);

    const { data: weekRows } = await supabase
      .from('deliveries')
      .select('driver_payout')
      .eq('driver_id', uid)
      .eq('status', 'completed')
      .gte('requested_at', startOfWeek);

    setTodayEarnings((todayRows ?? []).reduce((s, d) => s + (d.driver_payout ?? 0), 0));
    setWeekEarnings((weekRows  ?? []).reduce((s, d) => s + (d.driver_payout ?? 0), 0));
  }, []);

  useEffect(() => {
    if (!session?.user || !currentMode) return;
    const uid = session.user.id;

    supabase
      .from('profiles')
      .select('*')
      .eq('id', uid)
      .single()
      .then(({ data }) => setProfile(data));

    if (currentMode === 'customer') fetchCustomerData(uid);
    if (currentMode === 'driver')   fetchDriverData(uid);

    const channel = supabase
      .channel('home-realtime')
      .on('postgres_changes', { event: '*', schema: 'public', table: 'deliveries' }, () => {
        if (currentMode === 'customer') fetchCustomerData(uid);
        if (currentMode === 'driver')   fetchDriverData(uid);
      })
      .subscribe();

    return () => { supabase.removeChannel(channel); };
  }, [session, currentMode, fetchCustomerData, fetchDriverData]);

  async function signOut() {
    await supabase.auth.signOut();
  }

  // Loading
  if (session === undefined) {
    return (
      <View style={styles.centered}>
        <ActivityIndicator color="#f5a623" size="large" />
      </View>
    );
  }

  // Not logged in
  if (!session) return <Redirect href="/auth" />;

  const shownOrder = activeOrder ?? recentCompleted;

  // ── REUSABLE UI COMPONENTS ──────────────────────────────────────────────────
  const ModeSwitcher = () => {
    if (availableModes.length <= 1) return null;
    return (
      <View style={styles.switcherContainer}>
        {availableModes.map((mode) => (
          <TouchableOpacity
            key={mode}
            style={[styles.pill, currentMode === mode && styles.activePill]}
            onPress={() => setMode(mode as AppMode)}
          >
            <Text style={[styles.pillText, currentMode === mode && styles.activePillText]}>
              {mode.charAt(0).toUpperCase() + mode.slice(1)}
            </Text>
          </TouchableOpacity>
        ))}
      </View>
    );
  };

  const RoleUpsells = () => (
    <>
      {!availableModes.includes('driver') && (
        <TouchableOpacity style={[styles.button, styles.upsellButton]} onPress={() => router.push('/driver')}>
          <Text style={styles.upsellText}>+ Become a Driver</Text>
        </TouchableOpacity>
      )}
      {!availableModes.includes('partner') && (
        <TouchableOpacity style={[styles.button, styles.upsellButton]} onPress={() => router.push('/partner')}>
          <Text style={styles.upsellText}>+ Add a Restaurant</Text>
        </TouchableOpacity>
      )}
    </>
  );

  // ── Customer Home ──────────────────────────────────────────────────────────
  if (currentMode === 'customer') {
    return (
      <ScrollView style={styles.scroll} contentContainerStyle={styles.container}>
        <ModeSwitcher />
        
        <Text style={styles.logo}>commongood<Text style={styles.accent}>s</Text></Text>
        <Text style={styles.tagline}>driver-owned delivery</Text>
        {profile?.full_name && <Text style={styles.welcome}>👋 {profile.full_name}</Text>}

        {shownOrder && (
          <TouchableOpacity
            style={[styles.statusCard, { borderLeftColor: STATUS_COLOR[shownOrder.status] }]}
            onPress={() => router.push('/orders')}
            activeOpacity={0.8}
          >
            <Text style={styles.statusCardLabel}>
              {activeOrder ? 'YOUR DELIVERY' : 'LAST DELIVERY'}
            </Text>
            <Text style={[styles.statusText, { color: STATUS_COLOR[shownOrder.status] }]}>
              {STATUS_LABEL[shownOrder.status]}
            </Text>
            <Text style={styles.statusMeta}>
              {shownOrder.category}  ·  Zone {shownOrder.zone_assigned}  ·  ${shownOrder.fee_charged}
            </Text>
            <Text style={styles.statusTap}>Tap to view history →</Text>
          </TouchableOpacity>
        )}

        <View style={styles.buttonGroup}>
          <TouchableOpacity style={styles.button} onPress={() => router.push('/customer')}>
            <Text style={styles.buttonText}>Request Delivery</Text>
          </TouchableOpacity>
          <TouchableOpacity style={[styles.button, styles.buttonOutline]} onPress={() => router.push('/orders')}>
            <Text style={[styles.buttonText, styles.buttonOutlineText]}>Order History</Text>
          </TouchableOpacity>
          
          <RoleUpsells />

          {isAdmin && (
            <TouchableOpacity style={[styles.button, styles.adminButton]} onPress={() => router.push('/admin')}>
              <Text style={styles.adminButtonText}>⚙️ Admin — Onboard Restaurant</Text>
            </TouchableOpacity>
          )}
        </View>

        <View style={styles.footer}>
          <TouchableOpacity onPress={signOut}>
            <Text style={styles.footerLink}>Sign Out</Text>
          </TouchableOpacity>
        </View>
      </ScrollView>
    );
  }

  // ── Driver Home ────────────────────────────────────────────────────────────
  if (currentMode === 'driver') {
    return (
      <ScrollView style={styles.scroll} contentContainerStyle={styles.container}>
        <ModeSwitcher />

        <Text style={styles.logo}>commongood<Text style={styles.accent}>s</Text></Text>
        <Text style={styles.tagline}>driver-owned delivery</Text>
        {profile?.full_name && <Text style={styles.welcome}>👋 {profile.full_name}</Text>}

        <View style={styles.earningsRow}>
          <View style={styles.earningsCard}>
            <Text style={styles.earningsAmount}>${todayEarnings.toFixed(2)}</Text>
            <Text style={styles.earningsLabel}>Today</Text>
          </View>
          <View style={styles.earningsCard}>
            <Text style={styles.earningsAmount}>${weekEarnings.toFixed(2)}</Text>
            <Text style={styles.earningsLabel}>This Week</Text>
          </View>
        </View>

        <View style={styles.buttonGroup}>
          <TouchableOpacity style={styles.button} onPress={() => router.push('/driver')}>
            <Text style={styles.buttonText}>Driver Dashboard</Text>
          </TouchableOpacity>
          <TouchableOpacity style={[styles.button, styles.buttonOutline]} onPress={() => router.push('/orders')}>
            <Text style={[styles.buttonText, styles.buttonOutlineText]}>Delivery History</Text>
          </TouchableOpacity>

          <RoleUpsells />

          {isAdmin && (
            <TouchableOpacity style={[styles.button, styles.adminButton]} onPress={() => router.push('/admin')}>
              <Text style={styles.adminButtonText}>⚙️ Admin — Onboard Restaurant</Text>
            </TouchableOpacity>
          )}
        </View>

        <View style={styles.footer}>
          <TouchableOpacity onPress={signOut}>
            <Text style={styles.footerLink}>Sign Out</Text>
          </TouchableOpacity>
        </View>
      </ScrollView>
    );
  }

  // ── Partner Home — redirect to real dashboard ──────────────────────────────
  if (currentMode === 'partner') {
    return <Redirect href="/partner-home" />;
  }

  return null;
}

const styles = StyleSheet.create({
  scroll:            { backgroundColor: '#0a1a1a' },
  container:         { padding: 32, paddingTop: 60, paddingBottom: 48, alignItems: 'center' },
  centered:          { flex: 1, backgroundColor: '#0a1a1a', alignItems: 'center', justifyContent: 'center', padding: 32 },
  
  // New Styles for the Mode Switcher & Upsells
  switcherContainer: { flexDirection: 'row', gap: 10, marginBottom: 30, backgroundColor: '#122828', padding: 6, borderRadius: 24 },
  pill:              { paddingVertical: 8, paddingHorizontal: 20, borderRadius: 20 },
  activePill:        { backgroundColor: '#1a6b6b' },
  pillText:          { color: '#7a9e9e', fontSize: 13, fontWeight: '700' },
  activePillText:    { color: '#f5f5f5' },
  upsellButton:      { backgroundColor: 'transparent', borderWidth: 1, borderColor: '#f5a623', borderStyle: 'dashed' },
  upsellText:        { color: '#f5a623', fontSize: 16, fontWeight: '600' },

  logo:              { fontSize: 42, fontWeight: '800', color: '#f5f5f5', letterSpacing: -1, marginBottom: 8 },
  accent:            { color: '#f5a623' },
  tagline:           { fontSize: 14, color: '#7a9e9e', letterSpacing: 2, textTransform: 'uppercase', marginBottom: 8 },
  welcome:           { fontSize: 15, color: '#f5f5f5', marginBottom: 32 },
  statusCard:        { width: '100%', backgroundColor: '#122828', borderRadius: 8, padding: 16, marginBottom: 24, borderLeftWidth: 3 },
  statusCardLabel:   { fontSize: 10, color: '#4a7a7a', letterSpacing: 2, marginBottom: 8 },
  statusText:        { fontSize: 15, fontWeight: '700', marginBottom: 6 },
  statusMeta:        { fontSize: 12, color: '#7a9e9e', marginBottom: 6 },
  statusTap:         { fontSize: 11, color: '#4a7a7a' },
  earningsRow:       { flexDirection: 'row', gap: 12, width: '100%', marginBottom: 32 },
  earningsCard:      { flex: 1, backgroundColor: '#122828', borderRadius: 8, padding: 16, alignItems: 'center' },
  earningsAmount:    { color: '#f5a623', fontSize: 24, fontWeight: '700' },
  earningsLabel:     { color: '#7a9e9e', fontSize: 12, marginTop: 4 },
  buttonGroup:       { width: '100%', gap: 12, marginBottom: 32 },
  button:            { backgroundColor: '#1a6b6b', paddingVertical: 16, borderRadius: 8, alignItems: 'center' },
  buttonOutline:     { backgroundColor: 'transparent', borderWidth: 1, borderColor: '#1a6b6b' },
  buttonText:        { color: '#f5f5f5', fontSize: 16, fontWeight: '600' },
  buttonOutlineText: { color: '#7a9e9e' },
  adminButton:       { backgroundColor: 'transparent', borderWidth: 1, borderColor: '#4a7a7a', borderStyle: 'dashed' },
  adminButtonText:   { color: '#4a7a7a', fontSize: 14, fontWeight: '600' },
  footer:            { flexDirection: 'row', alignItems: 'center', gap: 12 },
  footerLink:        { color: '#4a7a7a', fontSize: 13 },
});