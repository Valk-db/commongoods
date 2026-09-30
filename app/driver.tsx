import { useState, useEffect, useCallback } from 'react';
import {
  View, Text, TouchableOpacity, StyleSheet,
  ScrollView, ActivityIndicator, Alert, RefreshControl,
} from 'react-native';
import { supabase } from '../lib/supabase';
import type { Delivery } from '../lib/supabase';
import { openDriveNavigation } from '../lib/navigation';

type Earnings = {
  today: number;
  week: number;
  count: number;
};

export default function DriverScreen() {
  const [userId,    setUserId]    = useState<string | null>(null);
  const [available, setAvailable] = useState<Delivery[]>([]);
  const [activeJob, setActiveJob] = useState<Delivery | null>(null);
  const [earnings,  setEarnings]  = useState<Earnings>({ today: 0, week: 0, count: 0 });
  const [loading,   setLoading]   = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [claiming,  setClaiming]  = useState<string | null>(null);

  useEffect(() => {
    supabase.auth.getUser().then(({ data: { user } }) => {
      if (user) setUserId(user.id);
    });
  }, []);

  const fetchData = useCallback(async (uid: string) => {
    // Available (pending) jobs
    const { data: pendingJobs } = await supabase
      .from('deliveries')
      .select('*')
      .eq('status', 'pending')
      .order('requested_at', { ascending: true });

    // This driver's active job
    const { data: myJob } = await supabase
      .from('deliveries')
      .select('*')
      .eq('driver_id', uid)
      .in('status', ['claimed', 'in_progress'])
      .maybeSingle();

    // Earnings
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

    const todayTotal = (todayRows ?? []).reduce((sum, d) => sum + (d.driver_payout ?? 0), 0);
    const weekTotal  = (weekRows  ?? []).reduce((sum, d) => sum + (d.driver_payout ?? 0), 0);

    setAvailable(pendingJobs ?? []);
    setActiveJob(myJob ?? null);
    setEarnings({ today: todayTotal, week: weekTotal, count: todayRows?.length ?? 0 });
    setLoading(false);
  }, []);

  useEffect(() => {
    if (!userId) return;
    fetchData(userId);

    const channel = supabase
      .channel('deliveries-realtime')
      .on('postgres_changes', { event: '*', schema: 'public', table: 'deliveries' }, () => {
        fetchData(userId);
      })
      .subscribe();

    return () => { supabase.removeChannel(channel); };
  }, [userId, fetchData]);

  async function handleClaim(job: Delivery) {
    if (!userId) return;
    setClaiming(job.id);
    // .select() here is load-bearing: Supabase/PostgREST returns success with an
    // empty array (not an error) when the .eq('status','pending') guard matches
    // zero rows, e.g. another driver claimed it a moment earlier. Without
    // selecting back the row, that race goes undetected and the driver never
    // sees a "this job's gone" message.
    const { data, error } = await supabase
      .from('deliveries')
      .update({ driver_id: userId, status: 'claimed' })
      .eq('id', job.id)
      .eq('status', 'pending') // guard: only claim if still pending
      .select('id');

    setClaiming(null);
    if (error || !data || data.length === 0) {
      Alert.alert('Could not claim', 'This job may have already been taken.');
      fetchData(userId); // refresh so the stale card disappears from the list
    } else {
      fetchData(userId);
    }
  }

  async function handlePickedUp() {
    if (!activeJob || !userId) return;
    const { error } = await supabase
      .from('deliveries')
      .update({ status: 'in_progress', picked_up_at: new Date().toISOString() })
      .eq('id', activeJob.id)
      .eq('driver_id', userId);

    if (error) {
      Alert.alert('Error', error.message);
    } else {
      fetchData(userId);
    }
  }

  function handleNavigate(job: Delivery) {
    const toPickup = job.status === 'claimed';
    const destination = toPickup
      ? { latitude: job.pickup_lat, longitude: job.pickup_lng }
      : { latitude: job.dropoff_lat, longitude: job.dropoff_lng };
    const label = toPickup ? job.pickup_address : job.dropoff_address;
    openDriveNavigation(destination, label);
  }

  async function handleComplete() {
    if (!activeJob || !userId) return;
    Alert.alert(
      'Mark as Complete?',
      `Confirm delivery of ${activeJob.category} job for $${activeJob.driver_payout?.toFixed(2)}`,
      [
        { text: 'Cancel', style: 'cancel' },
        {
          text: 'Complete',
          onPress: async () => {
            const { error } = await supabase
              .from('deliveries')
              .update({ status: 'completed', delivered_at: new Date().toISOString() })
              .eq('id', activeJob.id)
              .eq('driver_id', userId);

            if (error) {
              Alert.alert('Error', error.message);
            } else {
              setActiveJob(null);
              fetchData(userId);
            }
          },
        },
      ]
    );
  }

  async function onRefresh() {
    if (!userId) return;
    setRefreshing(true);
    await fetchData(userId);
    setRefreshing(false);
  }

  if (loading) {
    return (
      <View style={styles.centered}>
        <ActivityIndicator color="#f5a623" size="large" />
      </View>
    );
  }

  return (
    <ScrollView
      style={styles.scroll}
      contentContainerStyle={styles.container}
      refreshControl={<RefreshControl refreshing={refreshing} onRefresh={onRefresh} tintColor="#f5a623" />}
    >
      <Text style={styles.label}>DRIVER DASHBOARD</Text>

      {/* Earnings */}
      <View style={styles.earningsRow}>
        <View style={styles.earningsCard}>
          <Text style={styles.earningsAmount}>${earnings.today.toFixed(2)}</Text>
          <Text style={styles.earningsLabel}>Today</Text>
        </View>
        <View style={styles.earningsCard}>
          <Text style={styles.earningsAmount}>${earnings.week.toFixed(2)}</Text>
          <Text style={styles.earningsLabel}>This Week</Text>
        </View>
        <View style={styles.earningsCard}>
          <Text style={styles.earningsAmount}>{earnings.count}</Text>
          <Text style={styles.earningsLabel}>Deliveries</Text>
        </View>
      </View>

      {/* Active job */}
      {activeJob && (
        <>
          <Text style={styles.sectionLabel}>YOUR ACTIVE JOB</Text>
          <View style={styles.activeCard}>
            <View style={styles.jobHeader}>
              <Text style={styles.jobType}>{activeJob.category}</Text>
              <Text style={styles.jobPay}>${activeJob.driver_payout?.toFixed(2)}</Text>
            </View>
            <Text style={styles.jobRoute}>↑ {activeJob.pickup_address}</Text>
            <Text style={styles.jobRoute}>↓ {activeJob.dropoff_address}</Text>
            <Text style={styles.jobMeta}>
              Zone {activeJob.zone_assigned}  ·  {activeJob.distance_miles?.toFixed(1)} mi
            </Text>
            <View style={styles.activeActions}>
              <TouchableOpacity style={styles.navigateButton} onPress={() => handleNavigate(activeJob)}>
                <Text style={styles.navigateText}>
                  🧭 Navigate to {activeJob.status === 'claimed' ? 'Pickup' : 'Dropoff'}
                </Text>
              </TouchableOpacity>
              {activeJob.status === 'claimed' ? (
                <TouchableOpacity style={styles.pickedUpButton} onPress={handlePickedUp}>
                  <Text style={styles.completeText}>Picked Up</Text>
                </TouchableOpacity>
              ) : (
                <TouchableOpacity style={styles.completeButton} onPress={handleComplete}>
                  <Text style={styles.completeText}>Mark Complete</Text>
                </TouchableOpacity>
              )}
            </View>
          </View>
        </>
      )}

      {/* Available jobs */}
      <Text style={styles.sectionLabel}>AVAILABLE JOBS</Text>

      {available.length === 0 ? (
        <View style={styles.emptyState}>
          <Text style={styles.emptyText}>No pending deliveries right now.</Text>
          <Text style={styles.emptySubtext}>Pull down to refresh.</Text>
        </View>
      ) : (
        available.map((job) => (
          <View key={job.id} style={styles.jobCard}>
            <View style={styles.jobHeader}>
              <Text style={styles.jobType}>{job.category}</Text>
              <Text style={styles.jobPay}>${job.driver_payout?.toFixed(2)}</Text>
            </View>
            <Text style={styles.jobRoute}>↑ {job.pickup_address}</Text>
            <Text style={styles.jobRoute}>↓ {job.dropoff_address}</Text>
            <View style={styles.jobFooter}>
              <Text style={styles.jobMeta}>
                Zone {job.zone_assigned}  ·  {job.distance_miles?.toFixed(1)} mi
              </Text>
              <TouchableOpacity
                style={[styles.claimButton, (!!claiming || !!activeJob) && styles.claimButtonDisabled]}
                onPress={() => handleClaim(job)}
                disabled={!!claiming || !!activeJob}
              >
                {claiming === job.id
                  ? <ActivityIndicator color="#f5f5f5" size="small" />
                  : <Text style={styles.claimText}>{activeJob ? 'Busy' : 'Claim'}</Text>
                }
              </TouchableOpacity>
            </View>
          </View>
        ))
      )}
    </ScrollView>
  );
}

const styles = StyleSheet.create({
  scroll:              { backgroundColor: '#0a1a1a' },
  container:           { padding: 24, paddingTop: 60, paddingBottom: 48 },
  centered:            { flex: 1, backgroundColor: '#0a1a1a', alignItems: 'center', justifyContent: 'center' },
  label:               { fontSize: 11, color: '#f5a623', letterSpacing: 2, marginBottom: 24 },
  earningsRow:         { flexDirection: 'row', gap: 10, marginBottom: 40 },
  earningsCard:        { flex: 1, backgroundColor: '#122828', borderRadius: 8, padding: 14, alignItems: 'center' },
  earningsAmount:      { color: '#f5a623', fontSize: 20, fontWeight: '700' },
  earningsLabel:       { color: '#7a9e9e', fontSize: 11, marginTop: 4 },
  sectionLabel:        { fontSize: 11, color: '#7a9e9e', letterSpacing: 2, marginBottom: 16 },
  activeCard:          { backgroundColor: '#122828', borderRadius: 8, padding: 16, marginBottom: 28, borderLeftWidth: 3, borderLeftColor: '#f5a623' },
  jobCard:             { backgroundColor: '#122828', borderRadius: 8, padding: 16, marginBottom: 12, borderLeftWidth: 3, borderLeftColor: '#1a6b6b' },
  jobHeader:           { flexDirection: 'row', justifyContent: 'space-between', marginBottom: 10 },
  jobType:             { color: '#f5f5f5', fontSize: 15, fontWeight: '700' },
  jobPay:              { color: '#f5a623', fontSize: 18, fontWeight: '700' },
  jobRoute:            { color: '#7a9e9e', fontSize: 13, marginBottom: 4 },
  jobFooter:           { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', marginTop: 12 },
  jobMeta:             { color: '#4a7a7a', fontSize: 12, marginTop: 4 },
  activeActions:       { flexDirection: 'row', gap: 10, marginTop: 14 },
  navigateButton:      { flex: 1, backgroundColor: '#0a1a1a', borderWidth: 1, borderColor: '#1a6b6b', paddingVertical: 10, borderRadius: 6, alignItems: 'center' },
  navigateText:        { color: '#7a9e9e', fontSize: 13, fontWeight: '700' },
  pickedUpButton:      { backgroundColor: '#1a6b6b', paddingVertical: 10, paddingHorizontal: 18, borderRadius: 6, alignItems: 'center' },
  claimButton:         { backgroundColor: '#1a6b6b', paddingVertical: 8, paddingHorizontal: 20, borderRadius: 6, minWidth: 72, alignItems: 'center' },
  claimButtonDisabled: { backgroundColor: '#1a3a3a' },
  claimText:           { color: '#f5f5f5', fontSize: 13, fontWeight: '700' },
  completeButton:      { backgroundColor: '#f5a623', paddingVertical: 10, paddingHorizontal: 18, borderRadius: 6, alignItems: 'center' },
  completeText:        { color: '#0a1a1a', fontSize: 13, fontWeight: '700' },
  emptyState:          { alignItems: 'center', paddingVertical: 48 },
  emptyText:           { color: '#7a9e9e', fontSize: 15, fontWeight: '600' },
  emptySubtext:        { color: '#4a7a7a', fontSize: 13, marginTop: 8 },
});