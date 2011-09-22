require 'net/http'

module DataMapperRest
  # Somewhat stolen from ActiveResource
  # TODO: Support https?
  class Connection
    attr_accessor :uri, :format

    def initialize(uri, format)
      @uri = uri
      @format = Format.new(format)
    end

    # this is used to run the http verbs like http_post, http_put, http_delete etc.
    # TODO: handle nested resources, see prefix in ActiveResource
    def method_missing(method, *args)
      if verb = method.to_s.match(/\Ahttp_(get|post|put|delete|head)\z/)

        orig_uri, @uri = @uri, @uri.dup
        begin
          path, query = args[0].split('?', 2)
          @uri.path = "#{path}.#{@format.extension}#{'?' << query if query}" # Should be the form of /resources
          data = {args[0].split("_", 3).last => args[1].to_json}# args[0] should seems like belinkr_persister_models}
          run_verb(verb.to_s.split('_').last, data) 
        ensure
          @uri = orig_uri
        end
      end
    end

    
    protected

      def run_verb(verb, data = nil)
        request do |http|
          klass = DataMapper::Ext::Module.find_const(Net::HTTP, DataMapper::Inflector.camelize(verb))
          request = klass.new(@uri.to_s, @format.header)
          request.basic_auth(@uri.user, @uri.password) if @uri.user && @uri.password
          request.form_data = data # Added for tinto
          result = http.request(request) #Removed second arg for tinto

          handle_response(result)
        end
      end

      def request(&block)
        res = nil
        Net::HTTP.start(@uri.host, @uri.port) do |http|
          res = yield(http)
        end
        res
      end

      # Handles response and error codes from remote service.
      def handle_response(response)
        case response.code.to_i
          when 301,302
            raise(Redirection.new(response))
          when 200...400
            response
          when 400
            raise(BadRequest.new(response))
          when 401
            raise(UnauthorizedAccess.new(response))
          when 403
            raise(ForbiddenAccess.new(response))
          when 404
            raise(ResourceNotFound.new(response))
          when 405
            raise(MethodNotAllowed.new(response))
          when 409
            raise(ResourceConflict.new(response))
          when 422
            raise(ResourceInvalid.new(response))
          when 401...500
            raise(ClientError.new(response))
          when 500...600
            raise(ServerError.new(response))
          else
            raise(ConnectionError.new(response, "Unknown response code: #{response.code}"))
        end
      end

  end
end
