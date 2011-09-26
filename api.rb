require 'bundler/setup'

require 'eventmachine'
require 'em-http'
require 'evma_httpserver'
require 'rack'
require 'json'
require 'uri'

CONFIG = if ENV['RUT']
  {
    :RutAlianza   => ENV['RUT'],
    :Local        => ENV['LOCAL'],
    :Clave        => ENV['PASSWORD']
  }
else
  yml = YAML.load_file('./config.yml')
  {
    :RutAlianza   => yml[:rut],
    :Local        => yml[:local],
    :Clave        => yml[:password]
  }
end

class RutChecker
  URL = 'http://validasocioexterno.elmercurio.cl/ValidaSocio_Externo.asmx/Alianza_ValidaSocio'

  include EM::Deferrable

  def initialize(rut)
    
    request = EM::HttpRequest.new(URL).get({
      :query => CONFIG.dup.update(:RutSocio => rut)
    })

    # This is called if the request completes successfully (whatever the code)
    request.callback {
      if request.response_header.status == 200
        
        body = request.response.to_s.gsub('&lt;', '<').gsub('&gt;', '>')

        body =~ /<Estado>(.+)<\/Estado>/
        p [:match, body]
        
        self.succeed($1.to_i == 1)
      else
        self.fail(request.response_header.status)
      end
    }

    # This is called if the request totally failed
    request.errback {
      self.fail("Error making API call")
    }
  end
end


class Api < EM::Connection
  include EM::HttpServer

   def post_init
     super
     no_environment_strings
   end

  def process_http_request
    # the http request details are available via the following instance variables:
    #   @http_protocol
    #   @http_request_method
    #   @http_cookie
    #   @http_if_none_match
    #   @http_content_type
    #   @http_path_info
    #   @http_request_uri
    #   @http_query_string
    #   @http_post_content
    #   @http_headers
    
    params = Rack::Utils.parse_nested_query(@http_query_string)
    response = EM::DelegatedHttpResponse.new(self)
    response.content_type 'application/json'
    
    checker = RutChecker.new(params['rut'])
    
    checker.callback do |r|
      response.status = 200
      response.content = json_response(params['rut'], r)
      response.send_response
    end
    
    checker.errback do |r|
      response.status = 500
      response.content = r.inspect
      response.send_response
    end
  end
  
  
  protected
  
  def json_response(rut, result)
    JSON.unparse(
      :rut => rut,
      :result => result
    )
  end
end

EM.run{
  EM.start_server '0.0.0.0', ENV['PORT'], Api
}