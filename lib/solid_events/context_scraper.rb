# frozen_string_literal: true

module SolidEvents
  module ContextScraper
    module_function

    def from_controller(controller)
      context = {}
      if controller.respond_to?(:current_user) && controller.current_user&.respond_to?(:id)
        context[:user_id] = controller.current_user.id
      end
      if controller.respond_to?(:current_account) && controller.current_account&.respond_to?(:id)
        context[:account_id] = controller.current_account.id
      end
      if controller.respond_to?(:tenant_id) && controller.tenant_id.present?
        context[:tenant_id] = controller.tenant_id
      end
      context
    rescue StandardError
      {}
    end
  end
end
