/**
 * Integration Tests: Quote Flow
 * Tests the complete get_quote -> create_delivery flow
 */

import { createClient } from '@supabase/supabase-js';
import { afterAll, beforeAll, describe, expect, it, vi } from 'vitest';

// Get environment from supabase status
const SUPABASE_URL = process.env.SUPABASE_URL || 'http://127.0.0.1:54321';
const SUPABASE_ANON_KEY = process.env.SUPABASE_ANON_KEY || '';
const SUPABASE_SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY || '';

const serviceClient = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);
let anonClient: ReturnType<typeof createClient>;
let testCustomerId: string;
let testPartnerId: string;

beforeAll(async () => {
  // Create test customer
  const { data: customer, error: customerError } = await serviceClient.auth.admin.createUser({
    email: `test-customer-${Date.now()}@example.com`,
    password: 'testpassword123',
    email_confirm: true,
    user_metadata: { full_name: 'Test Customer' }
  });
  expect(customerError).toBeNull();
  testCustomerId = customer.user!.id;

  // Create profile
  const { error: profileError } = await serviceClient
    .from('profiles')
    .insert({ id: testCustomerId, role: 'customer', full_name: 'Test Customer' });
  expect(profileError).toBeNull();

  // Create test partner
  const { data: partner, error: partnerError } = await serviceClient
    .from('partners')
    .insert({
      profile_id: testCustomerId, // reuse customer for simplicity
      name: 'Test Partner',
      address: '123 Test St',
      lat: 40.7128,
      lng: -74.0060,
      approved: true
    })
    .select('id')
    .single();
  expect(partnerError).toBeNull();
  testPartnerId = partner.id;

  // Create anon client with customer token
  const { data: session } = await serviceClient.auth.admin.generateLink({
    type: 'magiclink',
    email: customer.user!.email!,
  });
  // Actually sign in to get a proper token
  const { data: signIn } = await serviceClient.auth.signInWithPassword({
    email: customer.user!.email!,
    password: 'testpassword123'
  });

  anonClient = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
    global: { headers: { Authorization: `Bearer ${signIn.session!.access_token}` } }
  });
});

afterAll(async () => {
  // Cleanup
  if (testCustomerId) {
    await serviceClient.auth.admin.deleteUser(testCustomerId);
  }
});

describe('Quote Flow', () => {
  it('should create a quote via get_quote Edge Function', async () => {
    const response = await fetch(`${SUPABASE_URL}/functions/v1/get_quote`, {
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
        notes: 'Test quote'
      })
    });

    const result = await response.json();
    expect(response.ok).toBe(true);
    expect(result.success).toBe(true);
    expect(result.quote_id).toBeDefined();
    expect(result.pricing_breakdown).toBeDefined();
    expect(result.pricing_breakdown.customer_total).toBeGreaterThan(0);
    expect(result.expires_at).toBeDefined();
  });

  it('should create delivery from quote via create_delivery Edge Function', async () => {
    // First create a quote
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

    // Now create delivery using the quote
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
    expect(deliveryResponse.ok).toBe(true);
    expect(deliveryResult.success).toBe(true);
    expect(deliveryResult.delivery_id).toBeDefined();
    expect(deliveryResult.quote_id).toBe(quoteResult.quote_id);

    // Verify quote status is 'accepted'
    const { data: quote } = await serviceClient
      .from('quotes')
      .select('status, delivery_id')
      .eq('id', quoteResult.quote_id)
      .single();
    expect(quote?.status).toBe('accepted');
    expect(quote?.delivery_id).toBe(deliveryResult.delivery_id);

    // Verify delivery exists with correct pricing
    const { data: delivery } = await serviceClient
      .from('deliveries')
      .select('fee_charged, driver_payout, platform_cut, status')
      .eq('id', deliveryResult.delivery_id)
      .single();
    expect(delivery?.fee_charged).toBe(quoteResult.pricing_breakdown.customer_total);
    expect(delivery?.driver_payout).toBe(quoteResult.pricing_breakdown.driver_payout);
    expect(delivery?.platform_cut).toBe(quoteResult.pricing_breakdown.platform_cut);
    expect(delivery?.status).toBe('pending');
  });

  it('should reject delivery with mismatched coordinates', async () => {
    // Create a quote
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

    // Try to create delivery with different coordinates
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
        quote_id: quoteResult.quote_id,
        // Mismatched coordinates
        dropoff_lat: 41.0000,
        dropoff_lng: -74.0000
      })
    });

    const deliveryResult = await deliveryResponse.json();
    expect(deliveryResponse.ok).toBe(false);
    expect(deliveryResult.success).toBe(false);
    expect(deliveryResult.error).toBe('quote_coordinates_mismatch');
  });

  it('should reject delivery with expired quote', async () => {
    // Create a quote
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

    // Manually expire the quote
    await serviceClient
      .from('quotes')
      .update({ expires_at: new Date(Date.now() - 1000).toISOString() })
      .eq('id', quoteResult.quote_id);

    // Try to create delivery with expired quote
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
    expect(deliveryResponse.ok).toBe(false);
    expect(deliveryResult.success).toBe(false);
    expect(deliveryResult.error).toBe('quote_expired');
  });
});

describe('Concurrent Quote Race', () => {
  it('should handle concurrent get_quote calls for same route', async () => {
    const promises = Array(5).fill(null).map(() =>
      fetch(`${SUPABASE_URL}/functions/v1/get_quote`, {
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
      })
    );

    const responses = await Promise.all(promises);
    const results = await Promise.all(responses.map(r => r.json()));

    // All should succeed
    for (const result of results) {
      expect(result.success).toBe(true);
      expect(result.quote_id).toBeDefined();
    }

    // All quotes should have same pricing (deterministic)
    const firstTotal = results[0].pricing_breakdown.customer_total;
    for (const result of results) {
      expect(result.pricing_breakdown.customer_total).toBe(firstTotal);
    }
  });
});

describe('Preview Creates Zero Deliveries', () => {
  it('should create quote but not delivery when only previewing', async () => {
    // Just call get_quote - should not create any delivery
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

    // Check no delivery was created for this quote
    const { data: deliveries } = await serviceClient
      .from('deliveries')
      .select('id')
      .eq('customer_id', testCustomerId);

    // The deliveries array should be empty (or not include a delivery for this quote)
    // Actually get_quote doesn't create deliveries, so this should pass
    expect(deliveries).toEqual([]);
  });
});