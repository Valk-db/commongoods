import { useEffect, useState, useCallback } from 'react';
import {
  View, Text, ScrollView, StyleSheet,
  ActivityIndicator, RefreshControl, Alert, TouchableOpacity,
} from 'react-native';
import { supabase } from '../lib/supabase';
import type { Profile, Delivery } from '../lib/supabase';

const STATUS_LABEL: Record<string, string> = {
  pending:     '⏳ Pending',
  claimed:     '🚗 Claimed',
  in_progress: '📦 In Progress',
  completed:   '✅ Completed',
  cancelled:   '❌ Cancelled',
};

const STATUS_COLOR: Record<string, string> = {
  pending:     '#7a9e9e',
  claimed:     '#f5a623',
  in_progress: '#f5a623',
  completed:   '#1a6b6b',
  cancelled:   '#7a4a4a',
};

function formatDate(iso: string | null | undefined) {
  if (!iso) return '';
  const d = new Date(iso);
  return d.toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' });
}

export default function OrdersScreen() {
  const [profile,    setProfile]    = useState<Profile | null>(null);
  const [deliveries, setDeliveries] = useState<Delivery[]>([]);
  const [loading,    setLoading]    = useState(true);
  const [refreshing, setRefreshing] = useState(false);

  const [totalEarnings, setTotalEarnings] = useState(0);
  const [totalSpent,    setTotalSpent]    = useState(0);

  const fetchAll = useCallback(async () => {
    const { data: { user } } = await supabase.auth.getUser();
    if (!user) return;

    const { data: prof } = await supabase
      .from('profiles')
      .select('*')
      .eq('id', user.id)
      .single();

    setProfile(prof);

    const isDriver = prof?.role === 'driver';

    const query = isDriver
      ? supabase
          .from('deliveries')
          .select('*')
          .eq('driver_id', user.id)
          .order('requested_at', { ascending: false })
      : supabase
          .from('deliveries')
          .select('*')
          .eq('customer_id', user.id)
          .order('requested_at', { ascending: false });

    const { data } = await query;
    const rows = data ?? [];
    setDeliveries(rows);

    if (isDriver) {
      const earned = rows
        .filter(d => d.status === 'completed')
        .reduce((sum, d) => sum + (d.driver_payout ?? 0), 0);
      setTotalEarnings(earned);
    } else {
      const spent = rows
        .filter(d => d.status === 'completed')
        .reduce((sum, d) => sum + (d.fee_charged ?? 0), 0);
      setTotalSpent(spent);
    }

    setLoading(false);
  }, []);

  useEffect(() => { fetchAll(); }, [fetchAll]);

  async function onRefresh() {
    setRefreshing(true);
    await fetchAll();
    setRefreshing(false);
  }

  if (loading) {
    return (
      <View style={styles.centered}>
        <ActivityIndicator color="#f5a623" size="large" />
      </View>
    );
  }

  const isDriver    = profile?.role === 'driver';
  const completed   = deliveries.filter(d => d.status === 'completed');
  const active      = deliveries.filter(d => d.status && ['pending', 'claimed', 'in_progress'].includes(d.status));
  const past        = deliveries.filter(d => d.status && ['completed', 'cancelled'].includes(d.status));

  return (
    <ScrollView
      style={styles.scroll}
      contentContainerStyle={styles.container}
      refreshControl={<RefreshControl refreshing={refreshing} onRefresh={onRefresh} tintColor="#f5a623" />}
    >
      <Text style={styles.label}>
        {isDriver ? 'DELIVERY HISTORY' : 'ORDER HISTORY'}
      </Text>

      {/* Summary card */}
      <View style={styles.summaryRow}>
        <View style={styles.summaryCard}>
          <Text style={styles.summaryAmount}>
            ${isDriver ? totalEarnings.toFixed(2) : totalSpent.toFixed(2)}
          </Text>
          <Text style={styles.summaryLabel}>
            {isDriver ? 'Total Earned' : 'Total Spent'}
          </Text>
        </View>
        <View style={styles.summaryCard}>
          <Text style={styles.summaryAmount}>{completed.length}</Text>
          <Text style={styles.summaryLabel}>Completed</Text>
        </View>
        <View style={styles.summaryCard}>
          <Text style={styles.summaryAmount}>{deliveries.length}</Text>
          <Text style={styles.summaryLabel}>All Time</Text>
        </View>
      </View>

      {/* Active orders */}
      {active.length > 0 && (
        <>
          <Text style={styles.sectionLabel}>ACTIVE</Text>
          {active.map((d) => (
            <DeliveryCard key={d.id} delivery={d} isDriver={isDriver} />
          ))}
        </>
      )}

      {/* Past */}
      <Text style={styles.sectionLabel}>PAST</Text>
      {past.length === 0 ? (
        <View style={styles.emptyState}>
          <Text style={styles.emptyText}>No past {isDriver ? 'deliveries' : 'orders'} yet.</Text>
        </View>
      ) : (
        past.map((d) => (
          <DeliveryCard key={d.id} delivery={d} isDriver={isDriver} />
        ))
      )}
    </ScrollView>
  );
}

// Cancel order function
async function handleCancelOrder(deliveryId: string) {
  const { data, error } = await supabase.rpc('advance_delivery_status', {
    p_delivery_id: deliveryId,
    p_new_status: 'cancelled',
  });

  if (error) {
    Alert.alert('Error', error.message);
    return;
  }

  if (data && data.length > 0 && !data[0].success) {
    Alert.alert('Could not cancel', data[0].error || 'Unknown error');
  }
}

function DeliveryCard({ delivery: d, isDriver }: { delivery: Delivery; isDriver: boolean }) {
  const status = d.status ?? 'pending';
  const canCancel = !isDriver && (status === 'pending' || status === 'claimed');

  return (
    <View style={[styles.card, { borderLeftColor: STATUS_COLOR[status] }]}>
      <View style={styles.cardHeader}>
        <Text style={styles.cardCategory}>{d.category}</Text>
        <Text style={[styles.cardStatus, { color: STATUS_COLOR[status] }]}>
          {STATUS_LABEL[status]}
        </Text>
      </View>
      <Text style={styles.cardRoute}>↑ {d.pickup_address}</Text>
      <Text style={styles.cardRoute}>↓ {d.dropoff_address}</Text>
      <View style={styles.cardFooter}>
        <Text style={styles.cardMeta}>
          Zone {d.zone_assigned}  ·  {d.distance_miles?.toFixed(1)} mi  ·  {formatDate(d.requested_at)}
        </Text>
        <View style={styles.cardFooterRight}>
          {canCancel && (
            <TouchableOpacity style={styles.cancelButton} onPress={() => handleCancelOrder(d.id)}>
              <Text style={styles.cancelText}>Cancel</Text>
            </TouchableOpacity>
          )}
          <Text style={styles.cardAmount}>
            ${isDriver
              ? (d.driver_payout ?? 0).toFixed(2)
              : (d.fee_charged ?? 0).toFixed(2)
            }
          </Text>
        </View>
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  scroll:         { backgroundColor: '#0a1a1a' },
  container:      { padding: 24, paddingTop: 40, paddingBottom: 48 },
  centered:       { flex: 1, backgroundColor: '#0a1a1a', alignItems: 'center', justifyContent: 'center' },
  label:          { fontSize: 11, color: '#f5a623', letterSpacing: 2, marginBottom: 24 },
  summaryRow:     { flexDirection: 'row', gap: 10, marginBottom: 36 },
  summaryCard:    { flex: 1, backgroundColor: '#122828', borderRadius: 8, padding: 14, alignItems: 'center' },
  summaryAmount:  { color: '#f5a623', fontSize: 18, fontWeight: '700' },
  summaryLabel:   { color: '#7a9e9e', fontSize: 11, marginTop: 4, textAlign: 'center' },
  sectionLabel:   { fontSize: 11, color: '#7a9e9e', letterSpacing: 2, marginBottom: 14 },
  card:           { backgroundColor: '#122828', borderRadius: 8, padding: 16, marginBottom: 12, borderLeftWidth: 3 },
  cardHeader:     { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', marginBottom: 10 },
  cardCategory:   { color: '#f5f5f5', fontSize: 15, fontWeight: '700' },
  cardStatus:     { fontSize: 12, fontWeight: '600' },
  cardRoute:      { color: '#7a9e9e', fontSize: 13, marginBottom: 4 },
  cardFooter:     { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', marginTop: 10 },
  cardFooterRight: { flexDirection: 'row', alignItems: 'center', gap: 12 },
  cardMeta:       { color: '#4a7a7a', fontSize: 11 },
  cardAmount:     { color: '#f5a623', fontSize: 18, fontWeight: '700' },
  cancelButton:   { backgroundColor: '#7a4a4a', paddingVertical: 6, paddingHorizontal: 12, borderRadius: 4 },
  cancelText:     { color: '#f5f5f5', fontSize: 11, fontWeight: '600' },
  emptyState:     { alignItems: 'center', paddingVertical: 48 },
  emptyText:      { color: '#7a9e9e', fontSize: 15 },
});