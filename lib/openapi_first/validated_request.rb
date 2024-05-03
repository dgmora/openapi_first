# frozen_string_literal: true

require 'forwardable'

module OpenapiFirst
  # A validated request (see Request). It can be valid or not.
  class ValidatedRequest
    extend Forwardable

    def initialize(request_values, error:, operation: nil, path_item: nil)
      @request_values = request_values
      @error = error
      @operation = operation
      @path_item = path_item
    end

    def_delegators :@request_values, :path_parameters, :query, :headers, :cookies, :body
    def_delegators :@operation, :operation_id

    # Returns the error object if validation failed.
    # @return [Failure, nil]
    attr_reader :error

    attr_reader :operation, :path_item

    alias parsed_body body
    alias query_parameters query

    # Checks if the request is valid.
    # @return [Boolean] true if the request is valid, false otherwise.
    def valid?
      error.nil?
    end

    def params
      @params ||= query.merge(path_parameters)
    end

    def known?
      !@operation.nil?
    end
  end
end
