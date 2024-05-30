# frozen_string_literal: true

require_relative 'router/path_template'
require_relative 'router/response_matcher'

module OpenapiFirst
  # Router can map requests / responses to their API definition
  class Router
    # Returned by {#match}
    RequestMatch = Data.define(:request_definition, :params, :error, :responses) do
      def match_response(status:, content_type:)
        responses&.match(status, content_type)
      end
    end

    # Returned by {#routes} to introspect all routes
    Route = Data.define(:path, :request_method, :requests, :responses)

    # @visibility private
    class Routes
      include Enumerable

      def initialize(static, dynamic)
        @static = static
        @dynamic = dynamic
      end

      def each
        [@static, @dynamic].each do |index|
          index.each do |path, request_methods|
            request_methods.each do |request_method, content|
              next if request_method == :template

              yield(Route.new(path, request_method, content[:requests], content[:responses]))
            end
          end
        end
      end
    end

    NOT_FOUND = RequestMatch.new(request_definition: nil, params: nil, responses: nil, error: Failure.new(:not_found))
    private_constant :NOT_FOUND

    def initialize
      @static = {}
      @dynamic = {} # TODO: use a trie or similar
    end

    # Returns an enumerator of all routes
    def routes
      Routes.new(@static, @dynamic)
    end

    # Add a request definition
    def add_request(request, request_method:, path:, content_type: nil)
      (route_at(path, request_method)[:requests])[content_type] = request
    end

    # Add a response definition
    def add_response(response, request_method:, path:, status:, response_content_type: nil)
      (route_at(path, request_method)[:responses]).add_response(status, response_content_type, response)
    end

    # Return all request objects that match the given path and request method
    def match(request_method, path, content_type: nil)
      path_item, params = find_path_item(path)
      return NOT_FOUND unless path_item

      content_types = path_item.dig(request_method, :requests)
      return NOT_FOUND.with(error: Failure.new(:method_not_allowed)) unless content_types

      request_definition = content_types[content_type]
      unless request_definition
        message = "#{content_type_err(content_type)} Content-Type should be #{content_types.keys.join(' or ')}."
        return NOT_FOUND.with(error: Failure.new(:unsupported_media_type, message:))
      end

      responses = path_item.dig(request_method, :responses)
      RequestMatch.new(request_definition:, params:, error: nil, responses:)
    end

    private

    def route_at(path, request_method)
      path_item = if PathTemplate.template?(path)
                    @dynamic[path] ||= { template: PathTemplate.new(path) }
                  else
                    @static[path] ||= {}
                  end
      path_item[request_method.upcase] ||= {
        requests: ContentMatcher.new,
        responses: ResponseMatcher.new
      }
    end

    def content_type_err(content_type)
      return 'Content-Type must not be empty.' if content_type.nil? || content_type.empty?

      "Content-Type #{content_type} is not defined."
    end

    def find_path_item(request_path)
      found = @static[request_path]
      return [found, {}] if found

      @dynamic.find do |_path, path_item|
        params = path_item[:template].match(request_path)
        return [path_item, params] if params
      end
    end
  end
end
