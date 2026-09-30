/**
 * Integration Tests: Dispatch and Claim Flow
 * Tests driver claiming, concurrent claims, and cancellation stages
 */

import { createClient } from '@supabase/supabase-js';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';

const SUPABASE_URL = process.env.SUPABASE_URL || 'http://127.0.0.1:54321';
const SUPABASE_ANON_KEY = process.env.SUPABASE_ANON_KEY || '';
const SUPABASE_SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY || '';

const serviceClient = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);
let anonClient: ReturnType<typeof createClient>;
let testCustomerId: string;
let testDriverId: string;
let testDriver2Id: string;
let testPartnerId: string;

beforeAll(async () => {
  // Create test customer
  const { data: customer } = await serviceClient.auth.admin.createUser({
    email: `test-customer-${Date.now()}@example.com`,
    password: 'testpassword123',
    email_confirm: true,
    user_metadata: { full_name: 'Test Customer' }
  });
  testCustomerId = customer.user!.id;
  await serviceClient.from('profiles').insert({ id: testCustomerId, role: 'customer', full_name: 'Test Customer' });

  // Create test driver 1
  const { data: driver } = await serviceClient.auth.admin.createUser({
    email: `test-driver-${Date.now()}@example.com`,
    password: 'testpassword123',
    email_confirm: true,
    user_metadata: { full_name: 'Test Driver' }
  });
  testDriverId = driver.user!.id;
  await serviceClient.from('profiles').insert({ id: testDriverId, role: 'driver', full_name: 'Test Driver' });
  await serviceClient.from('drivers').insert({ profile_id: testDriverId, approved: true, lat: 40.7128, lng: -74.0060 });

  // Create test driver 2
  const { data: driver2 } = await serviceClient.auth.admin.createUser({
    email: `test-driver2-${Date.now()}@example.com`,
    password: 'testpassword123',
    email_confirm: true,
    user_metadata: { full_name: 'Test Driver 2' }
  });
  testDriver2Id = driver2.user!.id;
  await serviceClient.from('profiles').insert({ id: testDriver2Id, role: 'driver', full_name: 'Test Driver 2' });
  await serviceClient.from('drivers').insert({ profile_id: testDriver2Id, approved: true, lat: 40.7130, lng: -74.0065 });

  // Create test partner
  const { data: partner } = await serviceClient
    .from('partners')
    .insert({
      profile_id: testCustomerId,
      name: 'Test Partner',
      address: '123 Test St',
      lat: 40.7128,
      lng: -74.0060,
      approved: true
    })
    .select('id')
    .single();
  testPartnerId = partner.id;

  // Sign in as customer
  const { data: signIn } = await serviceClient.auth.signInWithPassword({
    email: customer.user!.email!,
    password: 'testpassword123'
  });
  anonClient = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
    global: { headers: { Authorization: `Bearer ${signIn.session!.access_token}` } }
  });
});

afterAll(async () => {
  if (testCustomerId) await serviceClient.auth.admin.deleteUser(testCustomerId);
  if (testDriverId) await serviceClient.auth.admin.deleteUser(testDriverId);
  if (testDriver2Id) await serviceClient.auth.admin.deleteUser(testDriver2Id);
});

async function createTestDelivery(): Promise<string> {
  // Create quote
  const quoteResponse = await fetch(`${SUPABASE_URL}/functions/v1/get_quote`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${(await anonClient.auth.getSession()).data.session?.access_token}`
    },
    body: JSON.stringify({
      customer_id: testCustomerId,
      partner_id: testPartnerId,
      category: 'Auto Parts',
      pickup_address: '123 Pickup St',
      pickup_lat: 40.7128,
      pickup_lng: -74.0060,
      dropoff_address: '456 Dropoff Ave',
      dropoff_lat: 40.7580,
      dropoff_lng: -73.9855,
      estimated_duration_minutes: 20
    })
  });
  const quoteResult = await quoteResponse.json();
  expect(quoteResult.success).toBe(true);

  // Create delivery
  const deliveryResponse = await fetch(`${SUPABASE_URL}/functions/v1/create_delivery`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${(await anonClient.auth.getSession()).data.session?.access_token}`
    },
    body: JSON.stringify({
      customer_id: testCustomerId,
      partner_id: testPartnerId,
      category: 'Auto Parts',
      pickup_address: '123 Pickup St',
      pickup_lat: 40.7128,
      pickup_lng: -74.0060,
      dropoff_address: '456 Dropoff Ave',
      dropoff_lat: 40.7580,
      dropoff_lng: -73.9855,
      estimated_duration_minutes: 20,
      quote_id: quoteResult.quote_id
    })
  });
  const deliveryResult = await deliveryResponse.json();
  expect(deliveryResult.success).toBe(true);
  return deliveryResult.delivery_id;
}

describe('Driver Claim Flow', () => {
  it('should allow driver to claim a pending delivery', async () => {
    const deliveryId = await createTestDelivery();

    // Sign in as driver
    const { data: driverSignIn } = await serviceClient.auth.signInWithPassword({
      email: (await serviceClient.auth.admin.getUserById(testDriverId)).user!.email!,
      password: 'testpassword123'
    });
    const driverClient = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
      global: { headers: { Authorization: `Bearer ${driverSignIn.session!.access_token}` } }
    });

    // Call claim_delivery RPC
    const { data, error } = await driverClient.rpc('claim_delivery', { p_delivery_id: deliveryId });
    expect(error).toBeNull();
    expect(data[0].success).toBe(true);

    // Verify delivery status is 'claimed' and driver_id is set
    const { data: delivery } = await serviceClient
      .from('deliveries')
      .select('status, driver_id')
      .eq('id', deliveryId)
      .single();
    expect(delivery?.status).toBe('claimed');
    expect(delivery?.driver_id).toBe(testDriverId);
  });

  it('should reject second driver claiming same delivery (concurrent claim race)', async () => {
    const deliveryId = await createTestDelivery();

    // Sign in both drivers
    const { data: driver1SignIn } = await serviceClient.auth.signInWithPassword({
      email: (await serviceClient.auth.admin.getUserById(testDriverId)).user!.email!,
      password: 'testpassword123'
    });
    const { data: driver2SignIn } = await serviceClient.auth.signInWithPassword({
      email: (await serviceClient.auth.admin.getUserById(testDriver2Id)).user!.email!,
      password: 'testpassword123'
    });

    const driver1Client = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
      global: { headers: { Authorization: `Bearer ${driver1SignIn.session!.access_token}` } }
    });
    const driver2Client = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
      global: { headers: { Authorization: `Bearer ${driver2SignIn.session!.access_token}` } }
    });

    // Both try to claim simultaneously
    const [result1, result2] = await Promise.all([
      driver1Client.rpc('claim_delivery', { p_delivery_id: deliveryId }),
      driver2Client.rpc('claim_delivery', { p_delivery_id: deliveryId })
    ]);

    // One should succeed, one should fail
    const successes = [result1.data?.[0]?.success, result2.data?.[0]?.success].filter(Boolean).length;
    const failures = [result1.data?.[0]?.success, result2.data?.[0]?.success].filter(s => s === false).length;

    expect(successes).toBe(1);
    expect(failures).toBe(1);

    // Verify only one driver got it
    const { data: delivery } = await serviceClient
      .from('deliveries')
      .select('driver_id')
      .eq('id', deliveryId)
      .single();
    expect([testDriverId, testDriver2Id]).toContain(delivery?.driver_id);
  });

  it('should not allow customer to claim their own delivery', async () => {
    const deliveryId = await createTestDelivery();

    // Customer tries to claim
    const { data, error } = await anonClient.rpc('claim_delivery', { p_delivery_id: deliveryId });
    expect(data[0].success).toBe(false);
    expect(data[0].error).toBeDefined();
  });
});

describe('Cancellation Stages', () => {
  it('should allow customer to cancel before driver claims', async () => {
    const deliveryId = await createTestDelivery();

    // Customer cancels
    const { data, error } = await anonClient.rpc('advance_delivery_status', {
      p_delivery_id: deliveryId,
      p_new_status: 'cancelled'
    });
    expect(error).toBeNull();
    expect(data[0].success).toBe(true);

    const { data: delivery } = await serviceClient
      .from('deliveries')
      .select('status, cancel_stage, cancelled_by')
      .eq('id', deliveryId)
      .single();
    expect(delivery?.status).toBe('cancelled');
    expect(delivery?.cancel_stage).toBe('pre_claim');
    expect(delivery?.cancelled_by).toBe('customer');
  });

  it('should allow customer to cancel after driver claims (pre_pickup)', async () => {
    const deliveryId = await createTestDelivery();

    // Driver claims first
    const { data: driverSignIn } = await serviceClient.auth.signInWithPassword({
      email: (await serviceClient.auth.admin.getUserById(testDriverId)).user!.email!,
      password: 'testpassword123'
    });
    const driverClient = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
      global: { headers: { Authorization: `Bearer ${driverSignIn.session!.access_token}` } }
    });
    await driverClient.rpc('claim_delivery', { p_delivery_id: deliveryId });

    // Customer cancels
    const { data, error } = await anonClient.rpc('advance_delivery_status', {
      p_delivery_id: deliveryId,
      p_new_status: 'cancelled'
    });
    expect(error).toBeNull();
    expect(data[0].success).toBe(true);

    const { data: delivery } = await serviceClient
      .from('deliveries')
      .select('status, cancel_stage, cancelled_by')
      .eq('id', deliveryId)
      .single();
    expect(delivery?.status).toBe('cancelled');
    expect(delivery?.cancel_stage).toBe('pre_pickup');
    expect(delivery?.cancelled_by).toBe('customer');
  });

  it('should track compensation amount on driver cancellation after pickup', async () => {
    const deliveryId = await createTestDelivery();

    // Driver claims
    const { data: driverSignIn } = await serviceClient.auth.signInWithPassword({
      email: (await serviceClient.auth.admin.getUserById(testDriverId)).user!.email!,
      password: 'testpassword123'
    });
    const driverClient = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
      global: { headers: { Authorization: `Bearer ${driverSignIn.session!.access_token}` } }
    });
    await driverClient.rpc('claim_delivery', { p_delivery_id: deliveryId });

    // Driver advances to en_route
    await driverClient.rpc('advance_delivery_status', {
      p_delivery_id: deliveryId,
      p_new_status: 'en_route'
    });

    // Driver advances to arrived_pickup
    await driverClient.rpc('advance_delivery_status', {
      p_delivery_id: deliveryId,
      p_new_status: 'arrived_pickup'
    });

    // Driver cancels after pickup - should record compensation
    const { data, error } = await driverClient.rpc('advance_delivery_status', {
      p_delivery_id: deliveryId,
      p_new_status: 'cancelled'
    });
    expect(error).toBeNull();
    expect(data[0].success).toBe(true);

    const { data: delivery } = await serviceClient
      .from('deliveries')
      .select('status, cancel_stage, cancelled_by, compensation_amount')
      .eq('id', deliveryId)
      .single();
    expect(delivery?.status).toBe('cancelled');
    expect(delivery?.cancel_stage).toBe('post_pickup');
    expect(delivery?.cancelled_by).toBe('driver');
    expect(delivery?.compensation_amount).toBeGreaterThan(0);
  });
});