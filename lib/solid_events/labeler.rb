# frozen_string_literal: true

module SolidEvents
  module Labeler
    module_function

    def controller_action(controller_name:, action_name:, status:)
      base = controller_name.to_s.sub(/Controller\z/, "").underscore.singularize
      verb = action_to_verb(action_name.to_s, status.to_i)
      "#{base}.#{verb}"
    end

    def action_to_verb(action, status)
      return "created" if action == "create" && status.between?(200, 299)
      return "updated" if action == "update" && status.between?(200, 299)
      return "ended" if action == "destroy" && status.between?(200, 399)

      action
    end
  end
end
