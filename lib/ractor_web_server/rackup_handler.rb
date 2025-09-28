# frozen_string_literal: true

require "rackup" # move somewhere more suitable if needed

module RactorWebServer
  module RackupHandler # rubocop:disable Style/Documentation
    def run(app, **options)
      environment = ENV["RACK_ENV"] || "development"
      default_host = environment == "development" ? "localhost" : nil

      options.delete(:Host) || default_host
      port = options.delete(:Port) || 8080
      subscribers = options.delete(:subscribers) || {}

      server = RactorWebServer::Server.new(app: app, subscribers: subscribers, port: port)
      s = Ractor.new(server, &:run)
      loop do
        Ractor.select(s)
      end
    end

    def valid_options?(_options)
      environment = ENV["RACK_ENV"] || "development"
      default_host = environment == "development" ? "localhost" : "0.0.0.0"

      {
        "Host=HOST" => "Hostname to listen on (default: #{default_host})",
        "Port=PORT" => "Port to listen on (default: 8080)"
      }
    end
  end
end

if Object.const_defined?(:Rackup) && ::Rackup.const_defined?(:Handler)
  module Rackup
    module Handler # rubocop:disable Style/Documentation
      module RactorWebServer
        class << self
          include ::RactorWebServer::RackupHandler
        end
      end
      register :ractor_web_server, RactorWebServer
    end
  end
end
