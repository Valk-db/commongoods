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
}

interface CreateDeliveryResponse {
  success: boolean;
  error?: string;
  delivery_id?: string;
  quote_id?: string;
  pricing_breakdown?: {
    customer_total: number;
    components: Array<{ name: string; amount: number; description: string }>;
    platform_cut: number;
    driver_payout: number;
    zone: number;
    distance_miles: number;
    strategy: string;
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

    const body: CreateDeliveryRequest = await req.json();

    // Validate required fields
    if (!body.customer_id || body.customer_id !== user.id) {
      return new Response(JSON.stringify({ success: false, error: "Invalid customer_id" }), {
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
    directionsUrl.searchParams.set("overview", "full");
    directionsUrl.searchParams.set("access_token", mapboxToken);

    const directionsResponse = await fetch(directionsUrl.toString());
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

    // Check max distance
    const maxDistance = 20; // Will be from config in future
    if (distanceMiles > maxDistance) {
      return new Response(JSON.stringify({ success: false, error: "OUTSIDE_SERVICE_AREA" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // Now call the create_delivery RPC with service role
    const serviceRoleSupabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
    );

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
      p_config_snapshot_id: null, // Will use current config
    });

    if (error) {
      console.error("create_delivery RPC error:", error);
      return new Response(JSON.stringify({ success: false, error: error.message }), {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const result = data[0] as CreateDeliveryResponse;
    return new Response(JSON.stringify(result), {
      status: result.success ? 200 : 400,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (err) {
    console.error("create_delivery error:", err);
    return new Response(JSON.stringify({ success: false, error: "Internal server error" }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});