# frozen_string_literal: true

require 'rack'

module OpenapiFirst
  class App
    def initialize(
      app,
      spec,
      namespace:,
      allow_unknown_operation: !app.nil?
    )
      @stack = Rack::Builder.app do
        freeze_app
        use OpenapiFirst::Router,
            spec: spec,
            allow_unknown_operation: allow_unknown_operation
        use OpenapiFirst::RequestValidation
        run OpenapiFirst::OperationResolver.new(app, namespace: namespace)
      end
    end

    def call(env)
      @stack.call(env)
    end
  end
end
