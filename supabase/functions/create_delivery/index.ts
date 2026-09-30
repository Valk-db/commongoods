import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

interface CreateDeliveryRequest {
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
  idempotency_key?: string;
  quote_id?: string;
}

interface CreateDeliveryResponse {
  success: boolean;
  error?: string;
  delivery_id?: string;
  quote_id?: string;
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

// Rate limiting: track requests per customer per minute
const rateLimitMap = new Map<string, { count: number; resetAt: number }>();
const RATE_LIMIT_MAX = 10; // max 10 requests per minute
const RATE_LIMIT_WINDOW_MS = 60 * 1000;

// Idempotency key storage (in production, use Redis or DB)
const idempotencyStore = new Map<string, { response: CreateDeliveryResponse; expiresAt: number }>();
const IDEMPOTENCY_TTL_MS = 10 * 60 * 1000; // 10 minutes

function checkRateLimit(customerId: string): boolean {
  const now = Date.now();
  const entry = rateLimitMap.get(customerId);

  if (!entry || entry.resetAt < now) {
    rateLimitMap.set(customerId, { count: 1, resetAt: now + RATE_LIMIT_WINDOW_MS });
    return true;
  }

  if (entry.count >= RATE_LIMIT_MAX) {
    return false;
  }

  entry.count++;
  return true;
}

function checkIdempotency(key: string): CreateDeliveryResponse | null {
  const entry = idempotencyStore.get(key);
  if (!entry) return null;

  if (entry.expiresAt < Date.now()) {
    idempotencyStore.delete(key);
    return null;
  }

  return entry.response;
}

function storeIdempotency(key: string, response: CreateDeliveryResponse): void {
  idempotencyStore.set(key, {
    response,
    expiresAt: Date.now() + IDEMPOTENCY_TTL_MS
  });
}

function sanitizeError(error: unknown): string {
  // Never return raw error messages to clients
  if (error instanceof Error) {
    // Only expose safe error codes
    const safeErrors = [
      'OUTSIDE_SERVICE_AREA',
      'invalid_distance',
      'missing_customer_id',
      'invalid_customer_id',
      'missing_partner_id',
      'invalid_partner',
      'partner_not_approved',
      'pickup_mismatch',
      'invalid_category',
      'notes_too_long',
      'invalid_coordinates',
      'no_route_found',
      'Mapbox API error'
    ];
    if (safeErrors.includes(error.message)) {
      return error.message;
    }
  }
  return "Internal server error";
}

Deno.serve(async (req: Request) => {
  // CORS headers
  const corsHeaders = {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, idempotency-key",
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

    // Check idempotency key from header
    const idempotencyKey = req.headers.get("idempotency-key");
    if (idempotencyKey) {
      const cached = checkIdempotency(idempotencyKey);
      if (cached) {
        return new Response(JSON.stringify(cached), {
          status: cached.success ? 200 : 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        });
      }
    }

    // Check rate limit
    if (!checkRateLimit(user.id)) {
      return new Response(JSON.stringify({ success: false, error: "Rate limit exceeded" }), {
        status: 429,
        headers: { ...corsHeaders, "Content-Type": "application/json", "Retry-After": "60" },
      });
    }

    const body: CreateDeliveryRequest = await req.json();

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

    // Validate string lengths
    if (body.pickup_address.length > 500 || body.dropoff_address.length > 500) {
      return new Response(JSON.stringify({ success: false, error: "Address too long (max 500 chars)" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // Verify partner exists and is approved, and pickup matches
    const serviceRoleSupabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
    );

    const { data: partner, error: partnerError } = await serviceRoleSupabase
      .from('partners')
      .select('id, lat, lng, approved')
      .eq('id', body.partner_id)
      .single();

    if (partnerError || !partner) {
      return new Response(JSON.stringify({ success: false, error: "Invalid partner" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    if (!partner.approved) {
      return new Response(JSON.stringify({ success: false, error: "Partner not approved" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // Verify pickup location matches partner's stored location (within 100m)
    if (partner.lat && partner.lng) {
      const R = 6371e3; // Earth radius in meters
      const φ1 = body.pickup_lat * Math.PI / 180;
      const φ2 = partner.lat * Math.PI / 180;
      const Δφ = (partner.lat - body.pickup_lat) * Math.PI / 180;
      const Δλ = (partner.lng - body.pickup_lng) * Math.PI / 180;

      const a = Math.sin(Δφ / 2) * Math.sin(Δφ / 2) +
        Math.cos(φ1) * Math.cos(φ2) *
        Math.sin(Δλ / 2) * Math.sin(Δλ / 2);
      const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
      const distance = R * c; // meters

      if (distance > 100) { // 100 meters tolerance
        return new Response(JSON.stringify({ success: false, error: "Pickup location does not match partner" }), {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        });
      }
    }

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
    const distanceMiles = distanceMeters * 0.000621371;
    const durationSeconds = route.duration;
    const durationMinutes = Math.ceil(durationSeconds / 60);
    const routePolyline = route.geometry;

    // Get max distance from config
    const { data: configData, error: configError } = await serviceRoleSupabase.rpc('resolve_config', {
      p_key: 'geo.max_distance_miles',
      p_ctx: {},
      p_at: new Date().toISOString()
    });

    const maxDistance = configData || 20;
    if (distanceMiles > maxDistance) {
      return new Response(JSON.stringify({ success: false, error: "OUTSIDE_SERVICE_AREA" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // Now call the create_delivery RPC with service role
    const { data, error } = await serviceRoleSupabase.rpc("create_delivery", {
      p_customer_id: body.customer_id,
      p_partner_id: body.partner_id,
      p_category: body.category,
      p_pickup_address: body.pickup_address,
      p_pickup_lat: body.pickup_lat,
      p_pickup_lng: body.pickup_lng,
      p_dropoff_address: body.dropoff_address,
      p_dropoff_lat: body.dropoff_lat,
      p_dropoff_lng: body.dropoff_lng,
      p_distance_miles: distanceMiles,
      p_estimated_duration_minutes: durationMinutes,
      p_notes: body.notes,
      p_config_snapshot_id: null,
      p_quote_id: body.quote_id,
    });

    if (error) {
      console.error("create_delivery RPC error:", error);
      return new Response(JSON.stringify({ success: false, error: sanitizeError(error) }), {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const result = data[0] as CreateDeliveryResponse;

    // Store idempotency key response if provided
    if (idempotencyKey && result.success) {
      storeIdempotency(idempotencyKey, result);
    }

    return new Response(JSON.stringify(result), {
      status: result.success ? 200 : 400,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (err) {
    console.error("create_delivery error:", err);
    return new Response(JSON.stringify({ success: false, error: sanitizeError(err) }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});