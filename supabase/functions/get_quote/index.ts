import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

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

    // Check max distance from config (will be validated in RPC)
    // We'll let the RPC handle the OUTSIDE_SERVICE_AREA check

    // Now call the create_delivery RPC with service role to get pricing
    // We pass a special flag to indicate this is a quote request (not actual delivery)
    const serviceRoleSupabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
    );

    // Call a get_quote RPC that computes pricing but doesn't create delivery
    const { data, error } = await serviceRoleSupabase.rpc("get_quote", {
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
    });

    if (error) {
      console.error("get_quote RPC error:", error);
      return new Response(JSON.stringify({ success: false, error: error.message }), {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const result = data[0] as GetQuoteResponse;
    return new Response(JSON.stringify(result), {
      status: result.success ? 200 : 400,
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