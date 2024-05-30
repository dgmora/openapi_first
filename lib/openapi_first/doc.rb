# frozen_string_literal: true

require_relative 'failure'
require_relative 'router'
require_relative 'request'
require_relative 'response'

module OpenapiFirst
  # Represents an OpenAPI API Description document
  # This is returned by OpenapiFirst.load.
  class Doc
    attr_reader :filepath, :openapi_version, :config, :paths

    REQUEST_METHODS = %w[get head post put patch delete trace options].freeze
    private_constant :REQUEST_METHODS

    # @param resolved [Hash] The resolved OpenAPI document.
    # @param filepath [String] The file path of the OpenAPI document.
    def initialize(resolved, filepath = nil)
      @filepath = filepath
      @config = OpenapiFirst.configuration.clone
      @openapi_version = detect_version(resolved)
      @router = Router.new

      resolved['paths'].each do |path, path_item_object|
        path_item_object.slice(*REQUEST_METHODS).keys.map do |request_method|
          operation_object = path_item_object[request_method]
          path_item_parameters = path_item_object['parameters']
          build_requests(path, request_method, operation_object, path_item_parameters).each do |request|
            @router.add_request(
              request,
              request_method:,
              path:,
              content_type: request.content_type
            )
          end
          build_responses(operation_object).each do |response|
            @router.add_response(
              response,
              request_method:,
              path:,
              status: response.status,
              response_content_type: response.content_type
            )
          end
        end
      end
      @paths = resolved['paths'].keys
      @response_matchers = {}
      yield @config if block_given?
      @config.freeze
    end

    def routes
      @router.routes
    end

    # Validates the request against the API description.
    # @param rack_request [Rack::Request] The Rack request object.
    # @param raise_error [Boolean] Whether to raise an error if validation fails.
    # @return [Request] The validated request object.
    def validate_request(request, raise_error: false)
      route = @router.match(request.request_method, request.path, content_type: request.content_type)
      validated = if route.error
                    ValidatedRequest.new(request, error: route.error, request_definition: nil)
                  else
                    route.request_definition.validate(request, route_params: route.params)
                  end
      @config.hooks[:after_request_validation].each { |hook| hook.call(validated) }
      validated.error&.raise! if raise_error
      validated
    end

    # Validates the response against the API description.
    # @param rack_request [Rack::Request] The Rack request object.
    # @param rack_response [Rack::Response] The Rack response object.
    # @param raise_error [Boolean] Whether to raise an error if validation fails.
    # @return [Response] The validated response object.
    def validate_response(rack_request, rack_response, raise_error: false)
      route = @router.match(rack_request.request_method, rack_request.path, content_type: rack_request.content_type)
      return if route.error # Skip response validation for unknown requests

      response_match = route.match_response(status: rack_response.status, content_type: rack_response.content_type)
      error = response_match.error
      validated = if error
                    ValidatedResponse.new(rack_response, error)
                  else
                    response_match.response.validate(rack_response)
                  end
      @config.hooks[:after_response_validation]&.each { |hook| hook.call(validated) }
      validated.error&.raise! if raise_error
      validated
    end

    private

    def build_requests(path, request_method, operation_object, path_item_parameters)
      hooks = @config.hooks
      parameters = [].concat(operation_object['parameters'].to_a, path_item_parameters.to_a)
      required_body = operation_object.dig('requestBody', 'required') == true
      operation_id = operation_object['operationId']
      result = operation_object.dig('requestBody', 'content')&.map do |content_type, content|
        Request.new(path:, request_method:, operation_id:, parameters:, content_type:,
                    content_schema: content['schema'], required_body:, hooks:, openapi_version:)
      end || []
      unless required_body
        result << Request.new(path:, request_method:, operation_id:, parameters:, content_type: nil, content_schema: nil,
                              required_body:, hooks:, openapi_version:)
      end
      result
    end

    def build_responses(operation_object)
      Array(operation_object['responses']).flat_map do |status, response_object|
        response_object['content']&.map do |content_type, content_object|
          content_schema = content_object['schema']
          Response.new(status:, response_object:, content_type:, content_schema:, openapi_version:)
        end || Response.new(status:, response_object:, content_type: nil,
                            content_schema: nil, openapi_version:)
      end
    end

    def detect_version(resolved)
      (resolved['openapi'] || resolved['swagger'])[0..2]
    end
  end
end
