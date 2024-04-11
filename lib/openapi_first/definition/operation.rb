# frozen_string_literal: true

require 'forwardable'
require 'set'
require 'openapi_parameters'
require_relative 'request_body'
require_relative 'responses'

module OpenapiFirst
  class Definition
    # Represents an operation object in the OpenAPI 3.X specification.
    # Use this class to access information about the operation. Use `#[key]` to read the raw data.
    # When using the middleware you can access the operation object via `env[OpenapiFirst::REQUEST].operation`.
    class Operation
      extend Forwardable

      def_delegators :operation_object,
                     :[]

      def initialize(path, request_method, operation_object)
        @path = path
        @method = request_method
        @operation_object = operation_object
        @responses = Responses.new(self, operation_object['responses'])
        @request_body = RequestBody.new(operation_object['requestBody']) if operation_object['requestBody']
      end

      # @attr_reader [String] path The path of the operation as in the API description.
      attr_reader :path

      # @attr_reader [String] method The (downcased) request method of the operation.
      # Example: "get"
      attr_reader :method
      alias request_method method

      # @attr_reader [RequestBody, nil] request_body The request body of the operation, or `nil` if not present.
      attr_reader :request_body

      # Returns the operation ID as defined in the API description.
      # @return [String, nil]
      def operation_id
        operation_object['operationId']
      end

      # Checks if the operation is a read operation.
      # This is the case for all request methods except POST, PUT, PATCH and DELETE.
      # @return [Boolean] `true` if the operation is a read operation, `false` otherwise.
      def read?
        !write?
      end

      # Checks if the operation is a write operation.
      # This is the case for POST, PUT, PATCH and DELETE request methods.
      # @return [Boolean] `true` if the operation is a write operation, `false` otherwise.
      # @deprecated Use {#write?} instead.
      def write?
        WRITE_METHODS.include?(method)
      end

      # Checks if a response status is defined for this operation.
      # @param status [Integer, String] The response status to check.
      # @return [Boolean] `true` if the response status is defined, `false` otherwise.
      def response_status_defined?(status)
        responses.status_defined?(status)
      end

      # Returns the response object for a given status.
      # @param status [Integer, String] The response status.
      # @param content_type [String] Content-Type of the current response.
      # @return [Response, nil] The response object for the given status, or `nil` if not found.
      def response_for(status, content_type)
        responses.response_for(status, content_type)
      end

      # Returns a unique name for this operation. Used for generating error messages.
      # @visibility private
      def name
        @name ||= "#{method.upcase} #{path}".freeze
      end

      %i[query path header cookie].each do |location|
        define_method("#{location}_parameters") do
          all_parameters[location]
        end
      end

      private

      WRITE_METHODS = Set.new(%w[post put patch delete]).freeze
      private_constant :WRITE_METHODS

      IGNORED_HEADERS = Set['Content-Type', 'Accept', 'Authorization'].freeze
      private_constant :IGNORED_HEADERS

      attr_reader :operation_object, :responses

      def all_parameters
        @all_parameters ||= operation_object.fetch('parameters', []).group_by { _1['in']&.to_sym }.freeze
      end

      def build_parameters(parameters, klass)
        klass.new(parameters) if parameters.any?
      end
    end
  end
end
