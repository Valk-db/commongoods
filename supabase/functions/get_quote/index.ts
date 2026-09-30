import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
import {
  calculatePricing,
  getZoneFromDistance,
  isPeakHour,
  type PricingConfig,
  type PricingInput,
  type PricingResult,
} from "../_shared/pricing/index.ts";

interface GetQuoteRequest {
  customer_id: string;
  partner_id: string;
  category: string;
  pickup_address: string;
  pickup_lat: number;
  pickup_lng: number;
  dropoff_address: string;
  dropoff_lat: number;
  dropoff_lng: number;
  estimated_duration_minutes?: number;
  notes?: string;
}

interface GetQuoteResponse {
  success: boolean;
  error?: string;
  quote_id?: string;
  expires_at?: string;
  pricing_breakdown?: {
    customer_total: number;
    components: Array<{ name: string; amount: number; description: string; is_adjustment?: boolean }>;
    platform_cut: number;
    driver_payout: number;
    zone: number;
    distance_miles: number;
    strategy: string;
    is_peak_hour: boolean;
    demand_multiplier: number;
  };
}

// Helper to resolve config from database
async function resolveConfig(
  supabase: ReturnType<typeof createClient>,
  snapshotId: string | null
): Promise<PricingConfig> {
  if (snapshotId) {
    const { data, error } = await supabase
      .from('config_snapshots')
      .select('resolved')
      .eq('id', snapshotId)
      .single();
    if (error || !data) throw new Error('Invalid config snapshot');
    return data.resolved as unknown as PricingConfig;
  } else {
    const { data, error } = await supabase.rpc('resolve_all_config', {
      p_ctx: {},
      p_at: new Date().toISOString(),
    });
    if (error || !data || data.length === 0) throw new Error('Failed to resolve config');
    return data[0].config as unknown as PricingConfig;
  }
}

// Helper to get config snapshot ID
async function getConfigSnapshotId(
  supabase: ReturnType<typeof createClient>,
  config: PricingConfig
): Promise<string> {
  const { data, error } = await supabase
    .from('config_snapshots')
    .select('id')
    .eq('hash', await sha256(JSON.stringify(config)))
    .single();
  if (error || !data) {
    // Create new snapshot
    const { data: newSnapshot, error: createError } = await supabase
      .from('config_snapshots')
      .insert({ hash: await sha256(JSON.stringify(config)), resolved: config as unknown as Record<string, unknown> })
      .select('id')
      .single();
    if (createError || !newSnapshot) throw new Error('Failed to create config snapshot');
    return newSnapshot.id;
  }
  return data.id;
}

// Simple SHA-256 for Deno
async function sha256(input: string): Promise<string> {
  const encoder = new TextEncoder();
  const data = encoder.encode(input);
  const hashBuffer = await crypto.subtle.digest('SHA-256', data);
  const hashArray = Array.from(new Uint8Array(hashBuffer));
  return hashArray.map(b => b.toString(16).padStart(2, '0')).join('');
}

Deno.serve(async (req: Request) => {
  // CORS headers
  const corsHeaders = {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
  };

  if (req.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return new Response(JSON.stringify({ success: false, error: "Method not allowed" }), {
      status: 405,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  try {
    // Verify JWT
    const authHeader = req.headers.get("Authorization");
    if (!authHeader || !authHeader.startsWith("Bearer ")) {
      return new Response(JSON.stringify({ success: false, error: "Missing authorization" }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const token = authHeader.replace("Bearer ", "");
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_ANON_KEY")!,
      { global: { headers: { Authorization: `Bearer ${token}` } } }
    );

    const { data: { user }, error: userError } = await supabase.auth.getUser(token);
    if (userError || !user) {
      return new Response(JSON.stringify({ success: false, error: "Invalid token" }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const body: GetQuoteRequest = await req.json();

    // Validate required fields
    if (!body.customer_id || body.customer_id !== user.id) {
      return new Response(JSON.stringify({ success: false, error: "Invalid customer_id" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    if (!body.partner_id) {
      return new Response(JSON.stringify({ success: false, error: "Missing partner_id" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // Validate coordinates
    if (body.pickup_lat < -90 || body.pickup_lat > 90 || body.pickup_lng < -180 || body.pickup_lng > 180) {
      return new Response(JSON.stringify({ success: false, error: "Invalid pickup coordinates" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }
    if (body.dropoff_lat < -90 || body.dropoff_lat > 90 || body.dropoff_lng < -180 || body.dropoff_lng > 180) {
      return new Response(JSON.stringify({ success: false, error: "Invalid dropoff coordinates" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // Validate category allowlist
    const validCategories = ['Auto Parts', 'Hardware', 'Pharmacy', 'Catering', 'Office Supply', 'Other'];
    if (!validCategories.includes(body.category)) {
      return new Response(JSON.stringify({ success: false, error: "Invalid category" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // Validate notes length
    if (body.notes && body.notes.length > 500) {
      return new Response(JSON.stringify({ success: false, error: "Notes too long (max 500 chars)" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // Check for mock routing provider (for tests)
    const routingProvider = Deno.env.get("ROUTING_PROVIDER");
    let distanceMiles: number;
    let durationMinutes: number;

    if (routingProvider === "mock") {
      // Deterministic mock: haversine distance + simple duration estimate
      const R = 6371000; // Earth radius in meters
      const φ1 = body.pickup_lat * Math.PI / 180;
      const φ2 = body.dropoff_lat * Math.PI / 180;
      const Δφ = (body.dropoff_lat - body.pickup_lat) * Math.PI / 180;
      const Δλ = (body.dropoff_lng - body.pickup_lng) * Math.PI / 180;

      const a = Math.sin(Δφ / 2) * Math.sin(Δφ / 2) +
        Math.cos(φ1) * Math.cos(φ2) *
        Math.sin(Δλ / 2) * Math.sin(Δλ / 2);
      const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
      const distanceMeters = R * c;
      distanceMiles = distanceMeters * 0.000621371;

      // Simple duration: 30 mph average = 2 min/mile + 5 min base
      durationMinutes = Math.ceil(distanceMiles * 2 + 5);
    } else {
      // Call Mapbox Directions API to get distance and route
      const mapboxToken = Deno.env.get("MAPBOX_SECRET_TOKEN");
      if (!mapboxToken) {
        return new Response(JSON.stringify({ success: false, error: "Mapbox token not configured" }), {
          status: 500,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        });
      }

      const directionsUrl = new URL("https://api.mapbox.com/directions/v5/mapbox/driving/");
      directionsUrl.pathname += `${body.pickup_lng},${body.pickup_lat};${body.dropoff_lng},${body.dropoff_lat}`;
      directionsUrl.searchParams.set("geometries", "polyline6");
      directionsUrl.searchParams.set("overview", "simplified");
      directionsUrl.searchParams.set("access_token", mapboxToken);

      // Add timeout and retry
      const controller = new AbortController();
      const timeoutId = setTimeout(() => controller.abort(), 5000); // 5 second timeout

      let directionsResponse: Response;
      try {
        directionsResponse = await fetch(directionsUrl.toString(), { signal: controller.signal });
      } catch (e) {
        clearTimeout(timeoutId);
        // Retry once
        try {
          directionsResponse = await fetch(directionsUrl.toString());
        } catch (e2) {
          return new Response(JSON.stringify({ success: false, error: "Mapbox API error" }), {
            status: 502,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
          });
        }
      }
      clearTimeout(timeoutId);

      if (!directionsResponse.ok) {
        return new Response(JSON.stringify({ success: false, error: "Mapbox API error" }), {
          status: 502,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        });
      }

      const directionsData = await directionsResponse.json();
      if (!directionsData.routes || directionsData.routes.length === 0) {
        return new Response(JSON.stringify({ success: false, error: "No route found" }), {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        });
      }

      const route = directionsData.routes[0];
      const distanceMeters = route.distance;
      distanceMiles = distanceMeters * 0.000621371;
      const durationSeconds = route.duration;
      durationMinutes = Math.ceil(durationSeconds / 60);
    }

    // Resolve config
    const config = await resolveConfig(supabase, null);

    // Determine zone
    let zone: 1 | 2 | 3;
    try {
      zone = getZoneFromDistance(distanceMiles, config.distanceBands);
    } catch {
      return new Response(JSON.stringify({ success: false, error: "OUTSIDE_SERVICE_AREA" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // Check max distance
    const maxDistance = config.geo?.maxDistanceMiles || 20;
    if (distanceMiles > maxDistance) {
      return new Response(JSON.stringify({ success: false, error: "OUTSIDE_SERVICE_AREA" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // Check peak hours
    const isPeak = isPeakHour(config.peakHours, new Date());

    // Prepare pricing input
    const pricingInput: PricingInput = {
      distanceMiles,
      estimatedDurationMinutes: durationMinutes,
      zone,
      isPeakHour: isPeak,
      weatherSurcharge: config.weatherSurcharge || 0,
    };

    // Calculate pricing using shared engine
    const pricingResult: PricingResult = calculatePricing(config, pricingInput);

    // Verify components sum
    if (Math.abs(pricingResult.components.reduce((a, c) => a + c.amount, 0) - pricingResult.customerTotal) > 0.01) {
      console.error('Components do not sum to customerTotal');
    }

    // Get config snapshot ID
    const configSnapshotId = await getConfigSnapshotId(supabase, config);

    // Service role client for DB operations
    const serviceRoleSupabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
    );

    // Get active algorithm version
    const { data: algoVersion } = await serviceRoleSupabase
      .from('algorithm_versions')
      .select('id')
      .eq('kind', 'pricing')
      .eq('name', config.strategy)
      .eq('status', 'active')
      .order('created_at', { ascending: false })
      .limit(1)
      .single();

    // Create quote (expires in 15 minutes)
    const expiresAt = new Date(Date.now() + 15 * 60 * 1000).toISOString();
    const { data: quote, error: quoteError } = await serviceRoleSupabase
      .from('quotes')
      .insert({
        customer_id: body.customer_id,
        partner_id: body.partner_id,
        pickup_lat: body.pickup_lat,
        pickup_lng: body.pickup_lng,
        dropoff_lat: body.dropoff_lat,
        dropoff_lng: body.dropoff_lng,
        distance_miles: distanceMiles,
        estimated_duration_minutes: durationMinutes,
        zone_assigned: zone,
        customer_total: pricingResult.customerTotal,
        components: pricingResult.components,
        platform_cut: pricingResult.platformCut,
        driver_payout: pricingResult.driverPayout,
        pricing_algorithm_version: algoVersion?.id,
        config_snapshot_id: configSnapshotId,
        status: 'generated',
        expires_at: expiresAt,
      })
      .select('id')
      .single();

    if (quoteError || !quote) {
      console.error("Quote insert error:", quoteError);
      return new Response(JSON.stringify({ success: false, error: "Failed to create quote" }), {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    return new Response(JSON.stringify({
      success: true,
      quote_id: quote.id,
      expires_at: expiresAt,
      pricing_breakdown: {
        customer_total: pricingResult.customerTotal,
        components: pricingResult.components,
        platform_cut: pricingResult.platformCut,
        driver_payout: pricingResult.driverPayout,
        zone: pricingResult.zone,
        distance_miles: pricingResult.distanceMiles,
        strategy: pricingResult.strategy,
        is_peak_hour: isPeak,
        demand_multiplier: isPeak ? config.demandMultiplier.min : 1.0,
      },
    }), {
      status: 200,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (err) {
    console.error("get_quote error:", err);
    return new Response(JSON.stringify({ success: false, error: "Internal server error" }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});