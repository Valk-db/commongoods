export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[]

export type Database = {
  // Allows to automatically instantiate createClient with right options
  // instead of createClient<Database, { PostgrestVersion: 'XX' }>(URL, KEY)
  __InternalSupabase: {
    PostgrestVersion: "14.5"
  }
  graphql_public: {
    Tables: {
      [_ in never]: never
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
      graphql: {
        Args: {
          extensions?: Json
          operationName?: string
          query?: string
          variables?: Json
        }
        Returns: Json
      }
    }
    Enums: {
      [_ in never]: never
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
  public: {
    Tables: {
      deliveries: {
        Row: {
          actual_duration_minutes: number | null
          base_fee_applied: number | null
          cancellation_reason_code: string | null
          cancelled_by: string | null
          category: string
          claimed_at: string | null
          customer_id: string | null
          delivered_at: string | null
          distance_miles: number | null
          driver_arrived_at_dropoff_at: string | null
          driver_arrived_at_pickup_at: string | null
          driver_id: string | null
          driver_payout: number | null
          dropoff_address: string
          dropoff_lat: number
          dropoff_lng: number
          dynamic_boost_incentive: number | null
          estimated_duration_minutes: number | null
          fee_charged: number | null
          id: string
          notes: string | null
          partner_id: string | null
          per_mile_rate_applied: number | null
          picked_up_at: string | null
          pickup_address: string
          pickup_lat: number
          pickup_lng: number
          platform_cut: number | null
          ready_for_pickup_at: string | null
          requested_at: string | null
          route_polyline: string | null
          status: string | null
          surge_multiplier_applied: number | null
          tip_amount: number | null
          transport_type: string | null
          zone_assigned: number | null
        }
        Insert: {
          actual_duration_minutes?: number | null
          base_fee_applied?: number | null
          cancellation_reason_code?: string | null
          cancelled_by?: string | null
          category: string
          claimed_at?: string | null
          customer_id?: string | null
          delivered_at?: string | null
          distance_miles?: number | null
          driver_arrived_at_dropoff_at?: string | null
          driver_arrived_at_pickup_at?: string | null
          driver_id?: string | null
          driver_payout?: number | null
          dropoff_address: string
          dropoff_lat: number
          dropoff_lng: number
          dynamic_boost_incentive?: number | null
          estimated_duration_minutes?: number | null
          fee_charged?: number | null
          id?: string
          notes?: string | null
          partner_id?: string | null
          per_mile_rate_applied?: number | null
          picked_up_at?: string | null
          pickup_address: string
          pickup_lat: number
          pickup_lng: number
          platform_cut?: number | null
          ready_for_pickup_at?: string | null
          requested_at?: string | null
          route_polyline?: string | null
          status?: string | null
          surge_multiplier_applied?: number | null
          tip_amount?: number | null
          transport_type?: string | null
          zone_assigned?: number | null
        }
        Update: {
          actual_duration_minutes?: number | null
          base_fee_applied?: number | null
          cancellation_reason_code?: string | null
          cancelled_by?: string | null
          category?: string
          claimed_at?: string | null
          customer_id?: string | null
          delivered_at?: string | null
          distance_miles?: number | null
          driver_arrived_at_dropoff_at?: string | null
          driver_arrived_at_pickup_at?: string | null
          driver_id?: string | null
          driver_payout?: number | null
          dropoff_address?: string
          dropoff_lat?: number
          dropoff_lng?: number
          dynamic_boost_incentive?: number | null
          estimated_duration_minutes?: number | null
          fee_charged?: number | null
          id?: string
          notes?: string | null
          partner_id?: string | null
          per_mile_rate_applied?: number | null
          picked_up_at?: string | null
          pickup_address?: string
          pickup_lat?: number
          pickup_lng?: number
          platform_cut?: number | null
          ready_for_pickup_at?: string | null
          requested_at?: string | null
          route_polyline?: string | null
          status?: string | null
          surge_multiplier_applied?: number | null
          tip_amount?: number | null
          transport_type?: string | null
          zone_assigned?: number | null
        }
        Relationships: [
          {
            foreignKeyName: "deliveries_customer_id_fkey"
            columns: ["customer_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "deliveries_driver_id_fkey"
            columns: ["driver_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "deliveries_partner_id_fkey"
            columns: ["partner_id"]
            isOneToOne: false
            referencedRelation: "partners"
            referencedColumns: ["id"]
          },
        ]
      }
      delivery_item_options: {
        Row: {
          delivery_item_id: string | null
          id: string
          menu_item_option_id: string | null
          price_at_purchase: number
        }
        Insert: {
          delivery_item_id?: string | null
          id?: string
          menu_item_option_id?: string | null
          price_at_purchase: number
        }
        Update: {
          delivery_item_id?: string | null
          id?: string
          menu_item_option_id?: string | null
          price_at_purchase?: number
        }
        Relationships: [
          {
            foreignKeyName: "delivery_item_options_delivery_item_id_fkey"
            columns: ["delivery_item_id"]
            isOneToOne: false
            referencedRelation: "delivery_items"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "delivery_item_options_menu_item_option_id_fkey"
            columns: ["menu_item_option_id"]
            isOneToOne: false
            referencedRelation: "menu_item_options"
            referencedColumns: ["id"]
          },
        ]
      }
      delivery_items: {
        Row: {
          delivery_id: string | null
          id: string
          menu_item_id: string | null
          price_at_purchase: number
          quantity: number
        }
        Insert: {
          delivery_id?: string | null
          id?: string
          menu_item_id?: string | null
          price_at_purchase: number
          quantity?: number
        }
        Update: {
          delivery_id?: string | null
          id?: string
          menu_item_id?: string | null
          price_at_purchase?: number
          quantity?: number
        }
        Relationships: [
          {
            foreignKeyName: "delivery_items_delivery_id_fkey"
            columns: ["delivery_id"]
            isOneToOne: false
            referencedRelation: "deliveries"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "delivery_items_menu_item_id_fkey"
            columns: ["menu_item_id"]
            isOneToOne: false
            referencedRelation: "menu_items"
            referencedColumns: ["id"]
          },
        ]
      }
      delivery_messages: {
        Row: {
          created_at: string | null
          delivery_id: string | null
          id: string
          message_text: string
          sender_id: string | null
        }
        Insert: {
          created_at?: string | null
          delivery_id?: string | null
          id?: string
          message_text: string
          sender_id?: string | null
        }
        Update: {
          created_at?: string | null
          delivery_id?: string | null
          id?: string
          message_text?: string
          sender_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "delivery_messages_delivery_id_fkey"
            columns: ["delivery_id"]
            isOneToOne: false
            referencedRelation: "deliveries"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "delivery_messages_sender_id_fkey"
            columns: ["sender_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      delivery_status_history: {
        Row: {
          actor_id: string | null
          changed_at: string | null
          delivery_id: string | null
          id: string
          lat: number | null
          lng: number | null
          status: string
        }
        Insert: {
          actor_id?: string | null
          changed_at?: string | null
          delivery_id?: string | null
          id?: string
          lat?: number | null
          lng?: number | null
          status: string
        }
        Update: {
          actor_id?: string | null
          changed_at?: string | null
          delivery_id?: string | null
          id?: string
          lat?: number | null
          lng?: number | null
          status?: string
        }
        Relationships: [
          {
            foreignKeyName: "delivery_status_history_actor_id_fkey"
            columns: ["actor_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "delivery_status_history_delivery_id_fkey"
            columns: ["delivery_id"]
            isOneToOne: false
            referencedRelation: "deliveries"
            referencedColumns: ["id"]
          },
        ]
      }
      drivers: {
        Row: {
          approved: boolean | null
          id: string
          is_online: boolean
          updated_at: string | null
          vehicle_type: string | null
        }
        Insert: {
          approved?: boolean | null
          id: string
          is_online?: boolean
          updated_at?: string | null
          vehicle_type?: string | null
        }
        Update: {
          approved?: boolean | null
          id?: string
          is_online?: boolean
          updated_at?: string | null
          vehicle_type?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "drivers_id_fkey"
            columns: ["id"]
            isOneToOne: true
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      earnings: {
        Row: {
          amount: number
          created_at: string | null
          delivery_id: string | null
          driver_id: string | null
          id: string
          paid_out: boolean | null
          platform_cut: number
        }
        Insert: {
          amount: number
          created_at?: string | null
          delivery_id?: string | null
          driver_id?: string | null
          id?: string
          paid_out?: boolean | null
          platform_cut: number
        }
        Update: {
          amount?: number
          created_at?: string | null
          delivery_id?: string | null
          driver_id?: string | null
          id?: string
          paid_out?: boolean | null
          platform_cut?: number
        }
        Relationships: [
          {
            foreignKeyName: "earnings_delivery_id_fkey"
            columns: ["delivery_id"]
            isOneToOne: false
            referencedRelation: "deliveries"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "earnings_driver_id_fkey"
            columns: ["driver_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      menu_item_options: {
        Row: {
          id: string
          is_available: boolean | null
          menu_item_id: string | null
          name: string
          price_modifier: number | null
        }
        Insert: {
          id?: string
          is_available?: boolean | null
          menu_item_id?: string | null
          name: string
          price_modifier?: number | null
        }
        Update: {
          id?: string
          is_available?: boolean | null
          menu_item_id?: string | null
          name?: string
          price_modifier?: number | null
        }
        Relationships: [
          {
            foreignKeyName: "menu_item_options_menu_item_id_fkey"
            columns: ["menu_item_id"]
            isOneToOne: false
            referencedRelation: "menu_items"
            referencedColumns: ["id"]
          },
        ]
      }
      menu_items: {
        Row: {
          active: boolean | null
          category: string | null
          created_at: string | null
          description: string | null
          id: string
          name: string
          partner_id: string | null
          photo_url: string | null
          price: number
        }
        Insert: {
          active?: boolean | null
          category?: string | null
          created_at?: string | null
          description?: string | null
          id?: string
          name: string
          partner_id?: string | null
          photo_url?: string | null
          price: number
        }
        Update: {
          active?: boolean | null
          category?: string | null
          created_at?: string | null
          description?: string | null
          id?: string
          name?: string
          partner_id?: string | null
          photo_url?: string | null
          price?: number
        }
        Relationships: [
          {
            foreignKeyName: "menu_items_partner_id_fkey"
            columns: ["partner_id"]
            isOneToOne: false
            referencedRelation: "partners"
            referencedColumns: ["id"]
          },
        ]
      }
      partner_applications: {
        Row: {
          address: string
          business_name: string
          contact_email: string
          contact_name: string
          contact_phone: string
          id: string
          notes: string | null
          pos_system: string | null
          status: string | null
          submitted_at: string | null
        }
        Insert: {
          address: string
          business_name: string
          contact_email: string
          contact_name: string
          contact_phone: string
          id?: string
          notes?: string | null
          pos_system?: string | null
          status?: string | null
          submitted_at?: string | null
        }
        Update: {
          address?: string
          business_name?: string
          contact_email?: string
          contact_name?: string
          contact_phone?: string
          id?: string
          notes?: string | null
          pos_system?: string | null
          status?: string | null
          submitted_at?: string | null
        }
        Relationships: []
      }
      partners: {
        Row: {
          address: string
          approved: boolean | null
          average_prep_time_minutes: number | null
          business_name: string
          created_at: string | null
          founding_merchant: boolean | null
          id: string
          joined_during_pilot: boolean | null
          lat: number | null
          lng: number | null
          merchant_priority_score: number | null
          onboarding_fee_paid: boolean | null
          pickup_notes: string | null
          pos_system: string | null
          profile_id: string | null
        }
        Insert: {
          address: string
          approved?: boolean | null
          average_prep_time_minutes?: number | null
          business_name: string
          created_at?: string | null
          founding_merchant?: boolean | null
          id?: string
          joined_during_pilot?: boolean | null
          lat?: number | null
          lng?: number | null
          merchant_priority_score?: number | null
          onboarding_fee_paid?: boolean | null
          pickup_notes?: string | null
          pos_system?: string | null
          profile_id?: string | null
        }
        Update: {
          address?: string
          approved?: boolean | null
          average_prep_time_minutes?: number | null
          business_name?: string
          created_at?: string | null
          founding_merchant?: boolean | null
          id?: string
          joined_during_pilot?: boolean | null
          lat?: number | null
          lng?: number | null
          merchant_priority_score?: number | null
          onboarding_fee_paid?: boolean | null
          pickup_notes?: string | null
          pos_system?: string | null
          profile_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "partners_profile_id_fkey"
            columns: ["profile_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      performance_metrics: {
        Row: {
          actual_prep_minutes: number | null
          actual_transit_minutes: number | null
          delivery_id: string
          driver_wait_at_merchant_minutes: number | null
          estimated_prep_minutes: number | null
          estimated_transit_minutes: number | null
          had_interaction_issues: boolean | null
          prep_delay_minutes: number | null
          transit_delay_minutes: number | null
        }
        Insert: {
          actual_prep_minutes?: number | null
          actual_transit_minutes?: number | null
          delivery_id: string
          driver_wait_at_merchant_minutes?: number | null
          estimated_prep_minutes?: number | null
          estimated_transit_minutes?: number | null
          had_interaction_issues?: boolean | null
          prep_delay_minutes?: number | null
          transit_delay_minutes?: number | null
        }
        Update: {
          actual_prep_minutes?: number | null
          actual_transit_minutes?: number | null
          delivery_id?: string
          driver_wait_at_merchant_minutes?: number | null
          estimated_prep_minutes?: number | null
          estimated_transit_minutes?: number | null
          had_interaction_issues?: boolean | null
          prep_delay_minutes?: number | null
          transit_delay_minutes?: number | null
        }
        Relationships: [
          {
            foreignKeyName: "performance_metrics_delivery_id_fkey"
            columns: ["delivery_id"]
            isOneToOne: true
            referencedRelation: "deliveries"
            referencedColumns: ["id"]
          },
        ]
      }
      profiles: {
        Row: {
          cancellation_rate: number | null
          created_at: string | null
          full_name: string | null
          historical_tip_ratio: number | null
          id: string
          is_admin: boolean
          lifetime_deliveries: number | null
          phone: string | null
          priority_score: number | null
          role: string
        }
        Insert: {
          cancellation_rate?: number | null
          created_at?: string | null
          full_name?: string | null
          historical_tip_ratio?: number | null
          id: string
          is_admin?: boolean
          lifetime_deliveries?: number | null
          phone?: string | null
          priority_score?: number | null
          role: string
        }
        Update: {
          cancellation_rate?: number | null
          created_at?: string | null
          full_name?: string | null
          historical_tip_ratio?: number | null
          id?: string
          is_admin?: boolean
          lifetime_deliveries?: number | null
          phone?: string | null
          priority_score?: number | null
          role?: string
        }
        Relationships: []
      }
      ratings_and_reviews: {
        Row: {
          created_at: string | null
          delivery_id: string | null
          id: string
          rating_stars: number
          reviewee_id: string | null
          reviewee_type: string
          reviewer_id: string | null
          tags: string[] | null
          written_review: string | null
        }
        Insert: {
          created_at?: string | null
          delivery_id?: string | null
          id?: string
          rating_stars: number
          reviewee_id?: string | null
          reviewee_type: string
          reviewer_id?: string | null
          tags?: string[] | null
          written_review?: string | null
        }
        Update: {
          created_at?: string | null
          delivery_id?: string | null
          id?: string
          rating_stars?: number
          reviewee_id?: string | null
          reviewee_type?: string
          reviewer_id?: string | null
          tags?: string[] | null
          written_review?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "ratings_and_reviews_delivery_id_fkey"
            columns: ["delivery_id"]
            isOneToOne: false
            referencedRelation: "deliveries"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ratings_and_reviews_reviewee_id_fkey"
            columns: ["reviewee_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ratings_and_reviews_reviewer_id_fkey"
            columns: ["reviewer_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      referral_codes: {
        Row: {
          code: string
          created_at: string | null
          expires_at: string | null
          id: string
          is_active: boolean | null
          label: string | null
          role: string
          used_at: string | null
          used_by: string | null
        }
        Insert: {
          code: string
          created_at?: string | null
          expires_at?: string | null
          id?: string
          is_active?: boolean | null
          label?: string | null
          role: string
          used_at?: string | null
          used_by?: string | null
        }
        Update: {
          code?: string
          created_at?: string | null
          expires_at?: string | null
          id?: string
          is_active?: boolean | null
          label?: string | null
          role?: string
          used_at?: string | null
          used_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "referral_codes_used_by_fkey"
            columns: ["used_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      route_points: {
        Row: {
          delivery_id: string | null
          driver_speed: number | null
          id: string
          lat: number
          lng: number
          recorded_at: string | null
        }
        Insert: {
          delivery_id?: string | null
          driver_speed?: number | null
          id?: string
          lat: number
          lng: number
          recorded_at?: string | null
        }
        Update: {
          delivery_id?: string | null
          driver_speed?: number | null
          id?: string
          lat?: number
          lng?: number
          recorded_at?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "route_points_delivery_id_fkey"
            columns: ["delivery_id"]
            isOneToOne: false
            referencedRelation: "deliveries"
            referencedColumns: ["id"]
          },
        ]
      }
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
      check_user_role: { Args: { required_role: string }; Returns: boolean }
      current_role_is: { Args: { target_role: string }; Returns: boolean }
      get_my_role: { Args: never; Returns: string }
      is_admin: { Args: never; Returns: boolean }
      zone_pricing: {
        Args: { miles: number }
        Returns: {
          driver_payout: number
          fee: number
          platform_cut: number
          zone: number
        }[]
      }
    }
    Enums: {
      [_ in never]: never
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
}

type DatabaseWithoutInternals = Omit<Database, "__InternalSupabase">

type DefaultSchema = DatabaseWithoutInternals[Extract<keyof Database, "public">]

export type Tables<
  DefaultSchemaTableNameOrOptions extends
    | keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
      DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])[TableName] extends {
      Row: infer R
    }
    ? R
    : never
  : DefaultSchemaTableNameOrOptions extends keyof (DefaultSchema["Tables"] &
        DefaultSchema["Views"])
    ? (DefaultSchema["Tables"] &
        DefaultSchema["Views"])[DefaultSchemaTableNameOrOptions] extends {
        Row: infer R
      }
      ? R
      : never
    : never

export type TablesInsert<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Insert: infer I
    }
    ? I
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Insert: infer I
      }
      ? I
      : never
    : never

export type TablesUpdate<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Update: infer U
    }
    ? U
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Update: infer U
      }
      ? U
      : never
    : never

export type Enums<
  DefaultSchemaEnumNameOrOptions extends
    | keyof DefaultSchema["Enums"]
    | { schema: keyof DatabaseWithoutInternals },
  EnumName extends (DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"]
    : never) = never,
> = DefaultSchemaEnumNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"][EnumName]
  : DefaultSchemaEnumNameOrOptions extends keyof DefaultSchema["Enums"]
    ? DefaultSchema["Enums"][DefaultSchemaEnumNameOrOptions]
    : never

export type CompositeTypes<
  PublicCompositeTypeNameOrOptions extends
    | keyof DefaultSchema["CompositeTypes"]
    | { schema: keyof DatabaseWithoutInternals },
  CompositeTypeName extends (PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"]
    : never) = never,
> = PublicCompositeTypeNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof DefaultSchema["CompositeTypes"]
    ? DefaultSchema["CompositeTypes"][PublicCompositeTypeNameOrOptions]
    : never

export const Constants = {
  graphql_public: {
    Enums: {},
  },
  public: {
    Enums: {},
  },
} as const