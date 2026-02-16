# frozen_string_literal: true

require "test_helper"

module SolidEvents
  class SavedViewsControllerTest < ActionDispatch::IntegrationTest
    test "create stores a saved view with filter payload" do
      post "/solid_events/saved_views", params: {
        name: "Checkout Failures",
        created_by: "alice",
        filters: {
          "source" => "CheckoutController#create",
          "status" => "error",
          "unknown_key" => "ignored"
        }
      }

      assert_response :redirect
      saved_view = SolidEvents::SavedView.last
      assert_equal "Checkout Failures", saved_view.name
      assert_equal "alice", saved_view.created_by
      assert_equal "CheckoutController#create", saved_view.filters["source"]
      assert_equal "error", saved_view.filters["status"]
      assert_nil saved_view.filters["unknown_key"]
    end

    test "destroy removes saved view" do
      saved_view = SolidEvents::SavedView.create!(
        name: "Delete me",
        filters: {"status" => "error"}
      )

      delete "/solid_events/saved_views/#{saved_view.id}"
      assert_response :redirect
      assert_nil SolidEvents::SavedView.find_by(id: saved_view.id)
    end
  end
end
