# frozen_string_literal: true

require "test_helper"

module SolidEvents
  class LabelerTest < ActiveSupport::TestCase
    test "maps common actions" do
      assert_equal "order.created", SolidEvents::Labeler.controller_action(controller_name: "OrdersController", action_name: "create", status: 201)
      assert_equal "user.updated", SolidEvents::Labeler.controller_action(controller_name: "UsersController", action_name: "update", status: 200)
      assert_equal "session.ended", SolidEvents::Labeler.controller_action(controller_name: "SessionsController", action_name: "destroy", status: 204)
    end
  end
end
