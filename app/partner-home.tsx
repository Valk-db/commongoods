import { useState, useEffect } from 'react';
import {
  View, Text, TouchableOpacity, StyleSheet, ActivityIndicator, ScrollView,
} from 'react-native';
import { router } from 'expo-router';
import { supabase } from '../lib/supabase';
import { saveAppMode, clearAppMode, type AppMode } from '../lib/appMode';

interface PartnerRow {
  id: string;
  business_name: string;
  address: string;
  approved: boolean | null;
  founding_merchant: boolean | null;
}

export default function PartnerHomeScreen() {
  const [partner,  setPartner]  = useState<PartnerRow | null | undefined>(undefined);
  const [todayCount, setTodayCount] = useState(0);
  const [todayRevenue, setTodayRevenue] = useState(0);

  useEffect(() => {
    (async () => {
      const { data: { user } } = await supabase.auth.getUser();
      if (!user) return;

      const { data: partnerRow } = await supabase
        .from('partners')
        .select('id, business_name, address, approved, founding_merchant')
        .eq('profile_id', user.id)
        .maybeSingle();

      setPartner(partnerRow ?? null);

      if (partnerRow) {
        const startOfToday = new Date();
        startOfToday.setHours(0, 0, 0, 0);

        const { data: orders } = await supabase
          .from('deliveries')
          .select('fee_charged')
          .eq('partner_id', partnerRow.id)
          .gte('requested_at', startOfToday.toISOString());

        setTodayCount(orders?.length ?? 0);
        setTodayRevenue((orders ?? []).reduce((s, o) => s + (o.fee_charged ?? 0), 0));
      }
    })();
  }, []);

  async function switchMode(mode: AppMode) {
    await saveAppMode(mode);
    router.replace('/');
  }

  async function signOut() {
    await clearAppMode();
    await supabase.auth.signOut();
    router.replace('/auth');
  }

  if (partner === undefined) {
    return (
      <View style={styles.centered}>
        <ActivityIndicator color="#f5a623" size="large" />
      </View>
    );
  }

  if (partner === null) {
    return (
      <View style={styles.centered}>
        <Text style={styles.notLinkedIcon}>🤝</Text>
        <Text style={styles.notLinkedTitle}>Account not linked yet</Text>
        <Text style={styles.notLinkedBody}>
          We&apos;re still setting up your restaurant in CommonGoods. You&apos;ll see your dashboard here once it&apos;s ready — usually within a day of signing up.
        </Text>

        <View style={styles.footer}>
          <TouchableOpacity onPress={() => switchMode('customer')}>
            <Text style={styles.footerLink}>Switch to Customer Mode</Text>
          </TouchableOpacity>
          <Text style={styles.footerDivider}>·</Text>
          <TouchableOpacity onPress={signOut}>
            <Text style={styles.footerLink}>Sign Out</Text>
          </TouchableOpacity>
        </View>
      </View>
    );
  }

  return (
    <ScrollView style={styles.scroll} contentContainerStyle={styles.container}>

      <Text style={styles.label}>YOUR RESTAURANT</Text>
      <Text style={styles.businessName}>{partner.business_name}</Text>
      <Text style={styles.address}>{partner.address}</Text>

      {partner.founding_merchant && (
        <View style={styles.foundingBadge}>
          <Text style={styles.foundingBadgeText}>★ Founding Merchant — never pays an onboarding fee</Text>
        </View>
      )}

      <View style={styles.statsRow}>
        <View style={styles.statCard}>
          <Text style={styles.statValue}>{todayCount}</Text>
          <Text style={styles.statLabel}>Orders Today</Text>
        </View>
        <View style={styles.statCard}>
          <Text style={styles.statValue}>${todayRevenue.toFixed(2)}</Text>
          <Text style={styles.statLabel}>Revenue Today</Text>
        </View>
      </View>

      <View style={styles.navGroup}>
        <TouchableOpacity style={styles.navCard} onPress={() => router.push('/partner-orders')}>
          <Text style={styles.navIcon}>📋</Text>
          <View style={styles.navText}>
            <Text style={styles.navTitle}>Orders & Sales</Text>
            <Text style={styles.navDesc}>Live incoming orders, daily revenue</Text>
          </View>
          <Text style={styles.navArrow}>→</Text>
        </TouchableOpacity>

        <TouchableOpacity style={styles.navCard} onPress={() => router.push('/partner-menu')}>
          <Text style={styles.navIcon}>🍽️</Text>
          <View style={styles.navText}>
            <Text style={styles.navTitle}>Menu</Text>
            <Text style={styles.navDesc}>Edit items, prices, photos</Text>
          </View>
          <Text style={styles.navArrow}>→</Text>
        </TouchableOpacity>

        <TouchableOpacity style={styles.navCard} onPress={() => router.push('/partner-settings')}>
          <Text style={styles.navIcon}>⚙️</Text>
          <View style={styles.navText}>
            <Text style={styles.navTitle}>Restaurant Settings</Text>
            <Text style={styles.navDesc}>Name, address, pickup instructions</Text>
          </View>
          <Text style={styles.navArrow}>→</Text>
        </TouchableOpacity>

        <TouchableOpacity style={styles.navCard} onPress={() => router.push('/partner')}>
          <Text style={styles.navIcon}>ℹ️</Text>
          <View style={styles.navText}>
            <Text style={styles.navTitle}>Partner Program Info</Text>
            <Text style={styles.navDesc}>Pilot details, founding merchant terms</Text>
          </View>
          <Text style={styles.navArrow}>→</Text>
        </TouchableOpacity>
      </View>

      <View style={styles.footer}>
        <TouchableOpacity onPress={() => switchMode('customer')}>
          <Text style={styles.footerLink}>Switch to Customer Mode</Text>
        </TouchableOpacity>
        <Text style={styles.footerDivider}>·</Text>
        <TouchableOpacity onPress={() => switchMode('driver')}>
          <Text style={styles.footerLink}>Switch to Driver Mode</Text>
        </TouchableOpacity>
        <Text style={styles.footerDivider}>·</Text>
        <TouchableOpacity onPress={signOut}>
          <Text style={styles.footerLink}>Sign Out</Text>
        </TouchableOpacity>
      </View>

    </ScrollView>
  );
}

const styles = StyleSheet.create({
  scroll:             { backgroundColor: '#0a1a1a' },
  container:          { padding: 24, paddingTop: 60, paddingBottom: 48 },
  centered:           { flex: 1, backgroundColor: '#0a1a1a', alignItems: 'center', justifyContent: 'center', padding: 32 },

  notLinkedIcon:      { fontSize: 48, marginBottom: 20 },
  notLinkedTitle:     { color: '#f5f5f5', fontSize: 18, fontWeight: '700', marginBottom: 12, textAlign: 'center' },
  notLinkedBody:       { color: '#7a9e9e', fontSize: 14, textAlign: 'center', lineHeight: 22, marginBottom: 32 },

  label:              { fontSize: 11, color: '#7a9e9e', letterSpacing: 2, marginBottom: 8 },
  businessName:       { fontSize: 26, fontWeight: '700', color: '#f5f5f5', marginBottom: 4 },
  address:            { fontSize: 13, color: '#7a9e9e', marginBottom: 16 },

  foundingBadge:      { backgroundColor: '#0f2818', borderRadius: 8, padding: 12, marginBottom: 28, borderWidth: 1, borderColor: '#1a6b3a' },
  foundingBadgeText:  { color: '#4ade80', fontSize: 12, fontWeight: '700' },

  statsRow:           { flexDirection: 'row', gap: 12, marginBottom: 32 },
  statCard:           { flex: 1, backgroundColor: '#122828', borderRadius: 8, padding: 18, alignItems: 'center' },
  statValue:          { color: '#f5a623', fontSize: 24, fontWeight: '700' },
  statLabel:          { color: '#7a9e9e', fontSize: 12, marginTop: 4 },

  navGroup:           { gap: 12, marginBottom: 32 },
  navCard:            { flexDirection: 'row', alignItems: 'center', backgroundColor: '#122828', borderRadius: 10, padding: 18, borderWidth: 1, borderColor: '#1a3a3a' },
  navIcon:            { fontSize: 24, marginRight: 14 },
  navText:            { flex: 1 },
  navTitle:           { color: '#f5f5f5', fontSize: 15, fontWeight: '700', marginBottom: 2 },
  navDesc:            { color: '#7a9e9e', fontSize: 12 },
  navArrow:           { color: '#4a7a7a', fontSize: 18 },

  footer:             { flexDirection: 'row', alignItems: 'center', justifyContent: 'center', gap: 12, flexWrap: 'wrap' },
  footerLink:         { color: '#4a7a7a', fontSize: 13 },
  footerDivider:      { color: '#1a3a3a', fontSize: 13 },
});