# frozen_string_literal: true

require_relative '../failure'

module OpenapiFirst
  module RequestValidation
    class RequestBodyValidator # :nodoc:
      def initialize(request_body, openapi_version:, config:)
        @request_body = request_body
        @openapi_version = openapi_version
        @config = config
      end

      def validate!(parsed_request_body, request_content_type)
        schema = schema_for(request_content_type)
        unless schema
          Failure.fail!(:unsupported_media_type,
                        message: "Unsupported Media Type '#{request_content_type}'")
        end

        if @request_body.required? && parsed_request_body.nil?
          Failure.fail!(:invalid_body,
                        message: 'Request body is not defined')
        end

        validate_body!(parsed_request_body, schema)
      end

      private

      attr_reader :operation, :config, :openapi_version

      def schema_for(content_type)
        @schema_for ||= {}
        @schema_for.fetch(content_type) do
          schema = @request_body.schema_for(content_type)
          return unless schema

          after_property_validation = config.hooks[:after_request_body_property_validation]
          @schema_for[content_type] = Schema.new(schema, openapi_version:, after_property_validation:)
        end
      end

      def validate_body!(parsed_request_body, schema)
        request_body_schema = schema
        return unless request_body_schema

        validation = request_body_schema.validate(parsed_request_body)
        Failure.fail!(:invalid_body, errors: validation.errors) if validation.error?
      end
    end
  end
end
