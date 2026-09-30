import { useState, useEffect, useCallback } from 'react';
import {
  View, Text, TouchableOpacity, StyleSheet,
  ScrollView, ActivityIndicator, Alert, RefreshControl,
} from 'react-native';
import { supabase } from '../lib/supabase';
import type { Delivery } from '../lib/supabase';
import { openDriveNavigation } from '../lib/navigation';

const EDGE_FUNCTION_URL = process.env.EXPO_PUBLIC_SUPABASE_URL! + '/functions/v1';

type Earnings = {
  today: number;
  week: number;
  count: number;
};

export default function DriverScreen() {
  const [userId,    setUserId]    = useState<string | null>(null);
  const [available, setAvailable] = useState<AvailableJob[]>([]);
  const [activeJob, setActiveJob] = useState<Delivery | null>(null);
  const [earnings,  setEarnings]  = useState<Earnings>({ today: 0, week: 0, count: 0 });
  const [loading,   setLoading]   = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [claiming,  setClaiming]  = useState<string | null>(null);
  const [advancing, setAdvancing] = useState<string | null>(null);

  useEffect(() => {
    supabase.auth.getUser().then(({ data: { user } }) => {
      if (user) setUserId(user.id);
    });
  }, []);

  interface AvailableJob {
  id: string;
  category: string;
  pickup_address: string;
  pickup_lat: number;
  pickup_lng: number;
  dropoff_address: string | null;
  dropoff_lat: number | null;
  dropoff_lng: number | null;
  distance_miles: number | null;
  zone_assigned: number | null;
  fee_charged: number | null;
  driver_payout: number | null;
  platform_cut: number | null;
  estimated_duration_minutes: number | null;
  requested_at: string;
  notes?: string | null;
  partner_name: string | null;
  pickup_notes: string | null;
}

const fetchData = useCallback(async (uid: string) => {
    // Available (pending) jobs - use get_available_jobs RPC
    const { data: pendingJobs, error: jobsError } = await supabase
      .rpc('get_available_jobs');

    if (jobsError) {
      console.error('get_available_jobs error:', jobsError);
      // Fallback: try available_jobs view directly
      const { data: fallbackJobs, error: fallbackError } = await supabase
        .from('available_jobs' as any)
        .select('*')
        .order('requested_at', { ascending: true });

      if (fallbackError) {
        throw fallbackError;
      }
      setAvailable((fallbackJobs as unknown as AvailableJob[]) || []);
    } else {
      // Transform RPC result to AvailableJob (add missing fields with defaults)
      const jobs = (pendingJobs as unknown as Array<{
        id: string;
        category: string;
        pickup_address: string;
        pickup_lat: number;
        pickup_lng: number;
        dropoff_address: string | null;
        dropoff_lat: number | null;
        dropoff_lng: number | null;
        distance_miles: number | null;
        zone_assigned: number | null;
        fee_charged: number | null;
        driver_payout: number | null;
        platform_cut: number | null;
        estimated_duration_minutes: number | null;
        requested_at: string;
        partner_name: string | null;
        pickup_notes: string | null;
      }>) || [];
      setAvailable(jobs.map(job => ({
        ...job,
        notes: undefined,
      })));
    }

    // This driver's active job
    const { data: myJob } = await supabase
      .from('deliveries')
      .select('*')
      .eq('driver_id', uid)
      .in('status', ['claimed', 'in_progress'])
      .maybeSingle();

    // Earnings - use delivered_at for accuracy
    const now = new Date();
    const startOfToday = new Date(now.getFullYear(), now.getMonth(), now.getDate()).toISOString();
    const startOfWeek  = new Date(now.getFullYear(), now.getMonth(), now.getDate() - now.getDay()).toISOString();

    const { data: todayRows } = await supabase
      .from('earnings')
      .select('amount')
      .eq('driver_id', uid)
      .eq('paid_out', false) // only unpaid earnings
      .gte('created_at', startOfToday);

    const { data: weekRows } = await supabase
      .from('earnings')
      .select('amount')
      .eq('driver_id', uid)
      .eq('paid_out', false)
      .gte('created_at', startOfWeek);

    const todayTotal = (todayRows ?? []).reduce((sum, d) => sum + (d.amount ?? 0), 0);
    const weekTotal  = (weekRows  ?? []).reduce((sum, d) => sum + (d.amount ?? 0), 0);
    const todayCount = todayRows?.length ?? 0;

    setAvailable(pendingJobs ?? []);
    setActiveJob(myJob ?? null);
    setEarnings({ today: todayTotal, week: weekTotal, count: todayCount });
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

  // Call RPC function to claim a delivery
  async function handleClaim(jobId: string) {
    if (!userId) return;
    setClaiming(jobId);
    try {
      const { data, error } = await supabase.rpc('claim_delivery', {
        p_delivery_id: jobId,
      });

      setClaiming(null);
      if (error || !data || data.length === 0 || !data[0].success) {
        const msg = data?.[0]?.error || error?.message || 'This job may have already been taken.';
        Alert.alert('Could not claim', msg);
        fetchData(userId);
      } else {
        fetchData(userId);
      }
    } catch (err: any) {
      setClaiming(null);
      Alert.alert('Error', err.message);
      fetchData(userId);
    }
  }

  // Call RPC to advance status to in_progress (driver picked up)
  async function handlePickedUp() {
    if (!activeJob || !userId) return;
    setAdvancing(activeJob.id);
    try {
      const { data, error } = await supabase.rpc('advance_delivery_status', {
        p_delivery_id: activeJob.id,
        p_new_status: 'in_progress',
      });

      setAdvancing(null);
      if (error || !data || data.length === 0 || !data[0].success) {
        const msg = data?.[0]?.error || error?.message || 'Could not update status.';
        Alert.alert('Error', msg);
      } else {
        fetchData(userId);
      }
    } catch (err: any) {
      setAdvancing(null);
      Alert.alert('Error', err.message);
    }
  }

  // Call RPC to advance status to completed (driver delivered)
  async function handleComplete() {
    if (!activeJob || !userId) return;
    const confirmed = await new Promise<boolean>((resolve) => {
      Alert.alert(
        'Mark as Complete?',
        `Confirm delivery of ${activeJob.category} job for $${activeJob.driver_payout?.toFixed(2)}`,
        [
          { text: 'Cancel', style: 'cancel', onPress: () => resolve(false) },
          { text: 'Complete', onPress: () => resolve(true) },
        ]
      );
    });

    if (!confirmed) return;

    setAdvancing(activeJob.id);
    try {
      const { data, error } = await supabase.rpc('advance_delivery_status', {
        p_delivery_id: activeJob.id,
        p_new_status: 'completed',
      });

      setAdvancing(null);
      if (error || !data || data.length === 0 || !data[0].success) {
        const msg = data?.[0]?.error || error?.message || 'Could not complete delivery.';
        Alert.alert('Error', msg);
      } else {
        setActiveJob(null);
        fetchData(userId);
      }
    } catch (err: any) {
      setAdvancing(null);
      Alert.alert('Error', err.message);
    }
  }

  // Call RPC to release a job back to pending
  async function handleRelease() {
    if (!activeJob || !userId) return;
    const confirmed = await new Promise<boolean>((resolve) => {
      Alert.alert(
        'Release Job?',
        'This will make the job available for other drivers.',
        [
          { text: 'Cancel', style: 'cancel', onPress: () => resolve(false) },
          { text: 'Release', onPress: () => resolve(true) },
        ]
      );
    });

    if (!confirmed) return;

    setAdvancing(activeJob.id);
    try {
      const { data, error } = await supabase.rpc('release_delivery', {
        p_delivery_id: activeJob.id,
      });

      setAdvancing(null);
      if (error || !data || data.length === 0 || !data[0].success) {
        const msg = data?.[0]?.error || error?.message || 'Could not release job.';
        Alert.alert('Error', msg);
      } else {
        setActiveJob(null);
        fetchData(userId);
      }
    } catch (err: any) {
      setAdvancing(null);
      Alert.alert('Error', err.message);
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
                <>
                  <TouchableOpacity
                    style={styles.pickedUpButton}
                    onPress={handlePickedUp}
                    disabled={!!advancing}
                  >
                    <Text style={styles.completeText}>
                      {advancing === activeJob.id ? 'Starting...' : 'Picked Up → Start Driving'}
                    </Text>
                  </TouchableOpacity>
                  <TouchableOpacity
                    style={styles.releaseButton}
                    onPress={handleRelease}
                    disabled={!!advancing}
                  >
                    <Text style={styles.releaseText}>Release</Text>
                  </TouchableOpacity>
                </>
              ) : (
                <TouchableOpacity
                  style={styles.completeButton}
                  onPress={handleComplete}
                  disabled={!!advancing}
                >
                  <Text style={styles.completeText}>
                    {advancing === activeJob.id ? 'Completing...' : 'Mark Complete'}
                  </Text>
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
                onPress={() => handleClaim(job.id)}
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
  pickedUpButton:      { flex: 1, backgroundColor: '#1a6b6b', paddingVertical: 10, paddingHorizontal: 18, borderRadius: 6, alignItems: 'center' },
  releaseButton:       { backgroundColor: '#7a4a4a', paddingVertical: 10, paddingHorizontal: 18, borderRadius: 6, alignItems: 'center' },
  releaseText:         { color: '#f5f5f5', fontSize: 13, fontWeight: '700' },
  claimButton:         { backgroundColor: '#1a6b6b', paddingVertical: 8, paddingHorizontal: 20, borderRadius: 6, minWidth: 72, alignItems: 'center' },
  claimButtonDisabled: { backgroundColor: '#1a3a3a' },
  claimText:           { color: '#f5f5f5', fontSize: 13, fontWeight: '700' },
  completeButton:      { backgroundColor: '#f5a623', paddingVertical: 10, paddingHorizontal: 18, borderRadius: 6, alignItems: 'center' },
  completeText:        { color: '#0a1a1a', fontSize: 13, fontWeight: '700' },
  emptyState:          { alignItems: 'center', paddingVertical: 48 },
  emptyText:           { color: '#7a9e9e', fontSize: 15, fontWeight: '600' },
  emptySubtext:        { color: '#4a7a7a', fontSize: 13, marginTop: 8 },
});