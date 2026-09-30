import { useState, useEffect, useCallback } from 'react';
import {
  View, Text, ScrollView, StyleSheet,
  ActivityIndicator, RefreshControl, TouchableOpacity,
} from 'react-native';
import { router } from 'expo-router';
import { supabase } from '../lib/supabase';
import type { Delivery } from '../lib/supabase';

const STATUS_LABEL: Record<string, string> = {
  pending:     '⏳ Pending',
  claimed:     '🚗 Driver Assigned',
  in_progress: '📦 Out for Delivery',
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

function formatTime(iso: string | null | undefined) {
  if (!iso) return '';
  const d = new Date(iso);
  return d.toLocaleString('en-US', { month: 'short', day: 'numeric', hour: 'numeric', minute: '2-digit' });
}

export default function PartnerOrdersScreen() {
  const [partnerId,  setPartnerId]  = useState<string | null | undefined>(undefined);
  const [orders,     setOrders]     = useState<Delivery[]>([]);
  const [loading,    setLoading]    = useState(true);
  const [refreshing, setRefreshing] = useState(false);

  const fetchOrders = useCallback(async (pid: string) => {
    const { data } = await supabase
      .from('deliveries')
      .select('*')
      .eq('partner_id', pid)
      .order('requested_at', { ascending: false });
    setOrders(data ?? []);
    setLoading(false);
  }, []);

  useEffect(() => {
    (async () => {
      const { data: { user } } = await supabase.auth.getUser();
      if (!user) return;
      const { data: partner } = await supabase
        .from('partners')
        .select('id')
        .eq('profile_id', user.id)
        .maybeSingle();
      setPartnerId(partner?.id ?? null);
    })();
  }, []);

  useEffect(() => {
    if (!partnerId) return;
    fetchOrders(partnerId);

    const channel = supabase
      .channel('partner-orders-realtime')
      .on('postgres_changes', { event: '*', schema: 'public', table: 'deliveries' }, () => {
        fetchOrders(partnerId);
      })
      .subscribe();

    return () => { supabase.removeChannel(channel); };
  }, [partnerId, fetchOrders]);

  async function onRefresh() {
    if (!partnerId) return;
    setRefreshing(true);
    await fetchOrders(partnerId);
    setRefreshing(false);
  }

  if (partnerId === undefined || loading) {
    return (
      <View style={styles.centered}>
        <ActivityIndicator color="#f5a623" size="large" />
      </View>
    );
  }

  if (partnerId === null) {
    return (
      <View style={styles.centered}>
        <Text style={styles.notLinkedIcon}>📋</Text>
        <Text style={styles.notLinkedTitle}>Account not linked yet</Text>
        <Text style={styles.notLinkedBody}>
          We&apos;re still setting up your restaurant in CommonGoods. Orders will show up here once it&apos;s ready.
        </Text>
        <TouchableOpacity onPress={() => router.back()}>
          <Text style={styles.backLink}>← Go back</Text>
        </TouchableOpacity>
      </View>
    );
  }

  const active = orders.filter(o => o.status && ['pending', 'claimed', 'in_progress'].includes(o.status));
  const past   = orders.filter(o => o.status && ['completed', 'cancelled'].includes(o.status));

  const now = new Date();
  const startOfToday = new Date(now.getFullYear(), now.getMonth(), now.getDate());
  const startOfWeek  = new Date(now.getFullYear(), now.getMonth(), now.getDate() - now.getDay());

  const todayOrders = orders.filter(o => o.requested_at && new Date(o.requested_at) >= startOfToday);
  const weekOrders  = orders.filter(o => o.requested_at && new Date(o.requested_at) >= startOfWeek);

  return (
    <ScrollView
      style={styles.scroll}
      contentContainerStyle={styles.container}
      refreshControl={<RefreshControl refreshing={refreshing} onRefresh={onRefresh} tintColor="#f5a623" />}
    >
      <Text style={styles.label}>ORDERS & SALES</Text>

      <View style={styles.statsRow}>
        <View style={styles.statCard}>
          <Text style={styles.statValue}>{todayOrders.length}</Text>
          <Text style={styles.statLabel}>Orders Today</Text>
        </View>
        <View style={styles.statCard}>
          <Text style={styles.statValue}>{weekOrders.length}</Text>
          <Text style={styles.statLabel}>This Week</Text>
        </View>
        <View style={styles.statCard}>
          <Text style={styles.statValue}>{orders.length}</Text>
          <Text style={styles.statLabel}>All Time</Text>
        </View>
      </View>

      {active.length > 0 && (
        <>
          <Text style={styles.sectionLabel}>LIVE</Text>
          {active.map((o) => <OrderCard key={o.id} order={o} />)}
        </>
      )}

      <Text style={styles.sectionLabel}>PAST</Text>
      {past.length === 0 ? (
        <View style={styles.emptyState}>
          <Text style={styles.emptyText}>No completed orders yet.</Text>
        </View>
      ) : (
        past.map((o) => <OrderCard key={o.id} order={o} />)
      )}
    </ScrollView>
  );
}

function OrderCard({ order: o }: { order: Delivery }) {
  const status = o.status ?? 'pending';
  return (
    <View style={[styles.card, { borderLeftColor: STATUS_COLOR[status] }]}>
      <View style={styles.cardHeader}>
        <Text style={styles.cardCategory}>{o.category}</Text>
        <Text style={[styles.cardStatus, { color: STATUS_COLOR[status] }]}>{STATUS_LABEL[status]}</Text>
      </View>
      <Text style={styles.cardRoute}>🏁 {o.dropoff_address}</Text>
      <View style={styles.cardFooter}>
        <Text style={styles.cardMeta}>
          Zone {o.zone_assigned}  ·  {formatTime(o.requested_at)}
        </Text>
        <Text style={styles.cardAmount}>${(o.fee_charged ?? 0).toFixed(2)}</Text>
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  scroll:            { backgroundColor: '#0a1a1a' },
  container:         { padding: 24, paddingTop: 30, paddingBottom: 48 },
  centered:          { flex: 1, backgroundColor: '#0a1a1a', alignItems: 'center', justifyContent: 'center', padding: 32 },
  label:             { fontSize: 11, color: '#f5a623', letterSpacing: 2, marginBottom: 24 },

  notLinkedIcon:     { fontSize: 48, marginBottom: 20 },
  notLinkedTitle:    { color: '#f5f5f5', fontSize: 18, fontWeight: '700', marginBottom: 12, textAlign: 'center' },
  notLinkedBody:     { color: '#7a9e9e', fontSize: 14, textAlign: 'center', lineHeight: 22, marginBottom: 24 },
  backLink:          { color: '#4a7a7a', fontSize: 13 },

  statsRow:          { flexDirection: 'row', gap: 10, marginBottom: 32 },
  statCard:          { flex: 1, backgroundColor: '#122828', borderRadius: 8, padding: 14, alignItems: 'center' },
  statValue:         { color: '#f5a623', fontSize: 20, fontWeight: '700' },
  statLabel:         { color: '#7a9e9e', fontSize: 11, marginTop: 4, textAlign: 'center' },

  sectionLabel:      { fontSize: 11, color: '#7a9e9e', letterSpacing: 2, marginBottom: 14, marginTop: 8 },

  card:              { backgroundColor: '#122828', borderRadius: 8, padding: 16, marginBottom: 12, borderLeftWidth: 3 },
  cardHeader:        { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', marginBottom: 8 },
  cardCategory:      { color: '#f5f5f5', fontSize: 15, fontWeight: '700' },
  cardStatus:        { fontSize: 12, fontWeight: '600' },
  cardRoute:         { color: '#7a9e9e', fontSize: 13, marginBottom: 8 },
  cardFooter:        { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center' },
  cardMeta:          { color: '#4a7a7a', fontSize: 11 },
  cardAmount:        { color: '#f5a623', fontSize: 16, fontWeight: '700' },

  emptyState:        { alignItems: 'center', paddingVertical: 40 },
  emptyText:         { color: '#7a9e9e', fontSize: 14 },
});